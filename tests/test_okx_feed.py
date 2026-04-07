"""
tests/test_okx_feed.py — Unit tests for okx_feed.py parse functions.

All tests are pure unit tests — no network calls, no kdb+ process required.
pykx is only used in the IPC layer (_trade_cols, run_okx_feed);
the parse function (_parse_trade) is stdlib-only and tested here
without any IPC dependency.

Run from repo root:
  pytest tests/test_okx_feed.py
"""

import os
import sys
from pathlib import Path

import pytest

# ---------------------------------------------------------------------------
# Path and env setup — must happen before importing okx_feed
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(REPO_ROOT / "code" / "processes" / "feedhandler"))
os.environ.setdefault("KDBAPPCONFIG", str(REPO_ROOT / "appconfig"))

# Reset symmap cache so tests get a fresh load
import symmap as _symmap_module
_symmap_module.reload()

from okx_feed import _parse_trade, EXCHANGE


# ---------------------------------------------------------------------------
# Helpers: synthetic OKX trade entry builders
# ---------------------------------------------------------------------------

def _trade_entry(
    inst_id: str = "BTC-USDT",
    px: str = "50000.00",
    sz: str = "0.5",
    side: str = "buy",
    ts: str = "1700000000000",
    trade_id: str = "987654321",
) -> dict:
    """Build a single entry from an OKX trades channel data array."""
    return {
        "instId": inst_id,
        "tradeId": trade_id,
        "px": px,
        "sz": sz,
        "side": side,
        "ts": ts,
    }


# ---------------------------------------------------------------------------
# test_parse_trade_buy
# ---------------------------------------------------------------------------

class TestParseTradeBuy:
    def test_side_is_buy(self):
        row = _parse_trade(_trade_entry(side="buy"))
        assert row is not None
        assert row["side"] == "buy"

    def test_canonical_sym_resolved(self):
        row = _parse_trade(_trade_entry(inst_id="BTC-USDT"))
        assert row is not None
        assert row["sym"] == "BTC-USD"

    def test_price_is_float(self):
        row = _parse_trade(_trade_entry(px="50123.45"))
        assert isinstance(row["price"], float)
        assert row["price"] == pytest.approx(50123.45)

    def test_size_is_float(self):
        row = _parse_trade(_trade_entry(sz="1.23456789"))
        assert isinstance(row["size"], float)
        assert row["size"] == pytest.approx(1.23456789)

    def test_venue_is_okx(self):
        row = _parse_trade(_trade_entry())
        assert row["venue"] == EXCHANGE

    def test_venue_sym_preserved(self):
        row = _parse_trade(_trade_entry(inst_id="ETH-USDT"))
        assert row is not None
        assert row["venue_sym"] == "ETH-USDT"

    def test_time_is_ns_from_ms(self):
        ts_ms = "1700000000000"
        row = _parse_trade(_trade_entry(ts=ts_ms))
        assert row["time"] == int(ts_ms) * 1_000_000

    def test_eth_buy(self):
        row = _parse_trade(_trade_entry(inst_id="ETH-USDT", side="buy"))
        assert row is not None
        assert row["sym"] == "ETH-USD"
        assert row["side"] == "buy"


# ---------------------------------------------------------------------------
# test_parse_trade_sell
# ---------------------------------------------------------------------------

class TestParseTradeSell:
    def test_side_is_sell(self):
        row = _parse_trade(_trade_entry(side="sell"))
        assert row is not None
        assert row["side"] == "sell"

    def test_eth_sell(self):
        row = _parse_trade(_trade_entry(inst_id="ETH-USDT", side="sell"))
        assert row is not None
        assert row["side"] == "sell"
        assert row["sym"] == "ETH-USD"


# ---------------------------------------------------------------------------
# test_seq_parsed_as_long
# ---------------------------------------------------------------------------

class TestSeqParsedAsLong:
    def test_trade_id_converted_to_int(self):
        row = _parse_trade(_trade_entry(trade_id="987654321"))
        assert row is not None
        assert row["seq"] == 987654321

    def test_seq_is_int_type(self):
        row = _parse_trade(_trade_entry(trade_id="123"))
        assert isinstance(row["seq"], int)

    def test_large_trade_id(self):
        row = _parse_trade(_trade_entry(trade_id="9999999999999"))
        assert row is not None
        assert row["seq"] == 9999999999999

    def test_unparseable_trade_id_falls_back_to_zero(self):
        entry = _trade_entry()
        entry["tradeId"] = "not-an-int"
        row = _parse_trade(entry)
        assert row is not None
        assert row["seq"] == 0

    def test_missing_trade_id_falls_back_to_zero(self):
        entry = _trade_entry()
        del entry["tradeId"]
        row = _parse_trade(entry)
        assert row is not None
        assert row["seq"] == 0


# ---------------------------------------------------------------------------
# test_unknown_instid_skipped
# ---------------------------------------------------------------------------

class TestUnknownInstIdSkipped:
    def test_unknown_inst_id_returns_none(self):
        row = _parse_trade(_trade_entry(inst_id="NOTACOIN-USDT"))
        assert row is None

    def test_kraken_style_sym_not_recognised(self):
        row = _parse_trade(_trade_entry(inst_id="XBT/USD"))
        assert row is None

    def test_binance_style_sym_not_recognised(self):
        row = _parse_trade(_trade_entry(inst_id="BTCUSDT"))
        assert row is None


# ---------------------------------------------------------------------------
# test_malformed_skipped
# ---------------------------------------------------------------------------

class TestMalformedSkipped:
    def test_missing_px_returns_none(self):
        entry = _trade_entry()
        del entry["px"]
        assert _parse_trade(entry) is None

    def test_missing_sz_returns_none(self):
        entry = _trade_entry()
        del entry["sz"]
        assert _parse_trade(entry) is None

    def test_missing_inst_id_returns_none(self):
        entry = _trade_entry()
        del entry["instId"]
        assert _parse_trade(entry) is None

    def test_missing_ts_returns_none(self):
        entry = _trade_entry()
        del entry["ts"]
        assert _parse_trade(entry) is None

    def test_missing_side_returns_none(self):
        entry = _trade_entry()
        del entry["side"]
        assert _parse_trade(entry) is None

    def test_non_numeric_px_returns_none(self):
        assert _parse_trade(_trade_entry(px="not-a-number")) is None

    def test_non_numeric_sz_returns_none(self):
        assert _parse_trade(_trade_entry(sz="not-a-number")) is None

    def test_non_numeric_ts_returns_none(self):
        assert _parse_trade(_trade_entry(ts="not-a-timestamp")) is None

    def test_empty_dict_returns_none(self):
        assert _parse_trade({}) is None
