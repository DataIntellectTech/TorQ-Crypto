#!/bin/bash
# start_ui.sh — Start the TorQ-Crypto UI server.
# Sources setenv.sh for environment variables, activates the virtual
# environment if present, then runs code/ui/server.py.

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/setenv.sh"

UI_DIR="${SCRIPT_DIR}/code/ui"

if [ -d "${SCRIPT_DIR}/.venv" ]; then
  source "${SCRIPT_DIR}/.venv/bin/activate"
fi

LOG_DIR="${SCRIPT_DIR}/logs"
mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/ui_$(date +%Y_%m_%d_%H_%M_%S).log"

echo "UI server log: ${LOG_FILE}"
echo "UI server available at http://localhost:${UI_PORT:-8888}"
exec python "${UI_DIR}/server.py" >> "${LOG_FILE}" 2>&1