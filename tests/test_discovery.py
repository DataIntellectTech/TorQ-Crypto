"""test_discovery.py — Unit tests for code/processes/feedhandler/discovery.py.

Self-contained: uses unittest.mock to avoid real HTTP calls.
Run from repo root:
  python -m pytest tests/test_discovery.py -v
  or
  python tests/test_discovery.py
"""

import asyncio
import sys
import unittest
from pathlib import Path
from unittest.mock import AsyncMock, MagicMock, patch

sys.path.insert(0, str(Path(__file__).parents[1] / "code" / "processes" / "feedhandler"))

import discovery  # noqa: E402


def run(coro):
    return asyncio.get_event_loop().run_until_complete(coro)


# ---------------------------------------------------------------------------
# Helpers to build mock aiohttp responses
# ---------------------------------------------------------------------------

def _mock_response(json_data: dict, status: int = 200) -> MagicMock:
    resp = AsyncMock()
    resp.status = status
    resp.raise_for_status = MagicMock()
    resp.json = AsyncMock(return_value=json_data)
    resp.__aenter__ = AsyncMock(return_value=resp)
    resp.__aexit__ = AsyncMock(return_value=False)
    return resp


def _mock_session(response: MagicMock) -> MagicMock:
    session = MagicMock()
    session.get = MagicMock(return_value=response)
    session.__aenter__ = AsyncMock(return_value=session)
    session.__aexit__ = AsyncMock(return_value=False)
    return session


# ---------------------------------------------------------------------------
# Binance discovery tests
# ---------------------------------------------------------------------------

class TestDiscoverBinance(unittest.TestCase):

    def _binance_payload(self, symbols: list[dict]) -> dict:
        return {"symbols": symbols}

    def test_trading_symbols_included(self):
        payload = self._binance_payload([
            {"symbol": "btcusdt", "baseAsset": "BTC", "quoteAsset": "USDT", "status": "TRADING", "filters": []},
            {"symbol": "ethusdt", "baseAsset": "ETH", "quoteAsset": "USDT", "status": "TRADING", "filters": []},
        ])
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_binance(session))
        self.assertEqual(len(result), 2)

    def test_non_trading_symbols_excluded(self):
        payload = self._binance_payload([
            {"symbol": "btcusdt", "baseAsset": "BTC", "quoteAsset": "USDT", "status": "TRADING", "filters": []},
            {"symbol": "ltcbtc", "baseAsset": "LTC", "quoteAsset": "BTC",  "status": "BREAK",   "filters": []},
        ])
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_binance(session))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["venue_symbol"], "btcusdt")

    def test_btcusdt_maps_to_btc_usdt_not_btc_usd(self):
        payload = self._binance_payload([
            {"symbol": "btcusdt", "baseAsset": "BTC", "quoteAsset": "USDT", "status": "TRADING", "filters": []},
        ])
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_binance(session))
        self.assertEqual(result[0]["canonical_symbol"], "BTC-USDT")
        self.assertEqual(result[0]["quote"], "USDT")
        self.assertTrue(result[0]["mapping_verified"])

    def test_tick_size_extracted(self):
        payload = self._binance_payload([
            {"symbol": "btcusdt", "baseAsset": "BTC", "quoteAsset": "USDT", "status": "TRADING",
             "filters": [{"filterType": "PRICE_FILTER", "tickSize": "0.01000000"}]},
        ])
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_binance(session))
        self.assertAlmostEqual(result[0]["tick_size"], 0.01)

    def test_network_error_returns_empty(self):
        session = MagicMock()
        session.get = MagicMock(side_effect=Exception("network error"))
        result = run(discovery.discover_binance(session))
        self.assertEqual(result, [])

    def test_unknown_quote_sets_mapping_verified_false(self):
        payload = self._binance_payload([
            {"symbol": "btcxyz", "baseAsset": "BTC", "quoteAsset": "XYZ", "status": "TRADING", "filters": []},
        ])
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_binance(session))
        self.assertFalse(result[0]["mapping_verified"])
        # canonical_symbol equals venue_symbol when unverified
        self.assertEqual(result[0]["canonical_symbol"], result[0]["venue_symbol"])


# ---------------------------------------------------------------------------
# Kraken discovery tests
# ---------------------------------------------------------------------------

