"""test_symmap.py — Unit tests for code/processes/feedhandler/symmap.py.

Self-contained: writes temporary CSV files and loads symmap.py directly.
Run from repo root:
  python -m pytest tests/test_symmap.py -v
  or
  python tests/test_symmap.py
"""

import csv
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

# Add feedhandler to the import path
sys.path.insert(0, str(Path(__file__).parents[1] / "code" / "processes" / "feedhandler"))

import symmap  # noqa: E402 — imported after sys.path manipulation


def _write_symconfig(path: Path, rows: list[dict]) -> None:
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(f, fieldnames=["canonical_symbol", "enabled", "binance", "kraken", "coinbase"])
        w.writeheader()
        w.writerows(rows)


def _write_symmap(path: Path, rows: list[dict]) -> None:
    with open(path, "w", newline="") as f:
        w = csv.DictWriter(
            f,
            fieldnames=["canonical_symbol", "venue", "venue_symbol", "base", "quote",
                        "instrument_type", "tick_size", "mapping_verified"],
        )
        w.writeheader()
        w.writerows(rows)


class TestSymmapLoadStatic(unittest.TestCase):

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        p = Path(self.tmpdir.name)

        _write_symconfig(p / "symconfig.csv", [
            {"canonical_symbol": "BTC-USD",  "enabled": "true",  "binance": "false", "kraken": "true",  "coinbase": "true"},
            {"canonical_symbol": "BTC-USDT", "enabled": "true",  "binance": "true",  "kraken": "false", "coinbase": "false"},
            {"canonical_symbol": "ETH-USD",  "enabled": "false", "binance": "false", "kraken": "true",  "coinbase": "true"},
        ])
        _write_symmap(p / "symmap.csv", [
            {"canonical_symbol": "BTC-USD",  "venue": "kraken",  "venue_symbol": "XBT/USD", "base": "BTC", "quote": "USD",  "instrument_type": "spot", "tick_size": "",     "mapping_verified": "true"},
            {"canonical_symbol": "BTC-USD",  "venue": "coinbase","venue_symbol": "BTC-USD", "base": "BTC", "quote": "USD",  "instrument_type": "spot", "tick_size": "",     "mapping_verified": "true"},
            {"canonical_symbol": "BTC-USDT", "venue": "binance", "venue_symbol": "btcusdt", "base": "BTC", "quote": "USDT", "instrument_type": "spot", "tick_size": "0.01", "mapping_verified": "true"},
        ])

        # Reset module state
        symmap._static_rows.clear()
        symmap._runtime_rows.clear()
        symmap._verified_static.clear()
        symmap._symconfig.clear()

        with patch.object(Path, "__truediv__", side_effect=lambda self, other: Path(self.tmpdir.name) / other if other in ("symconfig.csv", "symmap.csv") else Path.__truediv__(self, other)):
            pass

        # Patch paths directly
        self._orig_symconfig = symmap._SYMCONFIG_PATH
        self._orig_symmap = symmap._SYMMAP_PATH
        symmap._SYMCONFIG_PATH = p / "symconfig.csv"
        symmap._SYMMAP_PATH = p / "symmap.csv"

        symmap.load_static()

    def tearDown(self):
        symmap._SYMCONFIG_PATH = self._orig_symconfig
        symmap._SYMMAP_PATH = self._orig_symmap
        self.tmpdir.cleanup()

    def test_get_venue_symbol_binance(self):
        result = symmap.get_venue_symbol("BTC-USDT", "binance")
        self.assertEqual(result, "btcusdt")

    def test_get_venue_symbol_kraken(self):
        result = symmap.get_venue_symbol("BTC-USD", "kraken")
        self.assertEqual(result, "XBT/USD")

    def test_get_venue_symbol_unknown_canonical(self):
        result = symmap.get_venue_symbol("UNKNOWN", "binance")
        self.assertIsNone(result)

    def test_get_venue_symbol_wrong_venue(self):
        result = symmap.get_venue_symbol("BTC-USD", "binance")
        self.assertIsNone(result)

    def test_get_canonical_kraken(self):
        result = symmap.get_canonical("XBT/USD", "kraken")
        self.assertEqual(result, "BTC-USD")

    def test_get_canonical_binance(self):
        result = symmap.get_canonical("btcusdt", "binance")
        self.assertEqual(result, "BTC-USDT")

    def test_get_canonical_unknown(self):
        result = symmap.get_canonical("UNKNOWN", "kraken")
        self.assertIsNone(result)

    def test_is_enabled_true(self):
        self.assertTrue(symmap.is_enabled("BTC-USD", "kraken"))
        self.assertTrue(symmap.is_enabled("BTC-USDT", "binance"))

    def test_is_enabled_false_venue(self):
        # BTC-USD is disabled on binance
        self.assertFalse(symmap.is_enabled("BTC-USD", "binance"))

    def test_is_enabled_false_disabled_symbol(self):
        # ETH-USD has enabled=false
        self.assertFalse(symmap.is_enabled("ETH-USD", "kraken"))

    def test_is_enabled_unknown_symbol(self):
        self.assertFalse(symmap.is_enabled("NONEXISTENT", "kraken"))

    def test_tick_size_parsed(self):
        rows = symmap.load_static()
        binance_row = next((r for r in rows if r["venue"] == "binance"), None)
        self.assertIsNotNone(binance_row)
        self.assertAlmostEqual(binance_row["tick_size"], 0.01)

    def test_tick_size_none_when_empty(self):
        rows = symmap.load_static()
        kraken_row = next((r for r in rows if r["venue"] == "kraken"), None)
        self.assertIsNotNone(kraken_row)
        self.assertIsNone(kraken_row["tick_size"])


