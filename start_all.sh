#!/bin/bash
# start_all.sh — Start the entire TorQ-Crypto system end to end.
#
# Sequence:
#   1. Source setenv.sh
#   2. Start the kdb+ TorQ stack (all processes)
#   3. Wait for the discovery process to be ready (up to 60 s)
#   4. Start the Python feeds in the background
#   5. Log startup completion

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setenv.sh"

# Ensure required runtime directories exist before any process starts
mkdir -p "${KDBLOG}" "${KDBHDB}" "${KDBWDB}"

# ---------------------------------------------------------------------------
# 1. Start TorQ kdb+ stack
# ---------------------------------------------------------------------------
echo "[start_all] Starting TorQ kdb+ stack..."
bash "${SCRIPT_DIR}/torq.sh" start all

# ---------------------------------------------------------------------------
# 2. Wait for discovery process
# ---------------------------------------------------------------------------
KDBDISCOVERYPORT=$((KDBBASEPORT+1))
echo "[start_all] Waiting for discovery process on port ${KDBDISCOVERYPORT}..."
timeout 60 bash -c "until nc -z localhost ${KDBDISCOVERYPORT} 2>/dev/null; do sleep 1; done" \
  || { echo "[start_all] ERROR: discovery process did not start within 60 s"; exit 1; }
echo "[start_all] Discovery process is ready."

# ---------------------------------------------------------------------------
# 3. Start Python feeds
# ---------------------------------------------------------------------------
echo "[start_all] Starting Python feed manager..."
mkdir -p "${SCRIPT_DIR}/run"
bash "${SCRIPT_DIR}/start_feeds.sh" &
FEED_PID=$!
echo "${FEED_PID}" > "${SCRIPT_DIR}/run/feed_manager.pid"
echo "[start_all] Feed manager PID: ${FEED_PID}"

# ---------------------------------------------------------------------------
# 4. Start UI server
# ---------------------------------------------------------------------------
echo "[start_all] Starting UI server..."
bash "${SCRIPT_DIR}/start_ui.sh" &
UI_PID=$!
echo "${UI_PID}" > "${SCRIPT_DIR}/run/ui_server.pid"
echo "[start_all] UI server PID: ${UI_PID}"

# ---------------------------------------------------------------------------
# 5. Done
# ---------------------------------------------------------------------------
echo "[start_all] System started."
echo "[start_all] UI available at http://localhost:${UI_PORT:-8888}"
