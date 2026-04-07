"""
tests/test_kraken_feed.py — Unit tests for kraken_feed.py parse functions.

All tests are pure unit tests — no network calls, no kdb+ process required.
pykx is only used in the IPC layer (_trade_cols, run_kraken_feed);
the parse functions (_parse_trade, _iso8601_to_ns) are stdlib-only and
tested here without any IPC dependency.

Run from repo root:
  pytest tests/test_kraken_feed.py
"""

import os
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Path and env setup — must happen before importing kraken_feed
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(REPO_ROOT / "code" / "processes" / "feedhandler"))
os.environ.setdefault("KDBAPPCONFIG", str(REPO_ROOT / "appconfig"))

# Reset symmap cache so tests get a fresh load
import symmap as _symmap_module
_symmap_module.reload()

from kraken_feed import _parse_trade, _iso8601_to_ns, EXCHANGE


# ---------------------------------------------------------------------------
# Helpers: synthetic Kraken trade entry builders
# ---------------------------------------------------------------------------

def _trade_entry(
    symbol: str = "XBT/USD",
    price: float = 50000.0,
    qty: float = 0.5,
    side: str = "buy",
    timestamp: str = "2023-11-14T20:00:00.000000Z",
) -> dict:
    """Build a single entry from a Kraken trade channel data array."""
    return {
        "symbol": symbol,
        "price": price,
        "qty": qty,
        "side": side,
        "timestamp": timestamp,
        "ord_type": "market",
        "trade_id": 1234567,
    }


def _trade_msg(entries: list[dict] | None = None) -> dict:
    """Build a full Kraken v2 trade channel message."""
    if entries is None:
        entries = [_trade_entry()]
    return {
        "channel": "trade",
        "type": "update",
        "data": entries,
    }


# ---------------------------------------------------------------------------
# _parse_trade: buy side
# ---------------------------------------------------------------------------

class TestParseTradeBuy:
    def test_side_is_buy(self):
        row = _parse_trade(_trade_entry(side="buy"))
        assert row is not None
        assert row["side"] == "buy"

    def test_canonical_sym_resolved(self):
        row = _parse_trade(_trade_entry(symbol="XBT/USD"))
        assert row is not None
        assert row["sym"] == "BTC-USD"

    def test_price_is_float(self):
        row = _parse_trade(_trade_entry(price=50123.45))
        assert isinstance(row["price"], float)
        assert row["price"] == pytest.approx(50123.45)

    def test_size_is_float(self):
        row = _parse_trade(_trade_entry(qty=1.23456789))
        assert isinstance(row["size"], float)
        assert row["size"] == pytest.approx(1.23456789)

    def test_venue_is_kraken(self):
        row = _parse_trade(_trade_entry())
        assert row["venue"] == EXCHANGE

    def test_venue_sym_preserved(self):
        row = _parse_trade(_trade_entry(symbol="ETH/USD"))
        assert row is not None
        assert row["venue_sym"] == "ETH/USD"

    def test_seq_is_zero(self):
        row = _parse_trade(_trade_entry())
        assert row["seq"] == 0


# ---------------------------------------------------------------------------
# _parse_trade: sell side
# ---------------------------------------------------------------------------

class TestParseTradeSell:
    def test_side_is_sell(self):
        row = _parse_trade(_trade_entry(side="sell"))
        assert row is not None
        assert row["side"] == "sell"

    def test_eth_sell(self):
        row = _parse_trade(_trade_entry(symbol="ETH/USD", side="sell"))
        assert row is not None
        assert row["side"] == "sell"
        assert row["sym"] == "ETH-USD"


# ---------------------------------------------------------------------------
# Timestamp parsing
# ---------------------------------------------------------------------------

class TestTimestampParsing:
    def test_utc_z_suffix(self):
        # 2023-11-14T20:00:00Z == 1699992000 seconds since epoch
        ns = _iso8601_to_ns("2023-11-14T20:00:00.000000Z")
        assert ns == 1_699_992_000_000_000_000

    def test_sub_second_precision(self):
        # 1699992000.574862 s → 1699992000574862000 ns
        ns = _iso8601_to_ns("2023-11-14T20:00:00.574862Z")
        assert ns == pytest.approx(1_699_992_000_574_862_000, abs=1000)

    def test_trade_row_timestamp(self):
        ts = "2023-11-14T20:00:00.000000Z"
        row = _parse_trade(_trade_entry(timestamp=ts))
        assert row is not None
        assert row["time"] == _iso8601_to_ns(ts)

    def test_returns_int(self):
        ns = _iso8601_to_ns("2023-11-14T20:00:00.000000Z")
        assert isinstance(ns, int)

    def test_unix_epoch(self):
        ns = _iso8601_to_ns("1970-01-01T00:00:00.000000Z")
        assert ns == 0


# ---------------------------------------------------------------------------
# Unknown symbol skipped
# ---------------------------------------------------------------------------

class TestUnknownSymbolSkipped:
    def test_unknown_symbol_returns_none(self):
        row = _parse_trade(_trade_entry(symbol="NOTACOIN/USD"))
        assert row is None

    def test_binance_symbol_not_recognised(self):
        # Binance-style symbol should not match Kraken mapping
        row = _parse_trade(_trade_entry(symbol="BTCUSDT"))
        assert row is None

    def test_bnb_not_on_kraken(self):
        # BNB-USD has no kraken_sym in symmap.csv
        row = _parse_trade(_trade_entry(symbol="BNB/USD"))
        assert row is None


# ---------------------------------------------------------------------------
# Malformed message handling
# ---------------------------------------------------------------------------

class TestMalformedSkipped:
    def test_missing_price_returns_none(self):
        entry = _trade_entry()
        del entry["price"]
        assert _parse_trade(entry) is None

    def test_missing_qty_returns_none(self):
        entry = _trade_entry()
        del entry["qty"]
        assert _parse_trade(entry) is None

    def test_missing_symbol_returns_none(self):
        entry = _trade_entry()
        del entry["symbol"]
        assert _parse_trade(entry) is None

    def test_missing_timestamp_returns_none(self):
        entry = _trade_entry()
        del entry["timestamp"]
        assert _parse_trade(entry) is None

    def test_missing_side_returns_none(self):
        entry = _trade_entry()
        del entry["side"]
        assert _parse_trade(entry) is None

    def test_non_numeric_price_returns_none(self):
        entry = _trade_entry()
        entry["price"] = "not-a-number"
        assert _parse_trade(entry) is None

    def test_empty_dict_returns_none(self):
        assert _parse_trade({}) is None

    def test_invalid_timestamp_returns_none(self):
        entry = _trade_entry(timestamp="not-a-timestamp")
        assert _parse_trade(entry) is None
