#!/usr/bin/env bash
# Start kdb+ processes, Python feeds, UI server, or all.
#
# Usage:
#   bin/start.sh [kdb|feeds|ui|all]   (default: all)
#
# kdb   — start all kdb+ processes listed in process.csv (startwithall=1)
#          Requires torq.sh to be present in TORQHOME (i.e. after deploy.sh).
# feeds — start the Python feed manager (binance, kraken, okx) in the background.
#          Requires .venv to exist in TORQHOME (created by deploy.sh or manually).
# ui    — start the asyncio HTTP/WebSocket UI server (code/ui/server.py).
#          Requires .venv and code/ui/requirements.txt to be installed.
# all   — start kdb first, wait 10 s for processes to come up, then start feeds + ui.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# ---------------------------------------------------------------------------
# Load environment
# ---------------------------------------------------------------------------
SETENV_FILE="${REPO_ROOT}/setenv.sh"
if [ ! -f "${SETENV_FILE}" ]; then
    echo "ERROR: setenv.sh not found at ${SETENV_FILE}"
    exit 1
fi
# shellcheck source=/dev/null
. "${SETENV_FILE}"

TORQSH="${TORQHOME}/torq.sh"
VENV_PYTHON="${TORQHOME}/.venv/bin/python"
FEED_MANAGER_DIR="${KDBAPPCODE}/processes/feedhandler"
FEED_PID_FILE="${KDBLOG}/feed_manager.pid"
FEED_LOG_FILE="${KDBLOG}/feed_manager.log"
UI_SERVER="${KDBAPPCODE}/ui/server.py"
UI_PID_FILE="${KDBLOG}/ui_server.pid"
UI_LOG_FILE="${KDBLOG}/ui_server.log"

# ---------------------------------------------------------------------------
# start_kdb: launch all startwithall=1 processes via torq.sh
# ---------------------------------------------------------------------------
start_kdb() {
    if [ ! -f "${TORQSH}" ]; then
        echo "ERROR: torq.sh not found at ${TORQSH}"
        echo "       Run 'bash deploy.sh' to build a self-contained deployment first."
        exit 1
    fi
    echo "Starting kdb+ processes..."
    bash "${TORQSH}" start all
}

# ---------------------------------------------------------------------------
# start_feeds: launch feed_manager.py in the background
# ---------------------------------------------------------------------------
start_feeds() {
    # Check for stale / active PID file
    if [ -f "${FEED_PID_FILE}" ]; then
        local existing_pid
        existing_pid=$(cat "${FEED_PID_FILE}")
        if kill -0 "${existing_pid}" 2>/dev/null; then
            echo "Python feeds already running (pid ${existing_pid})"
            echo "  log: ${FEED_LOG_FILE}"
            return 0
        else
            echo "Removing stale PID file (pid ${existing_pid} is not running)"
            rm -f "${FEED_PID_FILE}"
        fi
    fi

    if [ ! -f "${VENV_PYTHON}" ]; then
        echo "ERROR: Python venv not found at ${TORQHOME}/.venv"
        echo "       Run 'bash deploy.sh' or create the venv manually:"
        echo "         python3 -m venv ${TORQHOME}/.venv"
        echo "         ${TORQHOME}/.venv/bin/pip install -r ${FEED_MANAGER_DIR}/requirements.txt"
        exit 1
    fi

    if [ ! -d "${FEED_MANAGER_DIR}" ]; then
        echo "ERROR: feedhandler directory not found at ${FEED_MANAGER_DIR}"
        exit 1
    fi

    mkdir -p "${KDBLOG}"

    # Start the feed manager.  Must cd to its directory so that sibling
    # imports (binance_feed, kraken_feed, okx_feed, symmap) resolve correctly.
    pushd "${FEED_MANAGER_DIR}" > /dev/null
    nohup "${VENV_PYTHON}" feed_manager.py >> "${FEED_LOG_FILE}" 2>&1 &
    local feed_pid=$!
    echo "${feed_pid}" > "${FEED_PID_FILE}"
    popd > /dev/null

    echo "Python feed manager started"
    echo "  pid: ${feed_pid}"
    echo "  log: ${FEED_LOG_FILE}"
}

# ---------------------------------------------------------------------------
# start_ui: launch server.py in the background
# ---------------------------------------------------------------------------
start_ui() {
    if [ -f "${UI_PID_FILE}" ]; then
        local existing_pid
        existing_pid=$(cat "${UI_PID_FILE}")
        if kill -0 "${existing_pid}" 2>/dev/null; then
            echo "UI server already running (pid ${existing_pid})"
            echo "  log: ${UI_LOG_FILE}"
            return 0
        else
            echo "Removing stale PID file (pid ${existing_pid} is not running)"
            rm -f "${UI_PID_FILE}"
        fi
    fi

    if [ ! -f "${VENV_PYTHON}" ]; then
        echo "ERROR: Python venv not found at ${TORQHOME}/.venv"
        echo "       Run 'bash deploy.sh' or create the venv manually:"
        echo "         python3 -m venv ${TORQHOME}/.venv"
        echo "         ${TORQHOME}/.venv/bin/pip install -r ${KDBAPPCODE}/ui/requirements.txt"
        exit 1
    fi

    if [ ! -f "${UI_SERVER}" ]; then
        echo "ERROR: UI server not found at ${UI_SERVER}"
        exit 1
    fi

    mkdir -p "${KDBLOG}"

    nohup "${VENV_PYTHON}" "${UI_SERVER}" >> "${UI_LOG_FILE}" 2>&1 &
    local ui_pid=$!
    echo "${ui_pid}" > "${UI_PID_FILE}"

    echo "UI server started"
    echo "  pid:  ${ui_pid}"
    echo "  log:  ${UI_LOG_FILE}"
    echo "  url:  http://localhost:${UI_PORT:-8888}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
TARGET="${1:-all}"

case "${TARGET}" in
    kdb)
        start_kdb
        ;;
    feeds)
        start_feeds
        ;;
    ui)
        start_ui
        ;;
    all)
        start_kdb
        echo ""
        echo "Waiting 10 s for kdb+ processes to initialise before starting feeds and UI..."
        sleep 10
        start_feeds
        echo ""
        start_ui
        ;;
    *)
        echo "Usage: $0 [kdb|feeds|ui|all]"
        echo "  kdb   — start kdb+ processes only"
        echo "  feeds — start Python feed manager only"
        echo "  ui    — start UI server only"
        echo "  all   — start kdb+, feeds, and UI (default)"
        exit 1
        ;;
esac
