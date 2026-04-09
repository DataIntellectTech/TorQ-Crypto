#!/usr/bin/env python3
"""
TorQ-Crypto UI Server
=====================
Asyncio HTTP + WebSocket server. No web framework.

Configuration (environment variables):
  KDB_GATEWAY_HOST     — kdb+ gateway hostname (default: localhost)
  KDB_GATEWAY_PORT     — kdb+ gateway port     (default: KDBBASEPORT+7)
  KDB_GATEWAY_USER     — kdb+ gateway username (default: uiserver)
  KDB_GATEWAY_PASSWORD — kdb+ gateway password (default: pass)
  UI_PORT              — HTTP/WS listen port   (default: 8888)

Endpoints:
  ws://host:UI_PORT/ws                          — Live WebSocket feed (consolidated prices, 2 s)
  GET /api/history?sym=X&mins=30                — Consolidated mid timeseries
  GET /api/ohlc?sym=X                           — Today's OHLC session stats
  GET /api/arbitrage?sym=X&mins=30              — Time-bucketed arbitrage opportunities
  GET /                                         — Serves code/ui/static/index.html
  GET /<path>                                   — Serves files from code/ui/static/
"""

from __future__ import annotations

import asyncio
import base64
import hashlib
import json
import logging
import mimetypes
import os
import pathlib
import re
import struct
from datetime import datetime, timezone
from urllib.parse import parse_qs, urlparse

import pykx as kx

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

KDB_GATEWAY_HOST: str = os.environ.get("KDB_GATEWAY_HOST", "localhost")
KDB_GATEWAY_PORT: int = int(os.environ.get("KDB_GATEWAY_PORT", "9007"))
KDB_GATEWAY_USER: str = os.environ.get("KDB_GATEWAY_USER", "uiserver")
KDB_GATEWAY_PASSWORD: str = os.environ.get("KDB_GATEWAY_PASSWORD", "pass")
UI_PORT: int = int(os.environ.get("UI_PORT", "8888"))

STATIC_DIR: pathlib.Path = pathlib.Path(__file__).parent / "static"

# ---------------------------------------------------------------------------
# Logging
# ---------------------------------------------------------------------------

class _Fmt(logging.Formatter):
    def format(self, record: logging.LogRecord) -> str:
        ts = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
        return f"[{ts}] [ui_server] [{record.levelname}] {record.getMessage()}"


log = logging.getLogger("ui_server")
log.setLevel(logging.INFO)
_sh = logging.StreamHandler()
_sh.setFormatter(_Fmt())
log.addHandler(_sh)
log.propagate = False

# ---------------------------------------------------------------------------
# Gateway connection
# ---------------------------------------------------------------------------

_gw = None
_gw_lock: asyncio.Lock | None = None


def _get_lock() -> asyncio.Lock:
    global _gw_lock
    if _gw_lock is None:
        _gw_lock = asyncio.Lock()
    return _gw_lock


async def get_gw():
    """Return a live pykx.AsyncQConnection, connecting if needed."""
    global _gw
    async with _get_lock():
        if _gw is None:
            _gw = await kx.AsyncQConnection(
                host=KDB_GATEWAY_HOST,
                port=KDB_GATEWAY_PORT,
                username=KDB_GATEWAY_USER,
                password=KDB_GATEWAY_PASSWORD,
            )
            log.info(f"Connected to gateway {KDB_GATEWAY_HOST}:{KDB_GATEWAY_PORT}")
    return _gw


async def reset_gw() -> None:
    """Close and discard the current gateway connection."""
    global _gw
    async with _get_lock():
        if _gw is not None:
            try:
                await _gw.close()
            except Exception:
                pass
            _gw = None
    log.warning("Gateway connection reset")

# ---------------------------------------------------------------------------
# WebSocket client registry + minimal frame codec
# ---------------------------------------------------------------------------

_clients: set[asyncio.StreamWriter] = set()

_WS_MAGIC = "258EAFA5-E914-47DA-95CA-C5AB0DC85B11"


def _ws_accept(key: str) -> str:
    digest = hashlib.sha1((key + _WS_MAGIC).encode()).digest()
    return base64.b64encode(digest).decode()


