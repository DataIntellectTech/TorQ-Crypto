"""discovery.py — Per-exchange instrument auto-discovery.

On startup, each exchange REST API is queried to discover available trading
instruments.  Results are normalised into a common dict schema and published
to kdb+ via IPC (upd_discovery).

INSTRUMENT DISTINCTION
----------------------
BTC-USD (FIAT USD) and BTC-USDT (Tether stablecoin) are DIFFERENT instruments.
  - quote = genuine FIAT USD  -> canonical quote suffix "USD"  (e.g. BTC-USD)
  - quote = USDT (Tether)     -> canonical quote suffix "USDT" (e.g. BTC-USDT)
  - quote unknown/ambiguous   -> mapping_verified=False; canonical_symbol equals
                                  the original venue symbol unchanged.

MANUAL OVERRIDE
---------------
Rows in appconfig/symmap.csv with mapping_verified=True take precedence over
auto-discovered rows for the same venue + venue_symbol combination.  This
module produces discovery results; symmap.py enforces the override logic.
"""

import asyncio
import logging
import os
from typing import Any, Optional

import aiohttp

logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Kraken asset normalisation helpers
# ---------------------------------------------------------------------------
# Kraken uses XBT for Bitcoin and Z-prefixed ISO codes for fiat (e.g. ZUSD)
_KRAKEN_BASE_MAP = {"XBT": "BTC", "XXBT": "BTC"}
_KRAKEN_QUOTE_MAP = {
    "ZUSD": "USD", "USD": "USD",
    "ZEUR": "EUR", "EUR": "EUR",
    "ZGBP": "GBP", "GBP": "GBP",
}
_FIAT_QUOTES = {"USD", "EUR", "GBP", "JPY", "AUD", "CAD", "CHF"}


def _canonical_quote(quote_upper: str) -> tuple[str, bool]:
    """Return (normalised_quote, mapping_verified).

    mapping_verified=True only when the quote is unambiguously FIAT or USDT.
    """
    if quote_upper in _FIAT_QUOTES:
        return quote_upper, True
    if quote_upper == "USDT":
        return "USDT", True
    return quote_upper, False


def _make_canonical(base: str, quote: str) -> str:
    return f"{base}-{quote}"


# ---------------------------------------------------------------------------
# Binance discovery
# ---------------------------------------------------------------------------
async def discover_binance(session: aiohttp.ClientSession) -> list[dict]:
    """Query Binance exchangeInfo and return normalised instrument dicts."""
    url = "https://api.binance.com/api/v3/exchangeInfo"
    results: list[dict] = []
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as resp:
            resp.raise_for_status()
            data = await resp.json()
    except Exception as exc:
        logger.error("[binance] discovery failed: %s", exc)
        return results

    for sym in data.get("symbols", []):
        if sym.get("status") != "TRADING":
            continue
        base = sym.get("baseAsset", "").upper()
        raw_quote = sym.get("quoteAsset", "").upper()
        venue_symbol = sym.get("symbol", "").lower()

        norm_quote, verified = _canonical_quote(raw_quote)
        canonical = _make_canonical(base, norm_quote) if verified else venue_symbol

        tick_size: Optional[float] = None
        for f in sym.get("filters", []):
            if f.get("filterType") == "PRICE_FILTER":
                try:
                    tick_size = float(f.get("tickSize", 0)) or None
                except (ValueError, TypeError):
                    pass

        results.append({
            "canonical_symbol": canonical,
            "venue": "binance",
            "venue_symbol": venue_symbol,
            "base": base,
            "quote": norm_quote,
            "instrument_type": "spot",
            "tick_size": tick_size,
            "mapping_verified": verified,
        })

    logger.info("[binance] discovered %d instruments", len(results))
    return results


