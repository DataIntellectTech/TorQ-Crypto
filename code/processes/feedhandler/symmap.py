"""symmap.py — Symbol mapping utilities for TorQ-Crypto feed manager.

Loads appconfig/symconfig.csv and appconfig/symmap.csv.  After discovery
completes, feed_manager.py updates the in-memory dynamic mapping via
update_runtime().  Runtime rows (from discovery) override static CSV rows
for the same venue + venue_symbol combination, UNLESS the static row has
mapping_verified=True, in which case the static row takes precedence.
"""

import csv
import os
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Paths — resolved relative to this file's repo root
# ---------------------------------------------------------------------------
_REPO_ROOT = Path(__file__).resolve().parents[3]
_SYMCONFIG_PATH = _REPO_ROOT / "appconfig" / "symconfig.csv"
_SYMMAP_PATH = _REPO_ROOT / "appconfig" / "symmap.csv"

# ---------------------------------------------------------------------------
# In-memory state
# ---------------------------------------------------------------------------
# List of dicts from symmap.csv; keyed by (venue, venue_symbol) below
_static_rows: list[dict] = []
# Runtime rows from discovery, keyed by (venue, venue_symbol)
_runtime_rows: dict[tuple[str, str], dict] = {}
# Static rows with mapping_verified=True that must not be overridden
_verified_static: dict[tuple[str, str], dict] = {}
# symconfig rows keyed by canonical_symbol
_symconfig: dict[str, dict] = {}


def load_static() -> list[dict]:
    """Load appconfig/symconfig.csv and appconfig/symmap.csv into memory.

    Returns the list of symmap dicts (raw CSV rows with parsed types).
    """
    global _static_rows, _verified_static, _symconfig

    # --- symconfig ---
    _symconfig = {}
    with open(_SYMCONFIG_PATH, newline="") as f:
        for row in csv.DictReader(f):
            _symconfig[row["canonical_symbol"]] = {
                "canonical_symbol": row["canonical_symbol"],
                "enabled": row.get("enabled", "false").lower() == "true",
                "binance": row.get("binance", "false").lower() == "true",
                "kraken": row.get("kraken", "false").lower() == "true",
                "coinbase": row.get("coinbase", "false").lower() == "true",
            }

    # --- symmap ---
    _static_rows = []
    _verified_static = {}
    with open(_SYMMAP_PATH, newline="") as f:
        for row in csv.DictReader(f):
            tick_raw = row.get("tick_size", "").strip()
            rec = {
                "canonical_symbol": row["canonical_symbol"],
                "venue": row["venue"],
                "venue_symbol": row["venue_symbol"],
                "base": row["base"],
                "quote": row["quote"],
                "instrument_type": row.get("instrument_type", "spot"),
                "tick_size": float(tick_raw) if tick_raw else None,
                "mapping_verified": row.get("mapping_verified", "false").lower() == "true",
            }
            _static_rows.append(rec)
            if rec["mapping_verified"]:
                _verified_static[(rec["venue"], rec["venue_symbol"])] = rec

    return _static_rows


def update_runtime(discovered_rows: list[dict]) -> None:
    """Merge auto-discovered symbol rows into the runtime mapping.

    Static rows with mapping_verified=True take precedence over discovered rows
    for the same venue + venue_symbol combination.  All other discovered rows
    are accepted into the runtime map.
    """
    for row in discovered_rows:
        key = (row["venue"], row["venue_symbol"])
        if key in _verified_static:
            # Static override wins — do not replace with discovery result
            continue
        _runtime_rows[key] = row


def _effective_rows() -> list[dict]:
    """Return the merged effective symbol map.

    Priority: verified static > runtime (discovery) > unverified static.
    """
    seen: set[tuple[str, str]] = set()
    result: list[dict] = []

    # 1. Verified static rows always win
    for key, row in _verified_static.items():
        seen.add(key)
        result.append(row)

    # 2. Runtime (discovery) rows for unseen keys
    for key, row in _runtime_rows.items():
        if key not in seen:
            seen.add(key)
            result.append(row)

    # 3. Unverified static rows for anything still unseen
    for row in _static_rows:
        key = (row["venue"], row["venue_symbol"])
        if key not in seen:
            seen.add(key)
            result.append(row)

    return result


def get_venue_symbol(canonical: str, venue: str) -> Optional[str]:
    """Return the venue-specific symbol string for a canonical symbol."""
    for row in _effective_rows():
        if row["canonical_symbol"] == canonical and row["venue"] == venue:
            return row["venue_symbol"]
    return None


def get_canonical(venue_symbol: str, venue: str) -> Optional[str]:
    """Return the canonical symbol for a venue-specific symbol string."""
    for row in _effective_rows():
        if row["venue_symbol"] == venue_symbol and row["venue"] == venue:
            return row["canonical_symbol"]
    return None


def is_enabled(canonical: str, venue: str) -> bool:
    """Return True if the canonical symbol is enabled for the given venue."""
    cfg = _symconfig.get(canonical)
    if cfg is None:
        return False
    if not cfg.get("enabled", False):
        return False
    return bool(cfg.get(venue, False))