def _ws_text_frame(payload: str) -> bytes:
    data = payload.encode("utf-8")
    n = len(data)
    if n <= 125:
        return bytes([0x81, n]) + data
    if n <= 65535:
        return bytes([0x81, 126]) + struct.pack(">H", n) + data
    return bytes([0x81, 127]) + struct.pack(">Q", n) + data


async def _read_frame(reader: asyncio.StreamReader) -> tuple[int, bytes] | None:
    try:
        hdr = await reader.readexactly(2)
    except (asyncio.IncompleteReadError, ConnectionResetError, OSError):
        return None
    opcode = hdr[0] & 0x0F
    masked = bool(hdr[1] & 0x80)
    length = hdr[1] & 0x7F
    try:
        if length == 126:
            length = struct.unpack(">H", await reader.readexactly(2))[0]
        elif length == 127:
            length = struct.unpack(">Q", await reader.readexactly(8))[0]
        mask = await reader.readexactly(4) if masked else b""
        raw = bytearray(await reader.readexactly(length))
    except (asyncio.IncompleteReadError, ConnectionResetError, OSError):
        return None
    if masked:
        for i in range(length):
            raw[i] ^= mask[i % 4]
    return opcode, bytes(raw)


async def _handle_ws(reader: asyncio.StreamReader,
                     writer: asyncio.StreamWriter,
                     key: str) -> None:
    accept = _ws_accept(key)
    writer.write(
        b"HTTP/1.1 101 Switching Protocols\r\n"
        b"Upgrade: websocket\r\n"
        b"Connection: Upgrade\r\n"
        + f"Sec-WebSocket-Accept: {accept}\r\n\r\n".encode()
    )
    await writer.drain()
    _clients.add(writer)
    log.info(f"WebSocket client connected ({len(_clients)} total)")
    try:
        while True:
            frame = await _read_frame(reader)
            if frame is None:
                break
            opcode, _ = frame
            if opcode == 8:  # close
                writer.write(b"\x88\x00")
                await writer.drain()
                break
            if opcode == 9:  # ping → pong
                writer.write(b"\x8a\x00")
                await writer.drain()
    except Exception:
        pass
    finally:
        _clients.discard(writer)
        try:
            writer.close()
            await writer.wait_closed()
        except Exception:
            pass
        log.info(f"WebSocket client disconnected ({len(_clients)} total)")


async def broadcast(msg: str) -> None:
    if not _clients:
        return
    frame = _ws_text_frame(msg)
    dead: set[asyncio.StreamWriter] = set()
    for w in list(_clients):
        try:
            w.write(frame)
            await w.drain()
        except Exception:
            dead.add(w)
    _clients.difference_update(dead)

# ---------------------------------------------------------------------------
# Background poller — queries gateway every 2 s, broadcasts to WS clients
# ---------------------------------------------------------------------------

async def poller() -> None:
    while True:
        try:
            gw = await get_gw()
            result = await gw(".crypto.getconsolidated[`]")
            rows = _df_to_json(result.pd())
            await broadcast(json.dumps({"type": "consolidated", "data": rows}))
        except Exception as exc:
            log.error(f"Poller error: {exc}")
            await reset_gw()
        await asyncio.sleep(2)

# ---------------------------------------------------------------------------
# Shared helpers
# ---------------------------------------------------------------------------

_SYM_RE = re.compile(r"^[A-Za-z0-9_\-\.]+$")

_STATUS_TEXT = {
    200: "OK", 400: "Bad Request", 403: "Forbidden",
    404: "Not Found", 405: "Method Not Allowed", 503: "Service Unavailable",
}

_ERR_GW  = json.dumps({"error": "gateway unavailable"}).encode()
_ERR_SYM = json.dumps({"error": "invalid sym"}).encode()
_ERR_MIN = json.dumps({"error": "invalid mins"}).encode()
_ERR_N   = json.dumps({"error": "invalid n"}).encode()
_JSON_CT = [("Content-Type", "application/json")]


def _df_to_json(df) -> list[dict]:
    """Convert a pandas DataFrame returned by pykx to a JSON-serialisable list."""
    rows = []
    for _, row in df.iterrows():
        d: dict = {}
        for col in df.columns:
            v = row[col]
            if hasattr(v, "isoformat"):
                d[col] = v.isoformat()
            elif hasattr(v, "item"):       # numpy scalar (bool, int, float, …)
                d[col] = v.item()
            else:
                try:
                    d[col] = float(v)
                except (TypeError, ValueError):
                    d[col] = str(v)
        rows.append(d)
    return rows


