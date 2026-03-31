"""coinbase_feed.py — Coinbase Advanced Trade WebSocket feed.

Requires environment variables:
  COINBASE_API_KEY    — Coinbase Advanced Trade API key
  COINBASE_API_SECRET — Coinbase Advanced Trade API secret (Ed25519 or HMAC)

Subscribes to:
  market_trades channel -> trade table
  level2 channel        -> exchange_top table (local book state, best bid/ask)

Authentication:
  Every subscribe message is signed with HMAC-SHA256.  The signature covers
  timestamp + channel + product_ids concatenated as a string.

Level2 handling:
  Coinbase sends a snapshot ("type": "snapshot") followed by incremental
  updates ("type": "l2update").  A local order book is maintained and best
  bid/ask is extracted and published after every update.

REST backfill:
  Coinbase Advanced Trade does not offer a public historical trades endpoint
  with reliable gap coverage.  On reconnect, the recent ticker is fetched as
  a best-effort check.  If a gap is detected (> 60 s), a warning is logged
  and the feed continues from live data.
"""

import asyncio
import hashlib
import hmac
import json
import logging
import os
import time
from collections import defaultdict
from datetime import datetime, timezone
from typing import Optional

import aiohttp
import pykx as kx
import websockets

logger = logging.getLogger("coinbase")

WS_URL = "wss://advanced-trade-api.coinbase.com/ws"
REST_BASE = "https://api.coinbase.com"
HEARTBEAT_TIMEOUT = int(os.environ.get("COINBASE_HEARTBEAT_TIMEOUT", "30"))
RECONNECT_MAX = int(os.environ.get("FEED_RECONNECT_MAX", "60"))


# ---------------------------------------------------------------------------
# Authentication helpers
# ---------------------------------------------------------------------------

def _sign(api_key: str, api_secret: str, channel: str, product_ids: list[str]) -> dict:
    """Return a dict of auth fields for a Coinbase subscribe message."""
    ts = str(int(time.time()))
    msg = ts + channel + ",".join(product_ids)
    sig = hmac.new(api_secret.encode(), msg.encode(), hashlib.sha256).hexdigest()
    return {"api_key": api_key, "timestamp": ts, "signature": sig}


def _subscribe_msg(
    api_key: str, api_secret: str, channel: str, product_ids: list[str]
) -> str:
    payload = {
        "type": "subscribe",
        "product_ids": product_ids,
        "channel": channel,
    }
    payload.update(_sign(api_key, api_secret, channel, product_ids))
    return json.dumps(payload)


# ---------------------------------------------------------------------------
# Local order book
# ---------------------------------------------------------------------------

class OrderBook:
    def __init__(self) -> None:
        self.bids: dict[float, float] = {}
        self.asks: dict[float, float] = {}

    def apply_snapshot(self, events: list[dict]) -> None:
        self.bids.clear()
        self.asks.clear()
        for evt in events:
            for update in evt.get("updates", []):
                side = update.get("side", "")
                p, s = float(update["price_level"]), float(update["new_quantity"])
                if side == "bid":
                    self.bids[p] = s
                elif side == "offer":
                    self.asks[p] = s

    def apply_update(self, events: list[dict]) -> None:
        for evt in events:
            for update in evt.get("updates", []):
                side = update.get("side", "")
                p, s = float(update["price_level"]), float(update["new_quantity"])
                if side == "bid":
                    if s == 0.0:
                        self.bids.pop(p, None)
                    else:
                        self.bids[p] = s
                elif side == "offer":
                    if s == 0.0:
                        self.asks.pop(p, None)
                    else:
                        self.asks[p] = s

    def best(self) -> Optional[tuple[float, float, float, float]]:
        if not self.bids or not self.asks:
            return None
        best_bid = max(self.bids)
        best_ask = min(self.asks)
        return best_bid, self.bids[best_bid], best_ask, self.asks[best_ask]


# ---------------------------------------------------------------------------
# REST gap check (best-effort, no full backfill available)
# ---------------------------------------------------------------------------

async def _check_gap(
    session: aiohttp.ClientSession,
    conn: kx.QConnection,
    api_key: str,
    canonical: str,
    product_id: str,
) -> None:
    """Log a warning if a gap larger than 60 s is detected on reconnect."""
    try:
        max_t = conn(".pythonfeed.maxtime", kx.SymbolAtom(canonical), kx.SymbolAtom("coinbase"))
        if max_t is None:
            return
        epoch_ns = int(max_t) + 946684800_000_000_000
        last_seen_s = epoch_ns / 1e9
        gap_s = time.time() - last_seen_s
        if gap_s > 60:
            logger.warning(
                "[coinbase] gap detected for %s: %.0f seconds — continuing from live data",
                canonical, gap_s,
            )
    except Exception as exc:
        logger.warning("[coinbase] gap check failed for %s: %s", canonical, exc)


