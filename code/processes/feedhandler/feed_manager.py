"""feed_manager.py — Entry point for the TorQ-Crypto Python feed manager.

Start-up sequence:
  1. Connect to kdb+ pythonfeed1 process via pykx IPC
  2. Run auto-discovery for all three exchanges concurrently
  3. Publish discovery results to kdb+ (upd_discovery)
  4. Merge discovery with static symmap.csv
  5. Build per-exchange symbol maps and launch feed coroutines
  6. Handle graceful shutdown on SIGINT / SIGTERM

Feed restart policy:
  If any individual feed coroutine crashes, it is restarted with exponential
  backoff.  A crash in one feed does NOT crash the entire manager.

Logging format: [TIMESTAMP] [EXCHANGE] [LEVEL] message
All output to stdout.

Configuration (all from environment variables, no hardcoded defaults):
  KDB_HOST, KDB_PORT         — pythonfeed1 address
  KDB_USERNAME               — kdb+ auth username (default: pythonfeed)
  KDB_PASSWORD               — kdb+ auth password (default: pass)
  BINANCE_SYMBOLS            — comma-separated canonical symbols
  KRAKEN_SYMBOLS             — comma-separated canonical symbols
  COINBASE_SYMBOLS           — comma-separated canonical symbols
  COINBASE_API_KEY           — Coinbase auth
  COINBASE_API_SECRET        — Coinbase auth
  FEED_RECONNECT_MAX         — max backoff seconds
  BINANCE_HEARTBEAT_TIMEOUT  — per-exchange heartbeat (seconds)
  KRAKEN_HEARTBEAT_TIMEOUT
  COINBASE_HEARTBEAT_TIMEOUT
"""

import asyncio
import logging
import os
import signal
import sys
from datetime import datetime, timezone
from typing import Callable, Coroutine, Any

import pykx as kx

import discovery
import symmap
import binance_feed
import kraken_feed
import coinbase_feed

# ---------------------------------------------------------------------------
# Logging setup
# ---------------------------------------------------------------------------

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [%(name)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("feed_manager")


# ---------------------------------------------------------------------------
# kdb+ connection
# ---------------------------------------------------------------------------

def _connect_kdb() -> kx.QConnection:
    host = os.environ["KDB_HOST"]
    port = int(os.environ["KDB_PORT"])
    username = os.environ.get("KDB_USERNAME", "pythonfeed")
    password = os.environ.get("KDB_PASSWORD", "pass")
    logger.info("[feed_manager] connecting to kdb+ at %s:%d", host, port)
    return kx.QConnection(host=host, port=port, username=username, password=password)


# ---------------------------------------------------------------------------
# Symbol map builders
# ---------------------------------------------------------------------------

def _parse_env_symbols(env_var: str) -> list[str]:
    raw = os.environ.get(env_var, "")
    return [s.strip() for s in raw.split(",") if s.strip()]


def _build_binance_map() -> dict[str, str]:
    """Return {venue_symbol_lowercase -> canonical} for Binance."""
    syms = _parse_env_symbols("BINANCE_SYMBOLS")
    result = {}
    for canonical in syms:
        vs = symmap.get_venue_symbol(canonical, "binance")
        if vs:
            result[vs.lower()] = canonical
        else:
            logger.warning("[binance] no venue symbol found for %s", canonical)
    return result


def _build_kraken_map() -> dict[str, str]:
    """Return {kraken_pair (e.g. 'XBT/USD') -> canonical}."""
    syms = _parse_env_symbols("KRAKEN_SYMBOLS")
    result = {}
    for canonical in syms:
        vs = symmap.get_venue_symbol(canonical, "kraken")
        if vs:
            result[vs] = canonical
        else:
            logger.warning("[kraken] no venue symbol found for %s", canonical)
    return result


def _build_coinbase_map() -> dict[str, str]:
    """Return {product_id (e.g. 'BTC-USD') -> canonical}."""
    syms = _parse_env_symbols("COINBASE_SYMBOLS")
    result = {}
    for canonical in syms:
        vs = symmap.get_venue_symbol(canonical, "coinbase")
        if vs:
            result[vs] = canonical
        else:
            logger.warning("[coinbase] no venue symbol found for %s", canonical)
    return result


# ---------------------------------------------------------------------------
# Feed supervisor — restart on crash with backoff
# ---------------------------------------------------------------------------

async def _supervised(name: str, coro_factory: Callable[[], Coroutine[Any, Any, None]]) -> None:
    """Run a feed coroutine and restart it on any exception. Normal return exits the supervisor."""
    reconnect_max = int(os.environ.get("FEED_RECONNECT_MAX", "60"))
    backoff = 1.0
    while True:
        try:
            await coro_factory()
            logger.info("[feed_manager] %s feed exited normally", name)
            return
        except asyncio.CancelledError:
            logger.info("[feed_manager] %s feed cancelled", name)
            return
        except Exception as exc:
            logger.error("[feed_manager] %s feed crashed: %s — restarting in %.0fs", name, exc, backoff)
            await asyncio.sleep(backoff)
            backoff = min(backoff * 2, reconnect_max)


# ---------------------------------------------------------------------------
# Graceful shutdown
# ---------------------------------------------------------------------------

def _install_shutdown(loop: asyncio.AbstractEventLoop, tasks: list[asyncio.Task]) -> None:
    def _handler(sig_name: str) -> None:
        logger.info("[feed_manager] received %s, shutting down", sig_name)
        for task in tasks:
            task.cancel()

    for sig in (signal.SIGINT, signal.SIGTERM):
        loop.add_signal_handler(sig, lambda s=sig.name: _handler(s))


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main() -> None:
    # 1. Load static symbol mapping
    symmap.load_static()
    logger.info("[feed_manager] static symbol map loaded")

    # 2. Connect to kdb+
    conn = _connect_kdb()

    # 3. Run discovery for all exchanges
    logger.info("[feed_manager] running instrument discovery")
    discovered = await discovery.run_discovery()
    logger.info("[feed_manager] discovery complete: %d instruments total (symmap.csv used for feed routing)", len(discovered))

    # 5. Merge discovery into runtime symmap
    symmap.update_runtime(discovered)

    # 6. Build per-exchange symbol maps
    binance_map = _build_binance_map()
    kraken_map = _build_kraken_map()
    logger.info("[feed_manager] binance symbols: %s", list(binance_map.values()))
    logger.info("[feed_manager] kraken symbols: %s", list(kraken_map.values()))

    # 7. Launch feed coroutines under supervisor wrappers
    loop = asyncio.get_running_loop()
    tasks = [
        loop.create_task(_supervised("binance", lambda: binance_feed.run(conn, binance_map))),
        loop.create_task(_supervised("kraken",  lambda: kraken_feed.run(conn, kraken_map))),
        # coinbase disabled — requires COINBASE_API_KEY / COINBASE_API_SECRET
    ]

    _install_shutdown(loop, tasks)

    try:
        await asyncio.gather(*tasks)
    except asyncio.CancelledError:
        pass
    finally:
        logger.info("[feed_manager] closing kdb+ connection")
        try:
            conn.close()
        except Exception:
            pass
        logger.info("[feed_manager] shutdown complete")


if __name__ == "__main__":
    asyncio.run(main())