class TestUpdateRuntime(unittest.TestCase):

    def setUp(self):
        self.tmpdir = tempfile.TemporaryDirectory()
        p = Path(self.tmpdir.name)
        _write_symconfig(p / "symconfig.csv", [
            {"canonical_symbol": "BTC-USD", "enabled": "true", "binance": "false", "kraken": "true", "coinbase": "true"},
        ])
        _write_symmap(p / "symmap.csv", [
            {"canonical_symbol": "BTC-USD", "venue": "kraken", "venue_symbol": "XBT/USD", "base": "BTC", "quote": "USD", "instrument_type": "spot", "tick_size": "", "mapping_verified": "true"},
        ])
        symmap._static_rows.clear()
        symmap._runtime_rows.clear()
        symmap._verified_static.clear()
        symmap._symconfig.clear()
        symmap._SYMCONFIG_PATH = p / "symconfig.csv"
        symmap._SYMMAP_PATH = p / "symmap.csv"
        symmap.load_static()
        self.tmpdir_path = p

    def tearDown(self):
        self.tmpdir.cleanup()

    def test_runtime_row_added(self):
        discovered = [{
            "canonical_symbol": "ETH-USD",
            "venue": "kraken",
            "venue_symbol": "ETH/USD",
            "base": "ETH",
            "quote": "USD",
            "instrument_type": "spot",
            "tick_size": None,
            "mapping_verified": True,
        }]
        symmap.update_runtime(discovered)
        result = symmap.get_venue_symbol("ETH-USD", "kraken")
        self.assertEqual(result, "ETH/USD")

    def test_verified_static_overrides_discovery(self):
        # XBT/USD is already in verified static — discovery should not override it
        discovered = [{
            "canonical_symbol": "OVERRIDE",  # wrong canonical
            "venue": "kraken",
            "venue_symbol": "XBT/USD",
            "base": "BTC",
            "quote": "USD",
            "instrument_type": "spot",
            "tick_size": None,
            "mapping_verified": True,
        }]
        symmap.update_runtime(discovered)
        # The verified static row takes precedence
        result = symmap.get_canonical("XBT/USD", "kraken")
        self.assertEqual(result, "BTC-USD")  # static, not "OVERRIDE"


if __name__ == "__main__":
    unittest.main()