def _json_ok(rows: list[dict]) -> tuple[int, list[tuple], bytes]:
    body = json.dumps(rows).encode()
    return 200, [("Content-Type", "application/json"), ("Content-Length", str(len(body)))], body


def _gw_error(label: str, exc: Exception) -> tuple[int, list[tuple], bytes]:
    log.error(f"{label}: {exc}")
    return 503, _JSON_CT, _ERR_GW

# ---------------------------------------------------------------------------
# HTTP handlers
# ---------------------------------------------------------------------------

async def _history(params: dict) -> tuple[int, list[tuple], bytes]:
    sym = params.get("sym", ["BTC-USD"])[0]
    if not _SYM_RE.match(sym):
        return 400, _JSON_CT, _ERR_SYM

    mins_raw = params.get("mins", ["30"])[0]
    try:
        mins = int(mins_raw)
        if mins <= 0:
            raise ValueError
    except ValueError:
        return 400, _JSON_CT, _ERR_MIN

    q = f'.crypto.gethistory[`$"{sym}";{mins}j]'
    try:
        gw = await get_gw()
        result = await gw(q)
        df = result.pd()
        rows = [
            {"time": (row["time"].isoformat() if hasattr(row["time"], "isoformat") else str(row["time"])),
             "mid": float(row["mid"])}
            for _, row in df.iterrows()
        ]
        return _json_ok(rows)
    except (ConnectionError, OSError, BrokenPipeError) as exc:
        await reset_gw()
        return _gw_error("history connection", exc)
    except Exception as exc:
        await reset_gw()
        return _gw_error("history query", exc)


async def _ohlc(params: dict) -> tuple[int, list[tuple], bytes]:
    sym = params.get("sym", ["BTC-USD"])[0]
    if not _SYM_RE.match(sym):
        return 400, _JSON_CT, _ERR_SYM

    byvenue = params.get("byvenue", ["0"])[0] == "1"
    if byvenue:
        q = f'.crypto.ohlc[`sym`byvenue!(enlist `$"{sym}";1b)]'
    else:
        q = f'.crypto.ohlc[(enlist`sym)!enlist `$"{sym}"]'
    try:
        gw = await get_gw()
        result = await gw(q)
        return _json_ok(_df_to_json(result.pd()))
    except (ConnectionError, OSError, BrokenPipeError) as exc:
        await reset_gw()
        return _gw_error("ohlc connection", exc)
    except Exception as exc:
        return _gw_error("ohlc query", exc)


async def _arbitrage(params: dict) -> tuple[int, list[tuple], bytes]:
    sym = params.get("sym", ["BTC-USD"])[0]
    if not _SYM_RE.match(sym):
        return 400, _JSON_CT, _ERR_SYM

    mins_raw = params.get("mins", ["30"])[0]
    try:
        mins = int(mins_raw)
        if mins <= 0:
            raise ValueError
    except ValueError:
        return 400, _JSON_CT, _ERR_MIN

    # sym → type 11h, starttime/endtime → type 12h (enlist of timestamp atom)
    q = (
        f".crypto.arbitrage[`sym`starttime`endtime!"
        f'(enlist `$"{sym}";'
        f"enlist .z.p-{mins}*0D00:01;"
        f"enlist .z.p)]"
    )
    try:
        gw = await get_gw()
        result = await gw(q)
        return _json_ok(_df_to_json(result.pd()))
    except (ConnectionError, OSError, BrokenPipeError) as exc:
        await reset_gw()
        return _gw_error("arbitrage connection", exc)
    except Exception as exc:
        return _gw_error("arbitrage query", exc)


