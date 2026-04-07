"""
binance_feed.py — Binance WebSocket feed for TorQ-Crypto.

Connects to the Binance combined stream endpoint and subscribes to:
  {sym}@trade          — real-time trade events
  {sym}@depth5@100ms   — top-5 order book snapshots (best bid/ask)

Note on depth format: Binance @depth5 snapshots use 'bids'/'asks' fields and
do not include the symbol or a timestamp in the data payload.  The symbol is
extracted from the stream name; wall-clock time is used for the quote timestamp.
The prompt spec describes 'depthUpdate' / b / a fields (diff-depth format);
depth5 is used here because it avoids maintaining a local order book.

Data flow:
  trade events   -> upd("trade", column_vectors)  via pythonfeed IPC
  depth5 events  -> upd("quote", column_vectors)  via pythonfeed IPC

Reconnect: exponential backoff 1 s -> FEED_RECONNECT_MAX (default 60 s)
Heartbeat: reconnect if no message in BINANCE_HEARTBEAT_TIMEOUT s (default 30)
Backfill:  on reconnect, if gap > 30 s fetch missed trades via REST aggTrades
"""

from __future__ import annotations

import asyncio
import datetime
import json
import logging
import os
import time
from typing import Any, Optional

import aiohttp
import numpy as np
import pykx as kx
import websockets

import symmap as _symmap

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

EXCHANGE = "binance"
WS_BASE = "wss://stream.binance.com:9443/stream"
REST_AGG_TRADES = "https://api.binance.com/api/v3/aggTrades"

HEARTBEAT_TIMEOUT: int = int(os.environ.get("BINANCE_HEARTBEAT_TIMEOUT", "30"))
RECONNECT_MAX: int = int(os.environ.get("FEED_RECONNECT_MAX", "60"))
_BACKFILL_MIN_GAP_S = 30  # only backfill if the gap exceeds this many seconds


# ---------------------------------------------------------------------------
# Time helpers
# ---------------------------------------------------------------------------

def _ms_to_ns(ms: int) -> int:
    """Milliseconds since Unix epoch → nanoseconds since Unix epoch."""
    return int(ms) * 1_000_000


def _ns_to_ms(ns: int) -> int:
    """Nanoseconds since Unix epoch → milliseconds since Unix epoch."""
    return int(ns) // 1_000_000


# ---------------------------------------------------------------------------
# Pure parse functions (no pykx — unit-testable without IPC)
# ---------------------------------------------------------------------------

def _parse_trade(msg: dict[str, Any]) -> Optional[dict[str, Any]]:
    """Normalise a Binance @trade combined-stream message.

    Returns a plain Python dict matching the trade schema, or None to skip.
    Field mapping:
      e="trade"  T=trade_time_ms  s=venue_sym  p=price  q=qty  m=is_buyer_maker
    """
    try:
        data = msg.get("data", msg)
        if data.get("e") != "trade":
            return None
        venue_sym: str = data["s"]
        canonical = _symmap.get_canonical(venue_sym, EXCHANGE)
        if canonical is None:
            return None
        return {
            "time": _ms_to_ns(data["T"]),
            "sym": canonical,
            "venue": EXCHANGE,
            "price": float(data["p"]),
            "size": float(data["q"]),
            "side": "sell" if data.get("m") else "buy",
            "venue_sym": venue_sym,
            "seq": 0,
        }
    except (KeyError, ValueError, TypeError) as exc:
        logger.warning("[%s] trade parse error: %s", EXCHANGE, exc)
        return None


