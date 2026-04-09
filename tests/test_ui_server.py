"""
tests/test_ui_server.py — Unit tests for the TorQ-Crypto UI server.

Mocks pykx at import time so no kdb+ connection is needed.

Run: pytest tests/test_ui_server.py -v
"""

from __future__ import annotations

import asyncio
import json
import os
import sys
from datetime import datetime
from unittest.mock import AsyncMock, MagicMock, patch

import pandas as pd
import pytest

# ---------------------------------------------------------------------------
# Mock pykx BEFORE importing server so that `import pykx as kx` is satisfied
# ---------------------------------------------------------------------------
_pykx_mock = MagicMock()
sys.modules.setdefault("pykx", _pykx_mock)

# Add code/ui to sys.path
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "code", "ui"))

import server as ui_server  # noqa: E402

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _gw_result(df: pd.DataFrame) -> MagicMock:
    """Wrap a DataFrame as a fake pykx query result."""
    r = MagicMock()
    r.pd.return_value = df
    return r


async def _http(port: int, method: str, path: str) -> tuple[int, dict, bytes]:
    """Make a raw HTTP/1.1 request; return (status, headers, body)."""
    reader, writer = await asyncio.open_connection("127.0.0.1", port)
    req = f"{method} {path} HTTP/1.1\r\nHost: localhost\r\nConnection: close\r\n\r\n"
    writer.write(req.encode())
    await writer.drain()

    data = b""
    while True:
        try:
            chunk = await asyncio.wait_for(reader.read(4096), timeout=5.0)
        except asyncio.TimeoutError:
            break
        if not chunk:
            break
        data += chunk

    writer.close()
    try:
        await writer.wait_closed()
    except Exception:
        pass

    sep = data.find(b"\r\n\r\n")
    header_raw = data[:sep].decode(errors="replace")
    body = data[sep + 4:]
    lines = header_raw.split("\r\n")
    status = int(lines[0].split()[1])
    hdrs: dict[str, str] = {}
    for line in lines[1:]:
        if ":" in line:
            k, v = line.split(":", 1)
            hdrs[k.strip().lower()] = v.strip()
    return status, hdrs, body


async def _start_server() -> tuple[asyncio.Server, int]:
    """Start handle_client on an ephemeral port; return (server, port)."""
    # Reset gateway state so each test starts clean
    ui_server._gw = None
    ui_server._gw_lock = None
    ui_server._clients.clear()

    srv = await asyncio.start_server(ui_server.handle_client, "127.0.0.1", 0)
    port: int = srv.sockets[0].getsockname()[1]
    return srv, port


def _run(coro):
    return asyncio.run(coro)


# ---------------------------------------------------------------------------
# Tests
# ---------------------------------------------------------------------------

def test_history_endpoint_returns_json():
    async def _inner():
        df = pd.DataFrame(
            {"time": [datetime(2026, 1, 1, 12, 0, 0)], "mid": [50123.45]}
        )
        mock_gw_obj = AsyncMock()
        mock_gw_obj.return_value = _gw_result(df)

        srv, port = await _start_server()
        async with srv:
            with patch.object(ui_server, "get_gw", AsyncMock(return_value=mock_gw_obj)):
                status, hdrs, body = await _http(port, "GET", "/api/history?sym=BTC-USD&mins=30")
                assert mock_gw_obj.call_args[0][0] == ".crypto.gethistory[`BTC-USD;30j]"

        assert status == 200, f"expected 200, got {status}"
        assert "application/json" in hdrs.get("content-type", ""), hdrs
        rows = json.loads(body)
        assert isinstance(rows, list)
        assert len(rows) == 1
        assert "time" in rows[0]
        assert "mid" in rows[0]
        assert abs(rows[0]["mid"] - 50123.45) < 0.01

    _run(_inner())


def test_history_missing_gateway_returns_503():
    async def _inner():
        async def _no_gw():
            raise ConnectionError("gateway unreachable")

        srv, port = await _start_server()
        async with srv:
            with patch.object(ui_server, "get_gw", _no_gw):
                status, hdrs, body = await _http(port, "GET", "/api/history?sym=BTC-USD&mins=30")

        assert status == 503, f"expected 503, got {status}"
        payload = json.loads(body)
        assert "error" in payload

    _run(_inner())


def test_static_index_served():
    async def _inner():
        srv, port = await _start_server()
        async with srv:
            status, hdrs, body = await _http(port, "GET", "/")

        assert status == 200, f"expected 200, got {status}"
        assert "text/html" in hdrs.get("content-type", ""), hdrs
        assert b"<html" in body.lower() or b"<!doctype" in body.lower()

    _run(_inner())


def test_path_traversal_blocked():
    async def _inner():
        srv, port = await _start_server()
        async with srv:
            status, hdrs, body = await _http(port, "GET", "/../../../etc/passwd")

        assert status == 403, f"expected 403, got {status}"

    _run(_inner())
