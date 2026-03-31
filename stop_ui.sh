#!/bin/bash
# stop_ui.sh — Stop the TorQ-Crypto UI server.
#
# Looks for a PID file written by start_all.sh first; falls back to
# searching for the server.py process by name.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/run/ui_server.pid"

echo "[stop_ui] Stopping UI server..."

stop_pid() {
  local pid="$1"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}"
    echo "[stop_ui] Sent SIGTERM to PID ${pid}."
    local i=0
    while kill -0 "${pid}" 2>/dev/null && [ "${i}" -lt 5 ]; do
      sleep 1
      i=$((i + 1))
    done
    if kill -0 "${pid}" 2>/dev/null; then
      kill -9 "${pid}" 2>/dev/null || true
      echo "[stop_ui] Force-killed PID ${pid}."
    else
      echo "[stop_ui] PID ${pid} exited cleanly."
    fi
  else
    echo "[stop_ui] PID ${pid} is not running."
  fi
}

if [ -f "${PID_FILE}" ]; then
  PID="$(cat "${PID_FILE}")"
  echo "[stop_ui] Found PID file: ${PID}"
  stop_pid "${PID}"
  rm -f "${PID_FILE}"
else
  PIDS="$(pgrep -f 'ui/server\.py' 2>/dev/null || true)"
  if [ -n "${PIDS}" ]; then
    echo "[stop_ui] Found server.py process(es): ${PIDS}"
    for pid in ${PIDS}; do
      stop_pid "${pid}"
    done
  else
    echo "[stop_ui] No UI server process found — nothing to stop."
  fi
fi

echo "[stop_ui] Done."
