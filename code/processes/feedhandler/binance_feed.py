"""binance_feed.py — Binance WebSocket feed for trades and top-of-book data.

Connects to the Binance combined stream endpoint for all enabled symbols,
publishing normalised rows to kdb+ via IPC.

Streams opened per symbol:
  {sym}@trade          -> trade table
  {sym}@depth5@100ms   -> exchange_top table (5-level depth, 100 ms updates)

Reconnect logic:
  - Exponential backoff starting at 1 s, doubling each attempt, capped at
    FEED_RECONNECT_MAX (default 60 s).
  - On reconnect, queries kdb+ for the most recent trade timestamp per sym and
    backfills gaps via GET /api/v3/aggTrades.
"""

import asyncio
import json
import logging
import os
import time
from datetime import datetime, timezone
from typing import Optional

import aiohttp
import pykx as kx
import websockets

logger = logging.getLogger("binance")

WS_BASE = "wss://stream.binance.com:9443/stream?streams="
REST_BASE = "https://api.binance.com"
HEARTBEAT_TIMEOUT = int(os.environ.get("BINANCE_HEARTBEAT_TIMEOUT", "30"))
RECONNECT_MAX = int(os.environ.get("FEED_RECONNECT_MAX", "60"))


# ---------------------------------------------------------------------------
# Normalisation helpers
# ---------------------------------------------------------------------------

def _ts_now() -> kx.TimestampAtom:
    return kx.TimestampAtom(datetime.now(timezone.utc))


def _trade_rows_to_cols(rows: list) -> kx.List:
    """Convert list of trade row dicts to q column vectors (trade table order)."""
    return kx.List([
        kx.TimestampVector([r["time"].py() for r in rows]),
        kx.SymbolVector([r["sym"].py() for r in rows]),
        kx.SymbolVector([r["exchange"].py() for r in rows]),
        kx.FloatVector([r["price"] for r in rows]),
        kx.FloatVector([r["size"] for r in rows]),
        kx.SymbolVector([r["side"].py() for r in rows]),
        kx.SymbolVector([r["venue_sym"].py() for r in rows]),
    ])


def _exchange_top_row_to_cols(row: dict) -> kx.List:
    """Convert a single exchange_top row dict to q column vectors."""
    ts = row["time"].py()
    return kx.List([
        kx.TimestampVector([ts]),
        kx.SymbolVector([row["sym"].py()]),
        kx.TimestampVector([ts]),
        kx.SymbolVector([row["exchange"].py()]),
        kx.FloatVector([row["bid"]]),
        kx.FloatVector([row["bidSize"]]),
        kx.FloatVector([row["ask"]]),
        kx.FloatVector([row["askSize"]]),
    ])


def _norm_trade(msg: dict, canonical: str, venue_sym: str) -> dict:
    """Normalise a Binance @trade message into a trade-table row."""
    side = "buy" if msg.get("m") is False else "sell"  # m=True means market maker (sell side)
    return {
        "time": kx.TimestampAtom(datetime.fromtimestamp(msg["T"] / 1000, tz=timezone.utc)),
        "sym": kx.SymbolAtom(canonical),
        "exchange": kx.SymbolAtom("binance"),
        "price": float(msg["p"]),
        "size": float(msg["q"]),
        "side": kx.SymbolAtom(side),
        "venue_sym": kx.SymbolAtom(venue_sym),
    }


def _norm_depth(msg: dict, canonical: str) -> Optional[dict]:
    """Extract best bid/ask from a Binance @depth5 snapshot message."""
    bids = msg.get("bids", [])
    asks = msg.get("asks", [])
    if not bids or not asks:
        return None
    return {
        "time": _ts_now(),
        "sym": kx.SymbolAtom(canonical),
        "exchangeTime": _ts_now(),
        "exchange": kx.SymbolAtom("binance"),
        "bid": float(bids[0][0]),
        "bidSize": float(bids[0][1]),
        "ask": float(asks[0][0]),
        "askSize": float(asks[0][1]),
    }


# ---------------------------------------------------------------------------
# Backfill
# ---------------------------------------------------------------------------

