"""server.py — TorQ-Crypto UI server.

Serves static files from code/ui/static/ and provides:
  - WebSocket endpoint  ws://localhost:{UI_PORT}/ws
      Broadcasts consolidated order book and last trade prices to all
      connected browsers every 2 seconds by polling the TorQ gateway.
  - REST endpoints:
      GET /api/history?sym={sym}&mins={n}   — OHLC trade data
      GET /api/lastbook?sym={sym}            — per-venue top-of-book depth
      GET /api/orderbook?sym={sym}           — L2 order book
      GET /api/arbitrage?sym={sym}           — cross-venue arbitrage data

Configuration (environment variables):
  KDB_GATEWAY_HOST  — gateway hostname (e.g. localhost)
  KDB_GATEWAY_PORT  — gateway port
  KDB_USER          — kdb+ username (default: ui)
  KDB_PASSWORD      — kdb+ password (default: pass)
  UI_SYMBOLS        — comma-separated canonical symbols (default: BTC-USD,BTC-USDT,ETH-USD,ETH-USDT)
  UI_PORT           — HTTP/WS server port (default 8888)
"""

import asyncio
import json
import logging
import mimetypes
import os
import sys
import threading
from pathlib import Path

import pykx as kx
from aiohttp import web

logging.basicConfig(
    stream=sys.stdout,
    level=logging.INFO,
    format="%(asctime)s [ui_server] [%(levelname)s] %(message)s",
    datefmt="%Y-%m-%dT%H:%M:%S",
)
logger = logging.getLogger("ui_server")

STATIC_DIR  = Path(__file__).parent / "static"
UI_PORT     = int(os.environ.get("UI_PORT", "8888"))
GW_HOST     = os.environ["KDB_GATEWAY_HOST"]
GW_PORT     = int(os.environ["KDB_GATEWAY_PORT"])
GW_USER     = os.environ.get("KDB_USER", "ui")
GW_PASSWORD = os.environ.get("KDB_PASSWORD", "pass")
UI_SYMBOLS  = os.environ.get("UI_SYMBOLS", "BTC-USD,BTC-USDT,ETH-USD,ETH-USDT").split(",")
POLL_INTERVAL = 2  # seconds between gateway polls

# ---------------------------------------------------------------------------
# Gateway IPC helpers
# ---------------------------------------------------------------------------

_gw_conn: kx.QConnection | None = None
_gw_next_retry: float = 0.0   # epoch seconds — do not attempt before this time
_gw_lock = threading.Lock()   # serialise all IPC calls; kx.QConnection is not thread-safe
GW_RETRY_INTERVAL = 10        # seconds between reconnect attempts


def _ensure_gateway() -> kx.QConnection | None:
    """Must be called with _gw_lock held."""
    global _gw_conn, _gw_next_retry
    if _gw_conn is not None:
        return _gw_conn
    import time
    if time.monotonic() < _gw_next_retry:
        return None
    try:
        _gw_conn = kx.QConnection(host=GW_HOST, port=GW_PORT, username=GW_USER, password=GW_PASSWORD)
        logger.info("gateway connected at %s:%d as %s", GW_HOST, GW_PORT, GW_USER)
    except Exception as exc:
        logger.error("gateway connection failed: %s", exc)
        _gw_conn = None
        _gw_next_retry = time.monotonic() + GW_RETRY_INTERVAL
    return _gw_conn


def _kdb_to_json(result) -> list[dict]:
    """Convert a pykx Table to a JSON-serialisable list of dicts."""
    if result is None:
        return []
    try:
        df = result.pd()
        records = []
        for row in df.to_dict(orient="records"):
            clean = {}
            for k, v in row.items():
                if hasattr(v, "isoformat"):
                    clean[k] = v.isoformat()
                elif hasattr(v, "item"):  # numpy scalar
                    clean[k] = v.item()
                elif isinstance(v, (list, tuple)):
                    clean[k] = [x.item() if hasattr(x, "item") else x for x in v]
                else:
                    clean[k] = v
            records.append(clean)
        return records
    except Exception as exc:
        logger.error("kdb->json conversion failed: %s", exc)
        return []