class TestDiscoverKraken(unittest.TestCase):

    def test_xbt_usd_maps_to_btc_usd(self):
        payload = {
            "error": [],
            "result": {
                "XXBTZUSD": {
                    "base": "XXBT", "quote": "ZUSD", "wsname": "XBT/USD",
                    "lot_decimals": 8, "pair_decimals": 1,
                }
            }
        }
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_kraken(session))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["canonical_symbol"], "BTC-USD")
        self.assertEqual(result[0]["base"], "BTC")
        self.assertEqual(result[0]["quote"], "USD")
        self.assertTrue(result[0]["mapping_verified"])

    def test_api_error_returns_empty(self):
        payload = {"error": ["EGeneral:Unknown method"]}
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_kraken(session))
        self.assertEqual(result, [])

    def test_network_error_returns_empty(self):
        session = MagicMock()
        session.get = MagicMock(side_effect=Exception("timeout"))
        result = run(discovery.discover_kraken(session))
        self.assertEqual(result, [])

    def test_venue_symbol_uses_wsname(self):
        payload = {
            "error": [],
            "result": {
                "XETHZUSD": {
                    "base": "XETH", "quote": "ZUSD", "wsname": "ETH/USD",
                }
            }
        }
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_kraken(session))
        self.assertEqual(result[0]["venue_symbol"], "ETH/USD")


# ---------------------------------------------------------------------------
# Coinbase discovery tests
# ---------------------------------------------------------------------------

class TestDiscoverCoinbase(unittest.TestCase):

    def test_no_credentials_returns_empty(self):
        with patch.dict("os.environ", {"COINBASE_API_KEY": "", "COINBASE_API_SECRET": ""}):
            session = MagicMock()
            result = run(discovery.discover_coinbase(session))
            self.assertEqual(result, [])

    def test_btc_usd_maps_correctly(self):
        payload = {
            "products": [
                {"product_id": "BTC-USD", "base_currency_id": "BTC", "quote_currency_id": "USD"},
            ]
        }
        session = _mock_session(_mock_response(payload))
        with patch.dict("os.environ", {"COINBASE_API_KEY": "key", "COINBASE_API_SECRET": "secret"}):
            result = run(discovery.discover_coinbase(session))
        self.assertEqual(len(result), 1)
        self.assertEqual(result[0]["canonical_symbol"], "BTC-USD")
        self.assertEqual(result[0]["venue"], "coinbase")
        self.assertTrue(result[0]["mapping_verified"])

    def test_network_error_returns_empty(self):
        session = MagicMock()
        session.get = MagicMock(side_effect=Exception("connection refused"))
        with patch.dict("os.environ", {"COINBASE_API_KEY": "key", "COINBASE_API_SECRET": "secret"}):
            result = run(discovery.discover_coinbase(session))
        self.assertEqual(result, [])


# ---------------------------------------------------------------------------
# Instrument distinction tests (BTC-USD vs BTC-USDT must never collide)
# ---------------------------------------------------------------------------

class TestInstrumentDistinction(unittest.TestCase):

    def test_usdt_quote_gives_usdt_canonical(self):
        # Binance BTCUSDT should map to BTC-USDT, NOT BTC-USD
        payload = {
            "symbols": [
                {"symbol": "btcusdt", "baseAsset": "BTC", "quoteAsset": "USDT", "status": "TRADING", "filters": []}
            ]
        }
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_binance(session))
        canonical = result[0]["canonical_symbol"]
        self.assertNotEqual(canonical, "BTC-USD", "BTC-USDT must NOT be mapped to BTC-USD")
        self.assertEqual(canonical, "BTC-USDT")

    def test_usd_quote_gives_usd_canonical(self):
        # Kraken XBT/USD should map to BTC-USD
        payload = {
            "error": [],
            "result": {
                "XXBTZUSD": {"base": "XXBT", "quote": "ZUSD", "wsname": "XBT/USD"}
            }
        }
        session = _mock_session(_mock_response(payload))
        result = run(discovery.discover_kraken(session))
        canonical = result[0]["canonical_symbol"]
        self.assertEqual(canonical, "BTC-USD")
        self.assertNotEqual(canonical, "BTC-USDT", "BTC-USD (FIAT) must NOT be mapped to BTC-USDT")


if __name__ == "__main__":
    unittest.main()
