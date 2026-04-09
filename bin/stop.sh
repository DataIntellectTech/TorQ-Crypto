#!/usr/bin/env bash
# Stop kdb+ processes, Python feeds, UI server, or all.
#
# Usage:
#   bin/stop.sh [kdb|feeds|ui|all]   (default: all)
#
# kdb   — stop all kdb+ processes via torq.sh stop all.
#          Requires torq.sh to be present in TORQHOME.
# feeds — send SIGTERM to the feed manager process (identified by PID file).
# ui    — send SIGTERM to the UI server process (identified by PID file).
# all   — stop feeds and UI first, then kdb+ processes.

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
FEED_PID_FILE="${KDBLOG}/feed_manager.pid"
UI_PID_FILE="${KDBLOG}/ui_server.pid"

# ---------------------------------------------------------------------------
# stop_kdb: gracefully stop all kdb+ processes via torq.sh
# ---------------------------------------------------------------------------
stop_kdb() {
    if [ ! -f "${TORQSH}" ]; then
        echo "ERROR: torq.sh not found at ${TORQSH}"
        echo "       kdb+ processes may need to be stopped manually."
        exit 1
    fi
    echo "Stopping kdb+ processes..."
    bash "${TORQSH}" stop all
}

# ---------------------------------------------------------------------------
# stop_feeds: SIGTERM the feed manager process
# ---------------------------------------------------------------------------
stop_feeds() {
    if [ ! -f "${FEED_PID_FILE}" ]; then
        echo "No feed_manager.pid found at ${FEED_PID_FILE} — feeds may not be running."
        return 0
    fi

    local pid
    pid=$(cat "${FEED_PID_FILE}")

    if kill -0 "${pid}" 2>/dev/null; then
        echo "Stopping Python feed manager (pid ${pid})..."
        kill "${pid}"

        # Wait up to 10 s for the process to exit, then SIGKILL if needed
        local waited=0
        while kill -0 "${pid}" 2>/dev/null && [ "${waited}" -lt 10 ]; do
            sleep 1
            (( waited++ )) || true
        done

        if kill -0 "${pid}" 2>/dev/null; then
            echo "Process did not exit in 10 s — sending SIGKILL..."
            kill -9 "${pid}" 2>/dev/null || true
        else
            echo "Python feed manager stopped."
        fi
    else
        echo "Feed manager not running (stale PID file)."
    fi

    rm -f "${FEED_PID_FILE}"
}

# ---------------------------------------------------------------------------
# stop_ui: SIGTERM the UI server process
# ---------------------------------------------------------------------------
stop_ui() {
    if [ ! -f "${UI_PID_FILE}" ]; then
        echo "No ui_server.pid found at ${UI_PID_FILE} — UI server may not be running."
        return 0
    fi

    local pid
    pid=$(cat "${UI_PID_FILE}")

    if kill -0 "${pid}" 2>/dev/null; then
        echo "Stopping UI server (pid ${pid})..."
        kill "${pid}"

        local waited=0
        while kill -0 "${pid}" 2>/dev/null && [ "${waited}" -lt 10 ]; do
            sleep 1
            (( waited++ )) || true
        done

        if kill -0 "${pid}" 2>/dev/null; then
            echo "Process did not exit in 10 s — sending SIGKILL..."
            kill -9 "${pid}" 2>/dev/null || true
        else
            echo "UI server stopped."
        fi
    else
        echo "UI server not running (stale PID file)."
    fi

    rm -f "${UI_PID_FILE}"
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------
TARGET="${1:-all}"

case "${TARGET}" in
    kdb)
        stop_kdb
        ;;
    feeds)
        stop_feeds
        ;;
    ui)
        stop_ui
        ;;
    all)
        # Stop Python processes before kdb so they do not keep retrying IPC connections
        stop_feeds
        echo ""
        stop_ui
        echo ""
        stop_kdb
        ;;
    *)
        echo "Usage: $0 [kdb|feeds|ui|all]"
        echo "  kdb   — stop kdb+ processes only"
        echo "  feeds — stop Python feed manager only"
        echo "  ui    — stop UI server only"
        echo "  all   — stop feeds, UI, then kdb+ (default)"
        exit 1
        ;;
esac
