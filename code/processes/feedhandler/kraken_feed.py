"""kraken_feed.py — Kraken WebSocket feed for trades and top-of-book data.

Connects to wss://ws.kraken.com and subscribes to "trade" and "book" channels
for each enabled symbol.

Book handling:
  Kraken sends an initial snapshot followed by incremental updates.  A local
  order book is maintained in memory; best bid/ask is extracted and published
  after every update.

Reconnect:
  Exponential backoff.  REST backfill via /0/public/Trades uses the nanosecond
  "since" field returned by the API for pagination.
"""

import asyncio
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

logger = logging.getLogger("kraken")

WS_URL = "wss://ws.kraken.com"
REST_BASE = "https://api.kraken.com"
HEARTBEAT_TIMEOUT = int(os.environ.get("KRAKEN_HEARTBEAT_TIMEOUT", "30"))
RECONNECT_MAX = int(os.environ.get("FEED_RECONNECT_MAX", "60"))


# ---------------------------------------------------------------------------
# Local order book state
# ---------------------------------------------------------------------------

class OrderBook:
    """Minimal local order book for a single instrument."""

    def __init__(self) -> None:
        self.bids: dict[float, float] = {}  # price -> size
        self.asks: dict[float, float] = {}

    def apply_snapshot(self, bids: list, asks: list) -> None:
        self.bids = {float(b[0]): float(b[1]) for b in bids}
        self.asks = {float(a[0]): float(a[1]) for a in asks}

    def apply_delta(self, bids: list, asks: list) -> None:
        for price_str, size_str, *_ in bids:
            p, s = float(price_str), float(size_str)
            if s == 0.0:
                self.bids.pop(p, None)
            else:
                self.bids[p] = s
        for price_str, size_str, *_ in asks:
            p, s = float(price_str), float(size_str)
            if s == 0.0:
                self.asks.pop(p, None)
            else:
                self.asks[p] = s

    def best(self) -> Optional[tuple[float, float, float, float]]:
        """Return (best_bid, best_bid_size, best_ask, best_ask_size) or None."""
        if not self.bids or not self.asks:
            return None
        best_bid = max(self.bids)
        best_ask = min(self.asks)
        return best_bid, self.bids[best_bid], best_ask, self.asks[best_ask]


# ---------------------------------------------------------------------------
# Normalisation helpers
# ---------------------------------------------------------------------------

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


def _norm_exchange_top(canonical: str, bid: float, bid_sz: float, ask: float, ask_sz: float) -> dict:
    now = kx.TimestampAtom(datetime.now(timezone.utc))
    return {
        "time": now,
        "sym": kx.SymbolAtom(canonical),
        "exchangeTime": now,
        "exchange": kx.SymbolAtom("kraken"),
        "bid": bid,
        "bidSize": bid_sz,
        "ask": ask,
        "askSize": ask_sz,
    }


# ---------------------------------------------------------------------------
# REST backfill
# ---------------------------------------------------------------------------

async def _backfill(
    session: aiohttp.ClientSession,
    conn: kx.QConnection,
    kraken_pair: str,
    canonical: str,
    since_ns: int,
) -> None:
    url = f"{REST_BASE}/0/public/Trades"
    params = {"pair": kraken_pair.replace("/", ""), "since": since_ns}
    count = 0
    try:
        async with session.get(url, params=params, timeout=aiohttp.ClientTimeout(total=30)) as resp:
            resp.raise_for_status()
            data = await resp.json()
        if data.get("error"):
            logger.warning("[kraken] backfill API error for %s: %s", canonical, data["error"])
            return
        result = data.get("result", {})
        trades = next(iter(v for k, v in result.items() if k != "last"), [])
        rows = []
        for t in trades:
            price, volume, ts, side_char, *_ = t
            side = "buy" if side_char == "b" else "sell"
            rows.append({
                "time": kx.TimestampAtom(datetime.fromtimestamp(float(ts), tz=timezone.utc)),
                "sym": kx.SymbolAtom(canonical),
                "exchange": kx.SymbolAtom("kraken"),
                "price": float(price),
                "size": float(volume),
                "side": kx.SymbolAtom(side),
                "venue_sym": kx.SymbolAtom(kraken_pair),
            })
        if rows:
            conn("upd", kx.SymbolAtom("trade"), _trade_rows_to_cols(rows))
            count = len(rows)
        logger.info("[kraken] backfill %s: %d records published", canonical, count)
    except Exception as exc:
        logger.error("[kraken] backfill failed for %s: %s", canonical, exc)