def _parse_depth(msg: dict[str, Any]) -> Optional[dict[str, Any]]:
    """Normalise a Binance @depth5 combined-stream message.

    The depth5 payload uses 'bids'/'asks' (not 'b'/'a') and lacks both a
    timestamp and the symbol in the data dict.  Symbol is extracted from the
    'stream' field in the outer combined-stream envelope.

    Returns a plain Python dict matching the quote schema, or None to skip.
    """
    try:
        data = msg.get("data", msg)
        bids = data.get("bids")
        asks = data.get("asks")
        if not bids or not asks:
            return None

        # Venue symbol encoded as the first segment of the stream name:
        # "btcusdt@depth5@100ms" → "BTCUSDT"
        stream: str = msg.get("stream", "")
        venue_sym = stream.split("@")[0].upper()
        if not venue_sym:
            return None

        canonical = _symmap.get_canonical(venue_sym, EXCHANGE)
        if canonical is None:
            return None

        best_bid = max(bids, key=lambda x: float(x[0]))
        best_ask = min(asks, key=lambda x: float(x[0]))

        return {
            "time": int(time.time() * 1e9),          # wall-clock ns (no event ts in depth5)
            "sym": canonical,
            "venue": EXCHANGE,
            "bid": float(best_bid[0]),
            "ask": float(best_ask[0]),
            "bsize": float(best_bid[1]),
            "asize": float(best_ask[1]),
            "venue_sym": venue_sym,
        }
    except (KeyError, ValueError, TypeError, IndexError) as exc:
        logger.warning("[%s] depth parse error: %s", EXCHANGE, exc)
        return None


# ---------------------------------------------------------------------------
# IPC helpers — convert row dicts to kdb+ column vector lists
# ---------------------------------------------------------------------------

def _trade_cols(rows: list[dict[str, Any]]) -> list:
    """Convert trade row dicts to a kdb+ column-vector list for upd["trade"; ...]."""
    times_ns = np.array([r["time"] for r in rows], dtype="int64").view("datetime64[ns]")
    return [
        kx.toq(times_ns),
        kx.SymbolVector([r["sym"] for r in rows]),
        kx.SymbolVector([r["venue"] for r in rows]),
        kx.FloatVector([r["price"] for r in rows]),
        kx.FloatVector([r["size"] for r in rows]),
        kx.SymbolVector([r["side"] for r in rows]),
        kx.SymbolVector([r["venue_sym"] for r in rows]),
        kx.LongVector([r["seq"] for r in rows]),
    ]


def _quote_cols(rows: list[dict[str, Any]]) -> list:
    """Convert quote row dicts to a kdb+ column-vector list for upd["quote"; ...]."""
    times_ns = np.array([r["time"] for r in rows], dtype="int64").view("datetime64[ns]")
    return [
        kx.toq(times_ns),
        kx.SymbolVector([r["sym"] for r in rows]),
        kx.SymbolVector([r["venue"] for r in rows]),
        kx.FloatVector([r["bid"] for r in rows]),
        kx.FloatVector([r["ask"] for r in rows]),
        kx.FloatVector([r["bsize"] for r in rows]),
        kx.FloatVector([r["asize"] for r in rows]),
        kx.SymbolVector([r["venue_sym"] for r in rows]),
    ]


# ---------------------------------------------------------------------------
# Backfill
# ---------------------------------------------------------------------------

async def _backfill(conn: Any, venue_sym: str, canonical: str) -> None:
    """Fetch missed trades from Binance REST since the last kdb+ record.

    Queries pythonfeed for the max trade timestamp for this sym+venue.
    Only runs if the gap exceeds _BACKFILL_MIN_GAP_S seconds.
    On any REST failure: logs a warning and returns — never raises.
    """
    try:
        max_ts = await conn(
            ".pythonfeed.maxtime",
            kx.SymbolAtom(canonical),
            kx.SymbolAtom(EXCHANGE),
        )
        ts_py = max_ts.py()
        if not isinstance(ts_py, datetime.datetime):
            return  # null (NaT) — no prior data
        # pykx returns naive datetime; treat as UTC
        ts_unix_s = ts_py.replace(tzinfo=datetime.timezone.utc).timestamp()
        gap_s = time.time() - ts_unix_s
        if gap_s < _BACKFILL_MIN_GAP_S:
            return
        since_ms = int(ts_unix_s * 1000)
    except Exception as exc:
        logger.warning("[%s] maxtime query failed for %s: %s", EXCHANGE, canonical, exc)
        return

    url = f"{REST_AGG_TRADES}?symbol={venue_sym}&startTime={since_ms}"
    rows: list[dict] = []
    async with aiohttp.ClientSession() as session:
        try:
            async with session.get(url, timeout=aiohttp.ClientTimeout(total=15)) as resp:
                resp.raise_for_status()
                trades = await resp.json()
        except Exception as exc:
            logger.warning("[%s] REST backfill failed for %s: %s", EXCHANGE, venue_sym, exc)
            return

    for t in trades:
        try:
            rows.append({
                "time": _ms_to_ns(t["T"]),
                "sym": canonical,
                "venue": EXCHANGE,
                "price": float(t["p"]),
                "size": float(t["q"]),
                "side": "sell" if t.get("m") else "buy",
                "venue_sym": venue_sym,
                "seq": 0,
            })
        except (KeyError, ValueError, TypeError):
            pass

    if not rows:
        return

    try:
        await conn("upd", kx.SymbolAtom("trade"), _trade_cols(rows))
        logger.info("[%s] Backfilled %d trades for %s", EXCHANGE, len(rows), canonical)
    except Exception as exc:
        logger.warning("[%s] Backfill IPC publish failed for %s: %s", EXCHANGE, canonical, exc)