# ---------------------------------------------------------------------------
# Kraken discovery
# ---------------------------------------------------------------------------
async def discover_kraken(session: aiohttp.ClientSession) -> list[dict]:
    """Query Kraken AssetPairs and return normalised instrument dicts."""
    url = "https://api.kraken.com/0/public/AssetPairs"
    results: list[dict] = []
    try:
        async with session.get(url, timeout=aiohttp.ClientTimeout(total=30)) as resp:
            resp.raise_for_status()
            data = await resp.json()
    except Exception as exc:
        logger.error("[kraken] discovery failed: %s", exc)
        return results

    if data.get("error"):
        logger.error("[kraken] discovery API error: %s", data["error"])
        return results

    for pair_name, info in data.get("result", {}).items():
        raw_base = info.get("base", "").upper()
        raw_quote = info.get("quote", "").upper()
        venue_symbol = f"{info.get('wsname', pair_name)}"  # prefer wsname (XBT/USD)

        base = _KRAKEN_BASE_MAP.get(raw_base, raw_base.lstrip("X").lstrip("Z") or raw_base)
        norm_quote_str = _KRAKEN_QUOTE_MAP.get(raw_quote, raw_quote.lstrip("Z"))
        norm_quote, verified = _canonical_quote(norm_quote_str.upper())
        canonical = _make_canonical(base, norm_quote) if verified else venue_symbol

        results.append({
            "canonical_symbol": canonical,
            "venue": "kraken",
            "venue_symbol": venue_symbol,
            "base": base,
            "quote": norm_quote,
            "instrument_type": "spot",
            "tick_size": None,
            "mapping_verified": verified,
        })

    logger.info("[kraken] discovered %d instruments", len(results))
    return results


# ---------------------------------------------------------------------------
# Coinbase discovery
# ---------------------------------------------------------------------------
async def discover_coinbase(session: aiohttp.ClientSession) -> list[dict]:
    """Query Coinbase Advanced Trade products and return normalised dicts.

    Requires COINBASE_API_KEY and COINBASE_API_SECRET environment variables.
    Authentication uses JWT or HMAC depending on key type — here we use the
    simple Bearer approach supported by Coinbase Advanced Trade v3.
    """
    api_key = os.environ.get("COINBASE_API_KEY", "")
    api_secret = os.environ.get("COINBASE_API_SECRET", "")
    if not api_key or not api_secret:
        logger.warning("[coinbase] COINBASE_API_KEY / COINBASE_API_SECRET not set; skipping discovery")
        return []

    url = "https://api.coinbase.com/api/v3/brokerage/market/products"
    headers = {"Authorization": f"Bearer {api_key}"}
    results: list[dict] = []
    try:
        async with session.get(url, headers=headers, timeout=aiohttp.ClientTimeout(total=30)) as resp:
            resp.raise_for_status()
            data = await resp.json()
    except Exception as exc:
        logger.error("[coinbase] discovery failed: %s", exc)
        return results

    for product in data.get("products", []):
        product_id = product.get("product_id", "")
        base = product.get("base_currency_id", "").upper()
        raw_quote = product.get("quote_currency_id", "").upper()
        norm_quote, verified = _canonical_quote(raw_quote)
        canonical = _make_canonical(base, norm_quote) if verified else product_id

        results.append({
            "canonical_symbol": canonical,
            "venue": "coinbase",
            "venue_symbol": product_id,
            "base": base,
            "quote": norm_quote,
            "instrument_type": "spot",
            "tick_size": None,
            "mapping_verified": verified,
        })

    logger.info("[coinbase] discovered %d instruments", len(results))
    return results


# ---------------------------------------------------------------------------
# Top-level entry point
# ---------------------------------------------------------------------------
async def run_discovery() -> list[dict]:
    """Run discovery for all three exchanges concurrently.

    Returns the combined list of normalised instrument dicts.
    """
    async with aiohttp.ClientSession() as session:
        binance_rows, kraken_rows, coinbase_rows = await asyncio.gather(
            discover_binance(session),
            discover_kraken(session),
            discover_coinbase(session),
        )
    return binance_rows + kraken_rows + coinbase_rows
