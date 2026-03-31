#!/bin/bash
# stop_all.sh — Stop the entire TorQ-Crypto system.
#
# Sequence:
#   1. Stop the Python feed manager
#   2. Stop all TorQ kdb+ processes via torq.sh

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setenv.sh"

# ---------------------------------------------------------------------------
# 1. Stop UI server
# ---------------------------------------------------------------------------
echo "[stop_all] Stopping UI server..."
bash "${SCRIPT_DIR}/stop_ui.sh"

# ---------------------------------------------------------------------------
# 2. Stop Python feeds
# ---------------------------------------------------------------------------
echo "[stop_all] Stopping Python feed manager..."
bash "${SCRIPT_DIR}/stop_feeds.sh"

# ---------------------------------------------------------------------------
# 3. Stop TorQ kdb+ stack
# ---------------------------------------------------------------------------
TORQSH="${SCRIPT_DIR}/torq.sh"
if [ ! -f "${TORQSH}" ]; then
  echo "[stop_all] ERROR: torq.sh not found at ${TORQSH}."
  echo "[stop_all] Run deploy.sh first, then run stop_all.sh from the deploy/ directory."
  exit 1
fi

echo "[stop_all] Stopping TorQ kdb+ stack..."
bash "${TORQSH}" stop all

# ---------------------------------------------------------------------------
# 3. Done
# ---------------------------------------------------------------------------
echo "[stop_all] System stopped."