async def _backfill(
    session: aiohttp.ClientSession,
    conn: kx.QConnection,
    venue_sym: str,
    canonical: str,
    since_ms: int,
) -> None:
    """Fetch aggTrades since since_ms and publish to kdb+."""
    url = f"{REST_BASE}/api/v3/aggTrades"
    params = {"symbol": venue_sym.upper(), "startTime": since_ms, "limit": 1000}
    count = 0
    try:
        async with session.get(url, params=params, timeout=aiohttp.ClientTimeout(total=30)) as resp:
            resp.raise_for_status()
            trades = await resp.json()
        rows = []
        for t in trades:
            side = "sell" if t.get("m") else "buy"
            rows.append({
                "time": kx.TimestampAtom(datetime.fromtimestamp(t["T"] / 1000, tz=timezone.utc)),
                "sym": kx.SymbolAtom(canonical),
                "exchange": kx.SymbolAtom("binance"),
                "price": float(t["p"]),
                "size": float(t["q"]),
                "side": kx.SymbolAtom(side),
                "venue_sym": kx.SymbolAtom(venue_sym),
            })
        if rows:
            conn("upd", kx.SymbolAtom("trade"), _trade_rows_to_cols(rows))
            count = len(rows)
        logger.info("[binance] backfill %s: %d records published", canonical, count)
    except Exception as exc:
        logger.error("[binance] backfill failed for %s: %s", canonical, exc)


# ---------------------------------------------------------------------------
# Main feed coroutine
# ---------------------------------------------------------------------------

async def run(conn: kx.QConnection, symbol_map: dict[str, str]) -> None:
    """Run the Binance WebSocket feed.

    symbol_map: {venue_sym (lowercase) -> canonical_symbol}
    """
    if not symbol_map:
        logger.warning("[binance] no symbols configured, feed not started")
        return

    streams = "/".join(
        f"{sym}@trade/{sym}@depth5@100ms" for sym in symbol_map
    )
    url = WS_BASE + streams
    backoff = 1.0

    while True:
        try:
            logger.info("[binance] connecting to %s", url)
            async with websockets.connect(url, ping_interval=20, ping_timeout=10) as ws:
                backoff = 1.0  # reset on successful connect
                last_msg = time.monotonic()

                # On (re)connect: query kdb+ for gaps and backfill
                async with aiohttp.ClientSession() as session:
                    for venue_sym, canonical in symbol_map.items():
                        try:
                            max_t = conn(".pythonfeed.maxtime", kx.SymbolAtom(canonical), kx.SymbolAtom("binance"))
                            max_t_py = max_t.py()
                            # max_t_py is pandas.Timestamp or pd.NaT; .value gives ns since Unix epoch
                            if hasattr(max_t_py, "value") and max_t_py.value > 0:
                                since_ms = max_t_py.value // 1_000_000
                                await _backfill(session, conn, venue_sym, canonical, since_ms)
                        except Exception as exc:
                            logger.warning("[binance] could not determine backfill start for %s: %s", canonical, exc)

                async for raw in ws:
                    last_msg = time.monotonic()
                    if time.monotonic() - last_msg > HEARTBEAT_TIMEOUT:
                        logger.warning("[binance] heartbeat timeout, reconnecting")
                        break

                    try:
                        msg = json.loads(raw)
                    except json.JSONDecodeError:
                        continue

                    stream = msg.get("stream", "")
                    data = msg.get("data", {})

                    if "@trade" in stream:
                        venue_sym = stream.split("@")[0]
                        canonical = symbol_map.get(venue_sym)
                        if canonical:
                            row = _norm_trade(data, canonical, venue_sym)
                            conn("upd", kx.SymbolAtom("trade"), _trade_rows_to_cols([row]))
                    elif "@depth5" in stream:
                        venue_sym = stream.split("@")[0]
                        canonical = symbol_map.get(venue_sym)
                        if canonical:
                            row = _norm_depth(data, canonical)
                            if row:
                                conn("upd", kx.SymbolAtom("exchange_top"), _exchange_top_row_to_cols(row))

        except Exception as exc:
            logger.error("[binance] connection error: %s — reconnecting in %.0fs", exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, RECONNECT_MAX)
