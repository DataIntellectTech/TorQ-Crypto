"""
kraken_feed.py — Kraken WebSocket v2 feed for TorQ-Crypto.

Connects to the Kraken WebSocket v2 endpoint and subscribes to the trade
channel for all Kraken-enabled instruments in symmap.csv.

Data flow:
  trade events  -> upd("trade", column_vectors)  via pythonfeed IPC

Reconnect:  exponential backoff 1 s -> FEED_RECONNECT_MAX (default 60 s)
Heartbeat:  send {"method":"ping"} every 30 s — Kraken drops idle connections
Backfill:   not implemented (Kraken REST is rate-limited; not required)
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from datetime import datetime, timezone
from typing import Any, Optional

import pandas as pd
import pykx as kx
import websockets

import symmap as _symmap

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

EXCHANGE = "kraken"
WS_URL = "wss://ws.kraken.com/v2"

PING_INTERVAL: int = int(os.environ.get("KRAKEN_PING_INTERVAL", "30"))
RECONNECT_MAX: int = int(os.environ.get("FEED_RECONNECT_MAX", "60"))


# ---------------------------------------------------------------------------
# Time helpers
# ---------------------------------------------------------------------------

def _iso8601_to_ns(ts: str) -> int:
    """Parse an ISO 8601 timestamp string to nanoseconds since Unix epoch.

    Kraken sends timestamps like "2023-09-14T13:57:31.574862Z".
    datetime.fromisoformat handles the UTC 'Z' suffix on Python 3.11+;
    for earlier versions we normalise the suffix manually.
    """
    # Normalise 'Z' → '+00:00' for compatibility with Python < 3.11
    normalised = ts.replace("Z", "+00:00")
    dt = datetime.fromisoformat(normalised)
    # datetime.fromisoformat preserves tzinfo; ensure UTC
    if dt.tzinfo is None:
        dt = dt.replace(tzinfo=timezone.utc)
    epoch = datetime(1970, 1, 1, tzinfo=timezone.utc)
    delta = dt - epoch
    total_ns = int(delta.total_seconds() * 1_000_000_000)
    return total_ns


# ---------------------------------------------------------------------------
# Pure parse function (no pykx — unit-testable without IPC)
# ---------------------------------------------------------------------------

def _parse_trade(entry: dict[str, Any]) -> Optional[dict[str, Any]]:
    """Normalise a single entry from a Kraken trade channel data array.

    Each element of ``msg["data"]`` is a trade object with:
      symbol    — venue symbol (e.g. "XBT/USD")
      price     — float
      qty       — float
      side      — "buy" or "sell"
      timestamp — ISO 8601 string

    Returns a plain Python dict matching the trade schema, or None to skip.
    """
    try:
        venue_sym: str = entry["symbol"]
        canonical = _symmap.get_canonical(venue_sym, EXCHANGE)
        if canonical is None:
            return None
        side_raw: str = entry["side"]
        side = "buy" if side_raw == "buy" else "sell"
        return {
            "time": _iso8601_to_ns(entry["timestamp"]),
            "sym": canonical,
            "venue": EXCHANGE,
            "price": float(entry["price"]),
            "size": float(entry["qty"]),
            "side": side,
            "venue_sym": venue_sym,
            "seq": 0,
        }
    except (KeyError, ValueError, TypeError) as exc:
        logger.warning("[%s] trade parse error: %s | entry=%s", EXCHANGE, exc, entry)
        return None


# ---------------------------------------------------------------------------
# IPC helpers — convert row dicts to kdb+ column vector lists
# ---------------------------------------------------------------------------

def _trade_cols(rows: list[dict[str, Any]]) -> list:
    """Convert trade row dicts to a kdb+ column-vector list for upd["trade"; ...]."""
    return [
        kx.toq(pd.to_datetime([r["time"] for r in rows], unit="ns")),
        kx.SymbolVector([r["sym"] for r in rows]),
        kx.SymbolVector([r["venue"] for r in rows]),
        kx.FloatVector([r["price"] for r in rows]),
        kx.FloatVector([r["size"] for r in rows]),
        kx.SymbolVector([r["side"] for r in rows]),
        kx.SymbolVector([r["venue_sym"] for r in rows]),
        kx.LongVector([r["seq"] for r in rows]),
    ]


# ---------------------------------------------------------------------------
# Subscription message builder
# ---------------------------------------------------------------------------

def _build_subscribe_msg(venue_symbols: list[str]) -> str:
    return json.dumps({
        "method": "subscribe",
        "params": {
            "channel": "trade",
            "symbol": venue_symbols,
        },
    })


# ---------------------------------------------------------------------------
# Background ping task
# ---------------------------------------------------------------------------

async def _ping_loop(ws: Any) -> None:
    """Send a ping to Kraken every PING_INTERVAL seconds.

    Runs as a background task alongside the receive loop.  If the connection
    is closed the task exits cleanly.
    """
    while True:
        await asyncio.sleep(PING_INTERVAL)
        try:
            await ws.send(json.dumps({"method": "ping"}))
        except Exception:
            # WebSocket is closed — let the receive loop handle reconnection
            return


# ---------------------------------------------------------------------------
# Main feed loop
# ---------------------------------------------------------------------------

async def run_kraken_feed(conn: Any) -> None:
    """Connect to Kraken WebSocket v2 and publish normalised trade rows.

    Runs forever.  On disconnect, reconnects with exponential backoff.
    """
    enabled = _symmap.get_enabled_for_venue(EXCHANGE)
    if not enabled:
        logger.warning("[%s] No enabled symbols — feed will not start", EXCHANGE)
        return

    venue_symbols = [r["venue_symbol"] for r in enabled]
    subscribe_msg = _build_subscribe_msg(venue_symbols)
    backoff = 1.0

    while True:
        logger.info("[%s] Connecting to %s", EXCHANGE, WS_URL)
        try:
            async with websockets.connect(
                WS_URL,
                ping_interval=None,   # heartbeat managed manually via ping_loop
                open_timeout=15,
            ) as ws:
                logger.info("[%s] Connected — subscribing to %s", EXCHANGE, venue_symbols)
                await ws.send(subscribe_msg)
                backoff = 1.0

                ping_task = asyncio.ensure_future(_ping_loop(ws))
                try:
                    async for raw in ws:
                        try:
                            msg = json.loads(raw)
                        except json.JSONDecodeError as exc:
                            logger.warning("[%s] JSON decode error: %s", EXCHANGE, exc)
                            continue

                        _handle_message(msg, conn)

                finally:
                    ping_task.cancel()
                    try:
                        await ping_task
                    except asyncio.CancelledError:
                        pass

        except (websockets.exceptions.ConnectionClosed, OSError) as exc:
            logger.warning("[%s] WebSocket disconnected: %s", EXCHANGE, exc)
        except Exception as exc:
            logger.error("[%s] Unexpected error: %s", EXCHANGE, exc)

        logger.info("[%s] Reconnecting in %.1fs", EXCHANGE, backoff)
        await asyncio.sleep(backoff)
        backoff = min(backoff * 2, RECONNECT_MAX)


def _handle_message(msg: dict[str, Any], conn: Any) -> None:
    """Dispatch a parsed Kraken WebSocket v2 message.

    Separated from the async loop so it can be exercised in sync unit tests
    (the conn parameter is unused for non-trade channels).
    """
    channel = msg.get("channel")
    msg_type = msg.get("type")

    if msg_type == "pong":
        # Expected response to our periodic ping — no action needed
        return

    if channel == "heartbeat":
        # Kraken sends these automatically — no action needed
        return

    if channel == "status":
        logger.info("[%s] status: %s", EXCHANGE, msg)
        return

    if channel == "trade":
        data = msg.get("data", [])
        if not isinstance(data, list):
            logger.warning("[%s] unexpected trade data type: %s", EXCHANGE, type(data))
            return
        rows = []
        for entry in data:
            row = _parse_trade(entry)
            if row is not None:
                rows.append(row)
        if rows:
            asyncio.ensure_future(_publish_trades(conn, rows))
        return

    # Unknown message type — log at debug level so we don't flood logs
    if channel is not None or msg_type is not None:
        logger.debug("[%s] unhandled message: channel=%s type=%s", EXCHANGE, channel, msg_type)


async def _publish_trades(conn: Any, rows: list[dict[str, Any]]) -> None:
    try:
        await conn("upd", kx.SymbolAtom("trade"), _trade_cols(rows))
    except Exception as exc:
        logger.error("[%s] trade IPC failed: %s", EXCHANGE, exc)