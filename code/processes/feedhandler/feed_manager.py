"""
feed_manager.py — Entry point for TorQ-Crypto Python feed handlers.

Establishes a single pykx IPC connection to the pythonfeed TorQ process and
runs all enabled exchange feeds as concurrent asyncio tasks.

Configuration (environment variables):
  KDB_PYTHONFEED_HOST   Host for pythonfeed process (default: localhost)
  KDB_PYTHONFEED_PORT   Port for pythonfeed process (default: KDBBASEPORT+20)
  FEED_LOG_LEVEL        Logging level (default: INFO)
  FEED_RECONNECT_MAX    Max reconnect backoff in seconds (default: 60)

Smoke test:
  source setenv.sh
  python code/processes/feedhandler/feed_manager.py
  # Expect logs: "Connected to pythonfeed" then "[binance] Connected",
  #              "[kraken] Connected", "[okx] Connected"
  # Verify in kdb+: q)count trade  (should grow over time in RDB)
"""

from __future__ import annotations

import asyncio
import logging
import os
import sys
import time

import pykx as kx

from binance_feed import run_binance_feed
from kraken_feed import run_kraken_feed
from okx_feed import run_okx_feed

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

LOG_LEVEL = os.environ.get("FEED_LOG_LEVEL", "INFO").upper()
logging.basicConfig(
    level=getattr(logging, LOG_LEVEL, logging.INFO),
    format="[%(asctime)s] [%(name)s] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
    stream=sys.stdout,
)
logger = logging.getLogger("feed_manager")

# ---------------------------------------------------------------------------
# Config
# ---------------------------------------------------------------------------

_KDBBASEPORT = int(os.environ.get("KDBBASEPORT", "9000"))

KDB_PYTHONFEED_HOST: str = os.environ.get("KDB_PYTHONFEED_HOST", "localhost")
KDB_PYTHONFEED_PORT: int = int(
    os.environ.get("KDB_PYTHONFEED_PORT", str(_KDBBASEPORT + 20))
)
_CONNECT_RETRY_S = 5


# ---------------------------------------------------------------------------
# pythonfeed connection
# ---------------------------------------------------------------------------

async def _connect_pythonfeed() -> kx.AsyncQConnection:
    """Connect to pythonfeed, retrying every _CONNECT_RETRY_S seconds."""
    attempt = 0
    while True:
        attempt += 1
        try:
            conn = await kx.AsyncQConnection(
                host=KDB_PYTHONFEED_HOST,
                port=KDB_PYTHONFEED_PORT,
            )
            logger.info(
                "Connected to pythonfeed at %s:%d",
                KDB_PYTHONFEED_HOST, KDB_PYTHONFEED_PORT,
            )
            return conn
        except Exception as exc:
            logger.error(
                "Cannot connect to pythonfeed at %s:%d (attempt %d): %s — retrying in %ds",
                KDB_PYTHONFEED_HOST, KDB_PYTHONFEED_PORT, attempt, exc, _CONNECT_RETRY_S,
            )
            await asyncio.sleep(_CONNECT_RETRY_S)


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

async def main() -> None:
    logger.info(
        "feed_manager starting — pythonfeed at %s:%d",
        KDB_PYTHONFEED_HOST, KDB_PYTHONFEED_PORT,
    )
    conn = await _connect_pythonfeed()

    tasks = [
        asyncio.create_task(run_binance_feed(conn), name="binance"),
        asyncio.create_task(run_kraken_feed(conn), name="kraken"),
        asyncio.create_task(run_okx_feed(conn), name="okx"),
    ]

    logger.info("Started %d feed task(s)", len(tasks))
    await asyncio.gather(*tasks)


if __name__ == "__main__":
    asyncio.run(main())
