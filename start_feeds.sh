#!/bin/bash
# start_feeds.sh — Start the Python WebSocket feed manager.
# Sources setenv.sh for environment variables, activates the virtual
# environment if present, then runs feed_manager.py.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setenv.sh"

FEEDHANDLER_DIR="${SCRIPT_DIR}/code/processes/feedhandler"

if [ -d "${SCRIPT_DIR}/.venv" ]; then
  source "${SCRIPT_DIR}/.venv/bin/activate"
fi

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/pythonfeed_$(date +%Y_%m_%d_%H_%M_%S).log"

echo "Feed manager log: ${LOG_FILE}"
exec python "${FEEDHANDLER_DIR}/feed_manager.py" >> "${LOG_FILE}" 2>&1
