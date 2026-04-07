"""
tests/test_binance_feed.py — Unit tests for binance_feed.py parse functions.

All tests are pure unit tests — no network calls, no kdb+ process required.
pykx is only used in the IPC layer (_trade_cols, _quote_cols, run_binance_feed);
the parse functions (_parse_trade, _parse_depth) are stdlib-only and tested here
without any IPC dependency.

Run from repo root:
  pytest tests/test_binance_feed.py
"""

import os
import sys
from pathlib import Path
from unittest.mock import patch
import time

import pytest

# ---------------------------------------------------------------------------
# Path and env setup — must happen before importing binance_feed
# ---------------------------------------------------------------------------
REPO_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(REPO_ROOT / "code" / "processes" / "feedhandler"))
os.environ.setdefault("KDBAPPCONFIG", str(REPO_ROOT / "appconfig"))

# Reset symmap cache so tests get a fresh load
import symmap as _symmap_module
_symmap_module.reload()

from binance_feed import _parse_trade, _parse_depth, _ms_to_ns, _build_ws_url, EXCHANGE


# ---------------------------------------------------------------------------
# Helpers: synthetic Binance message builders
# ---------------------------------------------------------------------------

def _trade_msg(
    venue_sym: str = "BTCUSDT",
    price: str = "50000.00",
    qty: str = "0.5",
    trade_time_ms: int = 1_700_000_000_000,
    is_buyer_maker: bool = False,
) -> dict:
    """Build a combined-stream @trade message."""
    return {
        "stream": f"{venue_sym.lower()}@trade",
        "data": {
            "e": "trade",
            "E": trade_time_ms,
            "s": venue_sym,
            "t": 123456,
            "p": price,
            "q": qty,
            "T": trade_time_ms,
            "m": is_buyer_maker,
        },
    }


def _depth5_msg(
    venue_sym: str = "BTCUSDT",
    bids: list | None = None,
    asks: list | None = None,
) -> dict:
    """Build a combined-stream @depth5 message.

    Note: Binance @depth5 uses 'bids'/'asks' (not 'b'/'a') and the symbol
    is encoded in the stream name rather than the data payload.
    The prompt spec describes 'depthUpdate' / b / a fields (diff-depth format);
    this is the correct depth5 format.
    """
    if bids is None:
        bids = [["50000.00", "1.0"], ["49999.00", "2.0"]]
    if asks is None:
        asks = [["50001.00", "0.5"], ["50002.00", "1.5"]]
    return {
        "stream": f"{venue_sym.lower()}@depth5@100ms",
        "data": {
            "lastUpdateId": 999,
            "bids": bids,
            "asks": asks,
        },
    }


# ---------------------------------------------------------------------------
# _parse_trade tests
# ---------------------------------------------------------------------------

class TestParseTrade:
    def test_buy_side(self):
        row = _parse_trade(_trade_msg(is_buyer_maker=False))
        assert row is not None
        assert row["side"] == "buy"

    def test_sell_side(self):
        """m=True means the trade taker is the buyer-maker, i.e. a sell aggressor."""
        row = _parse_trade(_trade_msg(is_buyer_maker=True))
        assert row is not None
        assert row["side"] == "sell"

    def test_canonical_sym_resolved(self):
        row = _parse_trade(_trade_msg(venue_sym="BTCUSDT"))
        assert row is not None
        assert row["sym"] == "BTC-USD"

    def test_price_is_float(self):
        row = _parse_trade(_trade_msg(price="50123.45"))
        assert isinstance(row["price"], float)
        assert row["price"] == pytest.approx(50123.45)

    def test_size_is_float(self):
        row = _parse_trade(_trade_msg(qty="1.23456789"))
        assert isinstance(row["size"], float)
        assert row["size"] == pytest.approx(1.23456789)

    def test_venue_is_binance(self):
        row = _parse_trade(_trade_msg())
        assert row["venue"] == EXCHANGE

    def test_venue_sym_preserved(self):
        row = _parse_trade(_trade_msg(venue_sym="ETHUSDT"))
        assert row is not None
        assert row["venue_sym"] == "ETHUSDT"

    def test_time_is_ns_from_ms(self):
        ms = 1_700_000_000_000
        row = _parse_trade(_trade_msg(trade_time_ms=ms))
        assert row["time"] == ms * 1_000_000

    def test_seq_is_zero(self):
        """Binance trades don't carry a sequence number — always 0."""
        row = _parse_trade(_trade_msg())
        assert row["seq"] == 0

    def test_unknown_symbol_returns_none(self):
        row = _parse_trade(_trade_msg(venue_sym="NOTACOINSDT"))
        assert row is None

    def test_wrong_event_type_returns_none(self):
        msg = _trade_msg()
        msg["data"]["e"] = "kline"
        assert _parse_trade(msg) is None

    def test_malformed_missing_price_returns_none(self):
        msg = _trade_msg()
        del msg["data"]["p"]
        assert _parse_trade(msg) is None

    def test_malformed_non_numeric_price_returns_none(self):
        msg = _trade_msg(price="not-a-number")
        assert _parse_trade(msg) is None

    def test_empty_dict_returns_none(self):
        assert _parse_trade({}) is None

    def test_eth_usdt(self):
        row = _parse_trade(_trade_msg(venue_sym="ETHUSDT"))
        assert row is not None
        assert row["sym"] == "ETH-USD"


