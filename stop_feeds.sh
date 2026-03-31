#!/bin/bash
# stop_feeds.sh — Stop the Python WebSocket feed manager.
#
# Looks for a PID file written by start_feeds.sh first; falls back to
# searching for the feed_manager.py process by name.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PID_FILE="${SCRIPT_DIR}/run/feed_manager.pid"

echo "[stop_feeds] Stopping Python feed manager..."

stop_pid() {
  local pid="$1"
  if kill -0 "${pid}" 2>/dev/null; then
    kill "${pid}"
    echo "[stop_feeds] Sent SIGTERM to PID ${pid}."
    # Wait up to 5 s for graceful shutdown
    local i=0
    while kill -0 "${pid}" 2>/dev/null && [ "${i}" -lt 5 ]; do
      sleep 1
      i=$((i + 1))
    done
    if kill -0 "${pid}" 2>/dev/null; then
      kill -9 "${pid}" 2>/dev/null || true
      echo "[stop_feeds] Force-killed PID ${pid}."
    else
      echo "[stop_feeds] PID ${pid} exited cleanly."
    fi
  else
    echo "[stop_feeds] PID ${pid} is not running."
  fi
}

if [ -f "${PID_FILE}" ]; then
  PID="$(cat "${PID_FILE}")"
  echo "[stop_feeds] Found PID file: ${PID}"
  stop_pid "${PID}"
  rm -f "${PID_FILE}"
else
  # Fall back to searching by process name
  PIDS="$(pgrep -f 'feed_manager\.py' 2>/dev/null || true)"
  if [ -n "${PIDS}" ]; then
    echo "[stop_feeds] Found feed_manager.py process(es): ${PIDS}"
    for pid in ${PIDS}; do
      stop_pid "${pid}"
    done
  else
    echo "[stop_feeds] No feed_manager.py process found — nothing to stop."
  fi
fi

echo "[stop_feeds] Done."