def _syncexec(func: str, args: dict, proctype: str) -> list[dict]:
    """Route a function call through .gw.syncexec to a given process type."""
    with _gw_lock:
        conn = _ensure_gateway()
        if conn is None:
            return []
        query = kx.toq((kx.SymbolAtom(func), args))
        return _kdb_to_json(conn(".gw.syncexec", query, kx.SymbolAtom(proctype)))


# ---------------------------------------------------------------------------
# Fetch functions — one per kdb+ function
# ---------------------------------------------------------------------------

def _fetch_consolidated() -> list[dict]:
    global _gw_conn
    with _gw_lock:
        conn = _ensure_gateway()
        if conn is None:
            return []
        try:
            result = conn("getconsolidated", kx.SymbolVector(UI_SYMBOLS))
            return _kdb_to_json(result)
        except Exception as exc:
            logger.error("getconsolidated failed: %s", exc)
            _gw_conn = None
            return []


def _fetch_lastprices() -> list[dict]:
    global _gw_conn
    with _gw_lock:
        conn = _ensure_gateway()
        if conn is None:
            return []
        try:
            query = kx.toq((kx.SymbolAtom(".cryptoagg.getlastprices"), kx.SymbolVector(UI_SYMBOLS)))
            result = conn(".gw.syncexec", query, kx.SymbolAtom("cryptoagg"))
            return _kdb_to_json(result)
        except Exception as exc:
            logger.error("getlastprices failed: %s", exc)
            _gw_conn = None
            return []


def _fetch_lastbook(sym: str) -> list[dict]:
    global _gw_conn
    with _gw_lock:
        conn = _ensure_gateway()
        if conn is None:
            return []
        try:
            query = kx.toq((kx.SymbolAtom(".cryptoagg.getlastbook"), kx.SymbolAtom(sym)))
            result = conn(".gw.syncexec", query, kx.SymbolAtom("cryptoagg"))
            return _kdb_to_json(result)
        except Exception as exc:
            logger.error("getlastbook failed for %s: %s", sym, exc)
            _gw_conn = None
            return []


def _fetch_history(sym: str, mins: int) -> list[dict]:
    global _gw_conn
    with _gw_lock:
        conn = _ensure_gateway()
        if conn is None:
            return []
        try:
            query = kx.toq((
                kx.SymbolAtom("ohlc"),
                {"sym": kx.SymbolAtom(sym), "usetrade": kx.BooleanAtom(True)},
            ))
            result = conn(".gw.syncexec", query, kx.SymbolAtom("rdb"))
            return _kdb_to_json(result)
        except Exception as exc:
            logger.error("history query failed for %s: %s", sym, exc)
            _gw_conn = None
            return []


def _fetch_orderbook(sym: str) -> list[dict]:
    global _gw_conn
    with _gw_lock:
        conn = _ensure_gateway()
        if conn is None:
            return []
        try:
            query = kx.toq((kx.SymbolAtom("orderbook"), {"sym": kx.SymbolAtom(sym)}))
            result = conn(".gw.syncexec", query, kx.SymbolAtom("rdb"))
            return _kdb_to_json(result)
        except Exception as exc:
            logger.error("orderbook failed for %s: %s", sym, exc)
            _gw_conn = None
            return []


def _fetch_arbitrage(sym: str) -> list[dict]:
    global _gw_conn
    with _gw_lock:
        conn = _ensure_gateway()
        if conn is None:
            return []
        try:
            query = kx.toq((kx.SymbolAtom("arbitrage"), {"sym": kx.SymbolAtom(sym)}))
            result = conn(".gw.syncexec", query, kx.SymbolAtom("rdb"))
            return _kdb_to_json(result)
        except Exception as exc:
            logger.error("arbitrage failed for %s: %s", sym, exc)
            _gw_conn = None
            return []


# ---------------------------------------------------------------------------
# WebSocket broadcast loop
# ---------------------------------------------------------------------------

_browser_clients: set[web.WebSocketResponse] = set()