# ---------------------------------------------------------------------------
# WebSocket URL builder
# ---------------------------------------------------------------------------

def _build_ws_url(venue_symbols: list[str]) -> str:
    streams = "/".join(
        f"{s.lower()}@trade/{s.lower()}@depth5@100ms"
        for s in venue_symbols
    )
    return f"{WS_BASE}?streams={streams}"


# ---------------------------------------------------------------------------
# Main feed loop
# ---------------------------------------------------------------------------

async def run_binance_feed(conn: Any) -> None:
    """Connect to Binance combined stream and publish normalised rows.

    Runs forever.  On disconnect or heartbeat timeout, reconnects with
    exponential backoff.  Triggers REST backfill for all symbols on each
    successful connect.
    """
    enabled = _symmap.get_enabled_for_venue(EXCHANGE)
    if not enabled:
        logger.warning("[%s] No enabled symbols — feed will not start", EXCHANGE)
        return

    venue_symbols = [r["venue_symbol"] for r in enabled]
    url = _build_ws_url(venue_symbols)
    backoff = 1.0

    while True:
        logger.info("[%s] Connecting to %s", EXCHANGE, url)
        try:
            async with websockets.connect(
                url,
                ping_interval=None,   # heartbeat managed manually
                open_timeout=15,
            ) as ws:
                logger.info("[%s] Connected", EXCHANGE)
                backoff = 1.0

                # Kick off backfill for all symbols (don't block the receive loop)
                for row in enabled:
                    asyncio.ensure_future(
                        _backfill(conn, row["venue_symbol"], row["canonical_symbol"])
                    )

                while True:
                    try:
                        raw = await asyncio.wait_for(
                            ws.recv(), timeout=HEARTBEAT_TIMEOUT
                        )
                    except asyncio.TimeoutError:
                        logger.warning(
                            "[%s] No message in %ds — reconnecting",
                            EXCHANGE, HEARTBEAT_TIMEOUT,
                        )
                        break

                    try:
                        msg = json.loads(raw)
                    except json.JSONDecodeError as exc:
                        logger.warning("[%s] JSON decode error: %s", EXCHANGE, exc)
                        continue

                    trade_row = _parse_trade(msg)
                    if trade_row:
                        try:
                            await conn("upd", kx.SymbolAtom("trade"), _trade_cols([trade_row]))
                        except Exception as exc:
                            logger.error("[%s] trade IPC failed: %s", EXCHANGE, exc)

                    depth_row = _parse_depth(msg)
                    if depth_row:
                        try:
                            await conn("upd", kx.SymbolAtom("quote"), _quote_cols([depth_row]))
                        except Exception as exc:
                            logger.error("[%s] quote IPC failed: %s", EXCHANGE, exc)

        except (websockets.exceptions.ConnectionClosed, OSError) as exc:
            logger.warning("[%s] WebSocket disconnected: %s", EXCHANGE, exc)
        except Exception as exc:
            logger.error("[%s] Unexpected error: %s", EXCHANGE, exc)

        logger.info("[%s] Reconnecting in %.1fs", EXCHANGE, backoff)
        await asyncio.sleep(backoff)
        backoff = min(backoff * 2, RECONNECT_MAX)
