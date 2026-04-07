"""
tests/test_symmap.py — Unit tests for code/processes/feedhandler/symmap.py

Run from repo root:
  pytest tests/test_symmap.py
"""

import os
import sys
from pathlib import Path

import pytest

# Ensure the feedhandler module is importable and KDBAPPCONFIG points to the
# real appconfig directory regardless of where pytest is invoked from.
REPO_ROOT = Path(__file__).parent.parent
sys.path.insert(0, str(REPO_ROOT / "code" / "processes" / "feedhandler"))
os.environ.setdefault("KDBAPPCONFIG", str(REPO_ROOT / "appconfig"))

import symmap


@pytest.fixture(autouse=True)
def reset_cache():
    """Force symmap to reload from disk before each test."""
    symmap.reload()
    yield
    symmap.reload()


# ---------------------------------------------------------------------------
# get_canonical
# ---------------------------------------------------------------------------

def test_get_canonical_binance_btc():
    assert symmap.get_canonical("BTCUSDT", "binance") == "BTC-USD"


def test_get_canonical_kraken_btc():
    assert symmap.get_canonical("XBT/USD", "kraken") == "BTC-USD"


def test_get_canonical_okx_btc():
    assert symmap.get_canonical("BTC-USDT", "okx") == "BTC-USD"


def test_get_canonical_unknown_returns_none():
    assert symmap.get_canonical("UNKNOWN", "binance") is None


def test_get_canonical_exchange_case_insensitive():
    assert symmap.get_canonical("BTCUSDT", "BINANCE") == "BTC-USD"
    assert symmap.get_canonical("BTCUSDT", "Binance") == "BTC-USD"


def test_get_canonical_venue_symbol_case_insensitive():
    # Binance symbols are uppercase but lookup should be case-insensitive
    assert symmap.get_canonical("btcusdt", "binance") == "BTC-USD"


def test_get_canonical_eth():
    assert symmap.get_canonical("ETHUSDT", "binance") == "ETH-USD"
    assert symmap.get_canonical("ETH/USD", "kraken") == "ETH-USD"
    assert symmap.get_canonical("ETH-USDT", "okx") == "ETH-USD"


def test_get_canonical_unknown_exchange_raises():
    with pytest.raises(ValueError):
        symmap.get_canonical("BTCUSDT", "unknown_exchange")


# ---------------------------------------------------------------------------
# get_venue_symbol
# ---------------------------------------------------------------------------

def test_get_venue_symbol_kraken_btc():
    assert symmap.get_venue_symbol("BTC-USD", "kraken") == "XBT/USD"


def test_get_venue_symbol_binance_eth():
    assert symmap.get_venue_symbol("ETH-USD", "binance") == "ETHUSDT"


def test_get_venue_symbol_unknown_canonical_returns_none():
    assert symmap.get_venue_symbol("FAKE-USD", "binance") is None


def test_get_venue_symbol_empty_venue_returns_none():
    # BNB-USD has no Kraken or OKX symbol
    assert symmap.get_venue_symbol("BNB-USD", "kraken") is None
    assert symmap.get_venue_symbol("BNB-USD", "okx") is None


# ---------------------------------------------------------------------------
# get_enabled_for_venue
# ---------------------------------------------------------------------------

def test_get_enabled_for_venue_binance_at_least_four():
    result = symmap.get_enabled_for_venue("binance")
    assert len(result) >= 4


def test_get_enabled_for_venue_kraken_at_least_four():
    # BNB-USD has no Kraken symbol so should be excluded
    result = symmap.get_enabled_for_venue("kraken")
    assert len(result) >= 4


def test_get_enabled_for_venue_excludes_empty():
    # BNB-USD has no Kraken symbol — must not appear
    kraken = symmap.get_enabled_for_venue("kraken")
    canonicals = [r["canonical_symbol"] for r in kraken]
    assert "BNB-USD" not in canonicals


def test_get_enabled_for_venue_no_duplicates_binance():
    result = symmap.get_enabled_for_venue("binance")
    canonicals = [r["canonical_symbol"] for r in result]
    assert len(canonicals) == len(set(canonicals)), "Duplicate canonical_sym for binance"


def test_get_enabled_for_venue_no_duplicates_kraken():
    result = symmap.get_enabled_for_venue("kraken")
    canonicals = [r["canonical_symbol"] for r in result]
    assert len(canonicals) == len(set(canonicals)), "Duplicate canonical_sym for kraken"


def test_get_enabled_for_venue_no_duplicates_okx():
    result = symmap.get_enabled_for_venue("okx")
    canonicals = [r["canonical_symbol"] for r in result]
    assert len(canonicals) == len(set(canonicals)), "Duplicate canonical_sym for okx"


def test_get_enabled_for_venue_result_shape():
    result = symmap.get_enabled_for_venue("binance")
    for entry in result:
        assert "canonical_symbol" in entry
        assert "venue_symbol" in entry
        assert entry["venue_symbol"]  # must be non-empty