async def _broadcast_loop() -> None:
    """Poll gateway every POLL_INTERVAL seconds and push to browser clients."""
    while True:
        await asyncio.sleep(POLL_INTERVAL)
        if not _browser_clients:
            continue
        loop = asyncio.get_running_loop()
        # Run sequentially — kx.QConnection is not thread-safe; concurrent calls
        # from asyncio.gather corrupt the TCP stream and cause disconnects.
        consolidated = await loop.run_in_executor(None, _fetch_consolidated)
        lastprices   = await loop.run_in_executor(None, _fetch_lastprices)
        messages = [
            json.dumps({"type": "consolidated", "data": consolidated}),
            json.dumps({"type": "lastprices",   "data": lastprices}),
        ]
        dead = set()
        for ws in list(_browser_clients):
            try:
                for msg in messages:
                    await ws.send_str(msg)
            except Exception:
                dead.add(ws)
        _browser_clients.difference_update(dead)


# ---------------------------------------------------------------------------
# aiohttp request handlers
# ---------------------------------------------------------------------------

async def handle_ws(request: web.Request) -> web.WebSocketResponse:
    ws = web.WebSocketResponse()
    await ws.prepare(request)
    _browser_clients.add(ws)
    logger.info("browser WS connected (total: %d)", len(_browser_clients))
    try:
        async for _ in ws:
            pass
    except Exception:
        pass
    finally:
        _browser_clients.discard(ws)
        logger.info("browser WS disconnected (total: %d)", len(_browser_clients))
    return ws


def _json_response(data: list[dict]) -> web.Response:
    return web.Response(
        text=json.dumps(data),
        content_type="application/json",
        headers={"Access-Control-Allow-Origin": "*"},
    )


async def handle_history(request: web.Request) -> web.Response:
    sym  = request.rel_url.query.get("sym", "BTC-USD")
    mins = int(request.rel_url.query.get("mins", "30"))
    loop = asyncio.get_running_loop()
    return _json_response(await loop.run_in_executor(None, _fetch_history, sym, mins))


async def handle_lastbook(request: web.Request) -> web.Response:
    sym  = request.rel_url.query.get("sym", UI_SYMBOLS[0])
    loop = asyncio.get_running_loop()
    return _json_response(await loop.run_in_executor(None, _fetch_lastbook, sym))


async def handle_orderbook(request: web.Request) -> web.Response:
    sym  = request.rel_url.query.get("sym", UI_SYMBOLS[0])
    loop = asyncio.get_running_loop()
    return _json_response(await loop.run_in_executor(None, _fetch_orderbook, sym))


async def handle_arbitrage(request: web.Request) -> web.Response:
    sym  = request.rel_url.query.get("sym", UI_SYMBOLS[0])
    loop = asyncio.get_running_loop()
    return _json_response(await loop.run_in_executor(None, _fetch_arbitrage, sym))


async def handle_static(request: web.Request) -> web.Response:
    file_path = request.match_info.get("path", "") or "index.html"
    full_path = STATIC_DIR / file_path
    if not full_path.is_file():
        raise web.HTTPNotFound()
    content = full_path.read_bytes()
    mime = mimetypes.guess_type(str(full_path))[0] or "application/octet-stream"
    return web.Response(body=content, content_type=mime)


# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def serve() -> None:
    with _gw_lock:
        _ensure_gateway()

    app = web.Application()
    app.router.add_get("/ws",            handle_ws)
    app.router.add_get("/api/history",   handle_history)
    app.router.add_get("/api/lastbook",  handle_lastbook)
    app.router.add_get("/api/orderbook", handle_orderbook)
    app.router.add_get("/api/arbitrage", handle_arbitrage)
    app.router.add_get("/",              handle_static, name="index")
    app.router.add_get("/{path:.+}",     handle_static)

    broadcast_task = asyncio.create_task(_broadcast_loop())

    runner = web.AppRunner(app)
    await runner.setup()
    site = web.TCPSite(runner, "0.0.0.0", UI_PORT)
    await site.start()

    logger.info("server listening on http://0.0.0.0:%d", UI_PORT)
    logger.info("WebSocket available at ws://0.0.0.0:%d/ws", UI_PORT)

    try:
        await asyncio.Event().wait()
    finally:
        broadcast_task.cancel()
        await runner.cleanup()


if __name__ == "__main__":
    asyncio.run(serve())