async def _trades(params: dict) -> tuple[int, list[tuple], bytes]:
    sym = params.get("sym", ["BTC-USD"])[0]
    if not _SYM_RE.match(sym):
        return 400, _JSON_CT, _ERR_SYM

    n_raw = params.get("n", ["50"])[0]
    try:
        n = int(n_raw)
        if n <= 0 or n > 500:
            raise ValueError
    except ValueError:
        return 400, _JSON_CT, _ERR_N

    q = f'.crypto.gettrades[`$"{sym}";{n}j]'
    try:
        gw = await get_gw()
        result = await gw(q)
        return _json_ok(_df_to_json(result.pd()))
    except (ConnectionError, OSError, BrokenPipeError) as exc:
        await reset_gw()
        return _gw_error("trades connection", exc)
    except Exception as exc:
        await reset_gw()
        return _gw_error("trades query", exc)


async def _static(path: str) -> tuple[int, list[tuple], bytes]:
    if path in ("/", ""):
        path = "/index.html"
    try:
        target = (STATIC_DIR / path.lstrip("/")).resolve()
        static_root = STATIC_DIR.resolve()
        inside = (
            str(target).startswith(str(static_root) + os.sep)
            or target == static_root
        )
        if not inside:
            return 403, [("Content-Type", "text/plain")], b"Forbidden"
    except Exception:
        return 403, [("Content-Type", "text/plain")], b"Forbidden"

    if not target.is_file():
        return 404, [("Content-Type", "text/plain")], b"Not Found"

    content = target.read_bytes()
    mime, _ = mimetypes.guess_type(str(target))
    if not mime:
        mime = "application/octet-stream"
    return 200, [("Content-Type", mime), ("Content-Length", str(len(content)))], content

# ---------------------------------------------------------------------------
# Connection handler — HTTP parser + router
# ---------------------------------------------------------------------------

async def handle_client(reader: asyncio.StreamReader,
                        writer: asyncio.StreamWriter) -> None:
    try:
        first = await asyncio.wait_for(reader.readline(), timeout=10.0)
    except asyncio.TimeoutError:
        writer.close()
        return
    if not first:
        writer.close()
        return

    parts = first.decode(errors="replace").strip().split()
    if len(parts) < 2:
        writer.close()
        return
    method, raw_path = parts[0], parts[1]

    headers: dict[str, str] = {}
    while True:
        try:
            line = await asyncio.wait_for(reader.readline(), timeout=10.0)
        except asyncio.TimeoutError:
            writer.close()
            return
        decoded = line.decode(errors="replace").strip()
        if not decoded:
            break
        if ":" in decoded:
            k, v = decoded.split(":", 1)
            headers[k.strip().lower()] = v.strip()

    parsed = urlparse(raw_path)
    path = parsed.path
    params = parse_qs(parsed.query)

    # WebSocket upgrade
    if (
        headers.get("upgrade", "").lower() == "websocket"
        and path == "/ws"
        and "sec-websocket-key" in headers
    ):
        await _handle_ws(reader, writer, headers["sec-websocket-key"])
        return

    # HTTP routing
    if method != "GET":
        status, hdrs, body = 405, [("Content-Type", "text/plain")], b"Method Not Allowed"
    elif path == "/api/history":
        status, hdrs, body = await _history(params)
    elif path == "/api/ohlc":
        status, hdrs, body = await _ohlc(params)
    elif path == "/api/arbitrage":
        status, hdrs, body = await _arbitrage(params)
    elif path == "/api/trades":
        status, hdrs, body = await _trades(params)
    else:
        status, hdrs, body = await _static(path)

    status_text = _STATUS_TEXT.get(status, "Unknown")
    hdr_str = "".join(f"{k}: {v}\r\n" for k, v in hdrs)
    writer.write(f"HTTP/1.1 {status} {status_text}\r\n{hdr_str}\r\n".encode())
    writer.write(body)
    try:
        await writer.drain()
    except Exception:
        pass
    try:
        writer.close()
        await writer.wait_closed()
    except Exception:
        pass

# ---------------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------------

async def main() -> None:
    log.info(f"UI server starting on http://0.0.0.0:{UI_PORT}")
    log.info(f"Gateway: {KDB_GATEWAY_HOST}:{KDB_GATEWAY_PORT}")
    log.info(f"Static: {STATIC_DIR}")
    server = await asyncio.start_server(handle_client, "0.0.0.0", UI_PORT)
    asyncio.create_task(poller())
    async with server:
        log.info("Ready.")
        await server.serve_forever()


if __name__ == "__main__":
    asyncio.run(main())