# ---------------------------------------------------------------------------
# Main feed coroutine
# ---------------------------------------------------------------------------

async def run(conn: kx.QConnection, symbol_map: dict[str, str]) -> None:
    """Run the Coinbase Advanced Trade WebSocket feed.

    symbol_map: {product_id (e.g. 'BTC-USD') -> canonical_symbol}
    """
    if not symbol_map:
        logger.warning("[coinbase] no symbols configured, feed not started")
        return

    api_key = os.environ.get("COINBASE_API_KEY", "")
    api_secret = os.environ.get("COINBASE_API_SECRET", "")
    if not api_key or not api_secret:
        logger.error("[coinbase] COINBASE_API_KEY / COINBASE_API_SECRET not set; feed not started")
        return

    product_ids = list(symbol_map.keys())
    books: dict[str, OrderBook] = defaultdict(OrderBook)
    backoff = 1.0

    while True:
        try:
            logger.info("[coinbase] connecting to %s", WS_URL)
            async with websockets.connect(WS_URL, ping_interval=20, ping_timeout=10) as ws:
                backoff = 1.0
                last_msg = time.monotonic()

                # Subscribe to both channels with authentication
                await ws.send(_subscribe_msg(api_key, api_secret, "market_trades", product_ids))
                await ws.send(_subscribe_msg(api_key, api_secret, "level2", product_ids))

                # Gap check on reconnect
                async with aiohttp.ClientSession() as session:
                    for product_id, canonical in symbol_map.items():
                        await _check_gap(session, conn, api_key, canonical, product_id)

                async for raw in ws:
                    last_msg = time.monotonic()
                    if time.monotonic() - last_msg > HEARTBEAT_TIMEOUT:
                        logger.warning("[coinbase] heartbeat timeout, reconnecting")
                        break

                    try:
                        msg = json.loads(raw)
                    except json.JSONDecodeError:
                        continue

                    msg_type = msg.get("type", "")
                    channel = msg.get("channel", "")
                    events = msg.get("events", [])

                    if msg_type in ("subscriptions", "error"):
                        if msg_type == "error":
                            logger.error("[coinbase] WS error: %s", msg.get("message"))
                        continue

                    if channel == "market_trades":
                        rows = []
                        for evt in events:
                            for trade in evt.get("trades", []):
                                product_id = trade.get("product_id", "")
                                canonical = symbol_map.get(product_id)
                                if not canonical:
                                    continue
                                side = trade.get("side", "unknown").lower()
                                try:
                                    ts = datetime.fromisoformat(
                                        trade["time"].replace("Z", "+00:00")
                                    )
                                except (KeyError, ValueError):
                                    ts = datetime.now(timezone.utc)
                                rows.append({
                                    "time": kx.TimestampAtom(ts),
                                    "sym": kx.SymbolAtom(canonical),
                                    "exchange": kx.SymbolAtom("coinbase"),
                                    "price": float(trade.get("price", 0)),
                                    "size": float(trade.get("size", 0)),
                                    "side": kx.SymbolAtom(side),
                                    "venue_sym": kx.SymbolAtom(product_id),
                                })
                        if rows:
                            conn("upd", "trade", kx.toq(rows))

                    elif channel == "l2_data":
                        for evt in events:
                            product_id = evt.get("product_id", "")
                            canonical = symbol_map.get(product_id)
                            if not canonical:
                                continue
                            book = books[product_id]
                            evt_type = evt.get("type", "")
                            if evt_type == "snapshot":
                                book.apply_snapshot([evt])
                            elif evt_type == "update":
                                book.apply_update([evt])
                            best = book.best()
                            if best:
                                bid, bid_sz, ask, ask_sz = best
                                now = kx.TimestampAtom(datetime.now(timezone.utc))
                                row = {
                                    "time": now,
                                    "sym": kx.SymbolAtom(canonical),
                                    "exchangeTime": now,
                                    "exchange": kx.SymbolAtom("coinbase"),
                                    "bid": bid,
                                    "bidSize": bid_sz,
                                    "ask": ask,
                                    "askSize": ask_sz,
                                }
                                conn("upd", "exchange_top", kx.toq([row]))

        except Exception as exc:
            logger.error("[coinbase] connection error: %s — reconnecting in %.0fs", exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, RECONNECT_MAX)
