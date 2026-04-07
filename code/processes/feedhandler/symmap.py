"""
symmap.py — Symbol mapping for TorQ-Crypto feed handlers.

Loads appconfig/symmap.csv and provides lookup functions between
venue-specific symbols and canonical instrument names.

Configuration:
  KDBAPPCONFIG — path to appconfig directory (default: appconfig/)

No external dependencies — stdlib only.
"""

from __future__ import annotations

import csv
import os
from pathlib import Path

# Supported exchanges and their corresponding CSV column names.
_EXCHANGE_COLUMNS: dict[str, str] = {
    "binance": "binance_sym",
    "kraken": "kraken_sym",
    "okx": "okx_sym",
}

# Module-level cache: populated on first call to _load().
_rows: list[dict[str, str]] = []
_loaded: bool = False


def _symmap_path() -> Path:
    base = os.environ.get("KDBAPPCONFIG", "appconfig")
    return Path(base) / "symmap.csv"


def _load() -> None:
    global _rows, _loaded
    if _loaded:
        return
    path = _symmap_path()
    with open(path, newline="") as fh:
        reader = csv.DictReader(fh)
        _rows = [row for row in reader]
    _loaded = True


def _col(exchange: str) -> str:
    """Return the CSV column name for the given exchange. Case-insensitive."""
    key = exchange.lower()
    col = _EXCHANGE_COLUMNS.get(key)
    if col is None:
        raise ValueError(f"Unknown exchange '{exchange}'. Supported: {list(_EXCHANGE_COLUMNS)}")
    return col


def get_canonical(venue_symbol: str, exchange: str) -> str | None:
    """Return the canonical symbol for a venue-specific symbol, or None if not found.

    Matching is case-insensitive on venue_symbol.
    """
    _load()
    col = _col(exchange)
    target = venue_symbol.lower()
    for row in _rows:
        if row.get(col, "").lower() == target:
            return row["canonical_sym"] or None
    return None


def get_venue_symbol(canonical: str, exchange: str) -> str | None:
    """Return the venue-specific symbol for a canonical symbol, or None if not found."""
    _load()
    col = _col(exchange)
    for row in _rows:
        if row["canonical_sym"] == canonical:
            venue_sym = row.get(col, "")
            return venue_sym if venue_sym else None
    return None


def get_enabled_for_venue(exchange: str) -> list[dict[str, str]]:
    """Return all instruments available on the given exchange.

    Returns a list of dicts with keys:
      canonical_symbol — e.g. "BTC-USD"
      venue_symbol     — e.g. "BTCUSDT"

    Instruments with an empty venue symbol for this exchange are excluded.
    """
    _load()
    col = _col(exchange)
    result = []
    for row in _rows:
        venue_sym = row.get(col, "")
        if venue_sym:
            result.append({
                "canonical_symbol": row["canonical_sym"],
                "venue_symbol": venue_sym,
            })
    return result


def reload() -> None:
    """Force a reload of symmap.csv on the next call (useful in tests)."""
    global _loaded
    _loaded = False