# ---------------------------------------------------------------------------
# Main feed coroutine
# ---------------------------------------------------------------------------

async def run(conn: kx.QConnection, symbol_map: dict[str, str]) -> None:
    """Run the Kraken WebSocket feed.

    symbol_map: {kraken_pair (e.g. 'XBT/USD') -> canonical_symbol}
    """
    if not symbol_map:
        logger.warning("[kraken] no symbols configured, feed not started")
        return

    pairs = list(symbol_map.keys())
    books: dict[str, OrderBook] = defaultdict(OrderBook)
    backoff = 1.0

    while True:
        last_cmd = None
        try:
            logger.info("[kraken] connecting to %s", WS_URL)
            async with websockets.connect(WS_URL, ping_interval=20, ping_timeout=10) as ws:
                backoff = 1.0
                last_msg = time.monotonic()

                # Subscribe to trade and book channels
                await ws.send(json.dumps({
                    "event": "subscribe",
                    "pair": pairs,
                    "subscription": {"name": "trade"},
                }))
                await ws.send(json.dumps({
                    "event": "subscribe",
                    "pair": pairs,
                    "subscription": {"name": "book", "depth": 10},
                }))

                # Backfill on reconnect
                async with aiohttp.ClientSession() as session:
                    for kraken_pair, canonical in symbol_map.items():
                        try:
                            last_cmd = f".pythonfeed.maxtime[`{canonical};`kraken]"
                            max_t = conn(".pythonfeed.maxtime", kx.SymbolAtom(canonical), kx.SymbolAtom("kraken"))
                            max_t_py = max_t.py()
                            # max_t_py is pandas.Timestamp or pd.NaT; .value gives ns since Unix epoch
                            if hasattr(max_t_py, "value") and max_t_py.value > 0:
                                epoch_ns = max_t_py.value
                                await _backfill(session, conn, kraken_pair, canonical, epoch_ns)
                        except Exception as exc:
                            logger.warning("[kraken] could not determine backfill start for %s: %s", canonical, exc)

                async for raw in ws:
                    last_msg = time.monotonic()
                    if time.monotonic() - last_msg > HEARTBEAT_TIMEOUT:
                        logger.warning("[kraken] heartbeat timeout, reconnecting")
                        break

                    try:
                        msg = json.loads(raw)
                    except json.JSONDecodeError:
                        continue

                    # System events
                    if isinstance(msg, dict):
                        evt = msg.get("event", "")
                        if evt == "heartbeat":
                            last_msg = time.monotonic()
                        continue

                    # Data messages: [channelID, data, channelName, pair]
                    if not isinstance(msg, list) or len(msg) < 4:
                        continue

                    channel_name = msg[-2]
                    pair = msg[-1]
                    canonical = symbol_map.get(pair)
                    if not canonical:
                        continue
                    data = msg[1]

                    if channel_name == "trade":
                        rows = []
                        for t in data:
                            price, volume, ts, side_char, *_ = t
                            side = "buy" if side_char == "b" else "sell"
                            rows.append({
                                "time": kx.TimestampAtom(datetime.fromtimestamp(float(ts), tz=timezone.utc)),
                                "sym": kx.SymbolAtom(canonical),
                                "exchange": kx.SymbolAtom("kraken"),
                                "price": float(price),
                                "size": float(volume),
                                "side": kx.SymbolAtom(side),
                                "venue_sym": kx.SymbolAtom(pair),
                            })
                        if rows:
                            last_cmd = f"upd[`trade; {len(rows)} rows, sym={canonical}, pair={pair}]"
                            conn("upd", kx.SymbolAtom("trade"), _trade_rows_to_cols(rows))

                    elif channel_name.startswith("book"):
                        book = books[pair]
                        if "bs" in data or "as" in data:
                            # Snapshot
                            book.apply_snapshot(data.get("bs", []), data.get("as", []))
                        else:
                            # Delta
                            book.apply_delta(data.get("b", []), data.get("a", []))
                        best = book.best()
                        if best:
                            bid, bid_sz, ask, ask_sz = best
                            row = _norm_exchange_top(canonical, bid, bid_sz, ask, ask_sz)
                            last_cmd = f"upd[`exchange_top; sym={canonical}, bid={bid}, ask={ask}]"
                            conn("upd", kx.SymbolAtom("exchange_top"), _exchange_top_row_to_cols(row))

        except Exception as exc:
            logger.error("[kraken] last command: %s", last_cmd)
            logger.error("[kraken] connection error: %s — reconnecting in %.0fs", exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, RECONNECT_MAX)
