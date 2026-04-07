"""
okx_feed.py — OKX WebSocket v5 feed for TorQ-Crypto.

Connects to the OKX WebSocket v5 public endpoint and subscribes to the
trades channel for all OKX-enabled instruments in symmap.csv.

Data flow:
  trade events  -> upd("trade", column_vectors)  via pythonfeed IPC

Reconnect:  exponential backoff 1 s -> FEED_RECONNECT_MAX (default 60 s)
Heartbeat:  send literal "ping" text every 25 s — if "pong" not received
            within 10 s, force reconnect
Backfill:   not implemented
"""

from __future__ import annotations

import asyncio
import json
import logging
import os
from typing import Any, Optional

import numpy as np
import pykx as kx
import websockets

import symmap as _symmap

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

EXCHANGE = "okx"
WS_URL = "wss://ws.okx.com:8443/ws/v5/public"

PING_INTERVAL: int = int(os.environ.get("OKX_PING_INTERVAL", "25"))
PONG_TIMEOUT: int = int(os.environ.get("OKX_PONG_TIMEOUT", "10"))
RECONNECT_MAX: int = int(os.environ.get("FEED_RECONNECT_MAX", "60"))


# ---------------------------------------------------------------------------
# Pure parse function (no pykx — unit-testable without IPC)
# ---------------------------------------------------------------------------

def _parse_trade(entry: dict[str, Any]) -> Optional[dict[str, Any]]:
    """Normalise a single entry from an OKX trades channel data array.

    Each element of ``msg["data"]`` is a trade object with:
      instId  — venue symbol (e.g. "BTC-USDT")
      tradeId — exchange trade ID (string integer)
      px      — price (string float)
      sz      — size (string float)
      side    — "buy" or "sell"
      ts      — unix milliseconds (string integer)

    Returns a plain Python dict matching the trade schema, or None to skip.
    """
    try:
        inst_id: str = entry["instId"]
        canonical = _symmap.get_canonical(inst_id, EXCHANGE)
        if canonical is None:
            return None

        try:
            seq = int(entry["tradeId"])
        except (KeyError, ValueError, TypeError):
            seq = 0

        side_raw: str = entry["side"]
        side = "buy" if side_raw == "buy" else "sell"

        return {
            "time": int(entry["ts"]) * 1_000_000,   # ms → ns
            "sym": canonical,
            "venue": EXCHANGE,
            "price": float(entry["px"]),
            "size": float(entry["sz"]),
            "side": side,
            "venue_sym": inst_id,
            "seq": seq,
        }
    except (KeyError, ValueError, TypeError) as exc:
        logger.warning("[%s] trade parse error: %s | entry=%s", EXCHANGE, exc, entry)
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


# ---------------------------------------------------------------------------
# Subscription message builder
# ---------------------------------------------------------------------------

def _build_subscribe_msg(venue_symbols: list[str]) -> str:
    return json.dumps({
        "op": "subscribe",
        "args": [{"channel": "trades", "instId": s} for s in venue_symbols],
    })


# ---------------------------------------------------------------------------
# Background ping task
# ---------------------------------------------------------------------------

async def _ping_loop(ws: Any, pong_received: asyncio.Event) -> None:
    """Send "ping" to OKX every PING_INTERVAL seconds.

    Sets *pong_received* before each ping and waits up to PONG_TIMEOUT
    seconds for it to be set again by the receive loop.  If the pong does
    not arrive in time, closes the WebSocket to trigger a reconnect.

    Runs as a background task alongside the receive loop.
    """
    while True:
        await asyncio.sleep(PING_INTERVAL)
        pong_received.clear()
        try:
            await ws.send("ping")
        except Exception:
            return  # connection already closed

        try:
            await asyncio.wait_for(pong_received.wait(), timeout=PONG_TIMEOUT)
        except asyncio.TimeoutError:
            logger.warning("[%s] pong not received within %ds — forcing reconnect",
                           EXCHANGE, PONG_TIMEOUT)
            try:
                await ws.close()
            except Exception:
                pass
            return


# ---------------------------------------------------------------------------
# Main feed loop
# ---------------------------------------------------------------------------

async def run_okx_feed(conn: Any) -> None:
    """Connect to OKX WebSocket v5 and publish normalised trade rows.

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

                pong_received = asyncio.Event()
                pong_received.set()  # no outstanding ping yet

                ping_task = asyncio.ensure_future(_ping_loop(ws, pong_received))
                try:
                    async for raw in ws:
                        # OKX responds to "ping" with the literal text "pong"
                        if raw == "pong":
                            pong_received.set()
                            continue

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
    """Dispatch a parsed OKX WebSocket v5 message."""
    event = msg.get("event")

    if event == "error":
        logger.error("[%s] error event: %s", EXCHANGE, msg)
        return

    if event == "subscribe":
        result = msg.get("arg", {})
        code = msg.get("code", "0")
        if code != "0":
            logger.error("[%s] subscribe failed: %s", EXCHANGE, msg)
        else:
            logger.info("[%s] subscribed: %s", EXCHANGE, result)
        return

    arg = msg.get("arg", {})
    channel = arg.get("channel") if isinstance(arg, dict) else None

    if channel == "trades":
        data = msg.get("data", [])
        if not isinstance(data, list):
            logger.warning("[%s] unexpected trades data type: %s", EXCHANGE, type(data))
            return
        rows = []
        for entry in data:
            row = _parse_trade(entry)
            if row is not None:
                rows.append(row)
        if rows:
            asyncio.ensure_future(_publish_trades(conn, rows))
        return

    if event is not None or channel is not None:
        logger.debug("[%s] unhandled message: event=%s channel=%s", EXCHANGE, event, channel)


async def _publish_trades(conn: Any, rows: list[dict[str, Any]]) -> None:
    try:
        await conn("upd", kx.SymbolAtom("trade"), _trade_cols(rows))
    except Exception as exc:
        logger.error("[%s] trade IPC failed: %s", EXCHANGE, exc)