# ---------------------------------------------------------------------------
# _parse_depth tests
# ---------------------------------------------------------------------------

class TestParseDepth:
    def test_best_bid_positive(self):
        row = _parse_depth(_depth5_msg())
        assert row is not None
        assert row["bid"] > 0

    def test_best_ask_greater_than_bid(self):
        row = _parse_depth(_depth5_msg())
        assert row is not None
        assert row["ask"] > row["bid"]

    def test_bid_is_max_of_bids(self):
        bids = [["49000.00", "1"], ["50000.00", "2"], ["48000.00", "3"]]
        asks = [["51000.00", "1"]]
        row = _parse_depth(_depth5_msg(bids=bids, asks=asks))
        assert row["bid"] == pytest.approx(50000.0)

    def test_ask_is_min_of_asks(self):
        bids = [["49000.00", "1"]]
        asks = [["51000.00", "1"], ["52000.00", "2"], ["50500.00", "3"]]
        row = _parse_depth(_depth5_msg(bids=bids, asks=asks))
        assert row["ask"] == pytest.approx(50500.0)

    def test_canonical_sym_resolved(self):
        row = _parse_depth(_depth5_msg(venue_sym="BTCUSDT"))
        assert row is not None
        assert row["sym"] == "BTC-USD"

    def test_venue_is_binance(self):
        row = _parse_depth(_depth5_msg())
        assert row["venue"] == EXCHANGE

    def test_bid_qty(self):
        bids = [["50000.00", "1.5"], ["49999.00", "0.5"]]
        row = _parse_depth(_depth5_msg(bids=bids))
        assert row["bsize"] == pytest.approx(1.5)

    def test_ask_qty(self):
        asks = [["50002.00", "3.0"], ["50001.00", "0.25"]]
        row = _parse_depth(_depth5_msg(asks=asks))
        assert row["asize"] == pytest.approx(0.25)

    def test_unknown_symbol_returns_none(self):
        row = _parse_depth(_depth5_msg(venue_sym="NOTACOINSDT"))
        assert row is None

    def test_empty_bids_returns_none(self):
        msg = _depth5_msg(bids=[])
        assert _parse_depth(msg) is None

    def test_empty_asks_returns_none(self):
        msg = _depth5_msg(asks=[])
        assert _parse_depth(msg) is None

    def test_missing_bids_key_returns_none(self):
        msg = _depth5_msg()
        del msg["data"]["bids"]
        assert _parse_depth(msg) is None

    def test_malformed_price_string_returns_none(self):
        bids = [["not-a-price", "1.0"]]
        asks = [["50001.00", "1.0"]]
        msg = _depth5_msg(bids=bids, asks=asks)
        assert _parse_depth(msg) is None

    def test_no_stream_name_returns_none(self):
        msg = _depth5_msg()
        msg["stream"] = ""  # empty stream → can't extract symbol
        assert _parse_depth(msg) is None


# ---------------------------------------------------------------------------
# _build_ws_url
# ---------------------------------------------------------------------------

def test_build_ws_url_contains_all_streams():
    from binance_feed import _build_ws_url
    url = _build_ws_url(["BTCUSDT", "ETHUSDT"])
    assert "btcusdt@trade" in url
    assert "btcusdt@depth5@100ms" in url
    assert "ethusdt@trade" in url
    assert "stream.binance.com" in url


# ---------------------------------------------------------------------------
# _ms_to_ns
# ---------------------------------------------------------------------------

def test_ms_to_ns():
    assert _ms_to_ns(1000) == 1_000_000_000
    assert _ms_to_ns(1_700_000_000_000) == 1_700_000_000_000_000_000
