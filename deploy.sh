#!/usr/bin/env bash
# deploy.sh — Build a self-contained TorQ-Crypto deployment in deploy/
#
# Merges the TorQ framework with the TorQ-Crypto application into a single
# directory, creates all required data directories, generates a fresh setenv.sh,
# and sets up the Python virtual environment.
#
# Usage:
#   bash deploy.sh [OPTIONS]
#
# Options:
#   --torq PATH     Path to a local TorQ framework clone/install.
#                   If omitted, looks for TorQ at ../TorQ relative to this repo.
#                   Download TorQ: https://github.com/AquaQAnalytics/TorQ/releases
#   --port PORT     Base port for kdb+ processes (default: 9000).
#   --clean         Remove existing framework files from deploy/ before rebuilding.
#                   Data directories (logs/, hdb/, wdbhdb/) are preserved.
#   --help          Show this message.
#
# After deployment:
#   cd deploy/
#   bash bin/start.sh all      # start everything
#   bash bin/stop.sh all       # stop everything
#   bash bin/start.sh feeds    # start Python feeds only

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="${SCRIPT_DIR}"
DEPLOY_DIR="${REPO_ROOT}/deploy"

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
TORQ_SRC=""
KDB_PORT="9000"
CLEAN=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --torq)
            TORQ_SRC="$2"
            shift 2
            ;;
        --port)
            KDB_PORT="$2"
            shift 2
            ;;
        --clean)
            CLEAN=1
            shift
            ;;
        --help|-h)
            head -30 "$0" | grep '^#' | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Unknown argument: $1"
            echo "Run 'bash deploy.sh --help' for usage."
            exit 1
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Locate TorQ framework
# ---------------------------------------------------------------------------
if [ -z "${TORQ_SRC}" ]; then
    CANDIDATE="$(cd "${REPO_ROOT}/.." && pwd)/TorQ"
    if [ -f "${CANDIDATE}/torq.q" ]; then
        TORQ_SRC="${CANDIDATE}"
        echo "Auto-detected TorQ at: ${TORQ_SRC}"
    else
        echo "ERROR: TorQ framework not found."
        echo ""
        echo "  Provide it via --torq, or place a TorQ clone at:"
        echo "    ${CANDIDATE}"
        echo ""
        echo "  Download TorQ from:"
        echo "    https://github.com/AquaQAnalytics/TorQ/releases"
        exit 1
    fi
fi

if [ ! -f "${TORQ_SRC}/torq.q" ]; then
    echo "ERROR: '${TORQ_SRC}' does not look like a TorQ installation (torq.q not found)."
    exit 1
fi

echo ""
echo "==> TorQ source : ${TORQ_SRC}"
echo "==> Deploy dir  : ${DEPLOY_DIR}"
echo "==> Base port   : ${KDB_PORT}"
echo ""

# ---------------------------------------------------------------------------
# Optional clean: remove framework files, keep data directories
# ---------------------------------------------------------------------------
if [ "${CLEAN}" -eq 1 ]; then
    echo "--- Clean: removing existing framework files ---"
    # Remove known framework/app dirs; preserve data dirs (logs, hdb, wdbhdb, certs)
    for item in torq.q torq.sh database.q setenv.sh appconfig code config html lib; do
        if [ -e "${DEPLOY_DIR}/${item}" ]; then
            rm -rf "${DEPLOY_DIR:?}/${item}"
            echo "  Removed: ${item}"
        fi
    done
    echo ""
fi

# ---------------------------------------------------------------------------
# Create directory structure
# ---------------------------------------------------------------------------
echo "--- Creating directory structure ---"

mkdir -p "${DEPLOY_DIR}"
mkdir -p "${DEPLOY_DIR}/bin"
mkdir -p "${DEPLOY_DIR}/logs"
mkdir -p "${DEPLOY_DIR}/hdb/database"
mkdir -p "${DEPLOY_DIR}/wdbhdb"
mkdir -p "${DEPLOY_DIR}/certs"

echo "  Created: bin/ logs/ hdb/database/ wdbhdb/ certs/"
echo ""

# ---------------------------------------------------------------------------
# Copy TorQ framework
# ---------------------------------------------------------------------------
echo "--- Copying TorQ framework ---"

for file in torq.q torq.sh; do
    if [ -f "${TORQ_SRC}/${file}" ]; then
        cp "${TORQ_SRC}/${file}" "${DEPLOY_DIR}/"
        echo "  Copied: ${file}"
    else
        echo "  WARNING: ${file} not found in TorQ source — skipping"
    fi
done

for dir in code config html lib bin; do
    if [ -d "${TORQ_SRC}/${dir}" ]; then
        mkdir -p "${DEPLOY_DIR}/${dir}"
        cp -r "${TORQ_SRC}/${dir}/." "${DEPLOY_DIR}/${dir}/"
        echo "  Copied: ${dir}/"
    fi
done

echo ""

# ---------------------------------------------------------------------------
# Overlay TorQ-Crypto application files
# (TorQ-Crypto wins on any filename collision — intentional)
# ---------------------------------------------------------------------------
echo "--- Overlaying TorQ-Crypto application ---"

# Application config (appconfig/ entirely from TorQ-Crypto)
cp -r "${REPO_ROOT}/appconfig" "${DEPLOY_DIR}/"
echo "  Copied: appconfig/"

# Application code merged on top of TorQ framework code
mkdir -p "${DEPLOY_DIR}/code"
cp -r "${REPO_ROOT}/code/." "${DEPLOY_DIR}/code/"
echo "  Merged: code/"

# Schema file (referenced by tickerplant as -schemafile .../database)
cp "${REPO_ROOT}/database.q" "${DEPLOY_DIR}/"
echo "  Copied: database.q"

echo ""

# ---------------------------------------------------------------------------
# Install control scripts into deploy/bin/
# ---------------------------------------------------------------------------
echo "--- Installing control scripts ---"

cp "${REPO_ROOT}/bin/start.sh" "${DEPLOY_DIR}/bin/"
cp "${REPO_ROOT}/bin/stop.sh"  "${DEPLOY_DIR}/bin/"
chmod +x "${DEPLOY_DIR}/bin/start.sh" "${DEPLOY_DIR}/bin/stop.sh"
echo "  Installed: bin/start.sh bin/stop.sh"

echo ""

# ---------------------------------------------------------------------------
# Generate deploy/setenv.sh
# Sets TORQHOME to the deploy directory so all paths resolve correctly
# regardless of where deploy/ was placed.
# ---------------------------------------------------------------------------
echo "--- Writing setenv.sh ---"

cat > "${DEPLOY_DIR}/setenv.sh" << 'SETENV_CONTENT'
#!/bin/bash
# setenv.sh — environment for this TorQ-Crypto deployment.
# Generated by deploy.sh — edit KDBBASEPORT here to change the port.

# BASH_SOURCE[0] is always the path of this file itself, even when sourced
# from another script (unlike $0 which refers to the calling script).
dirpath="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" && pwd)"

export TORQHOME="${dirpath}"
export TORQAPPHOME="${TORQHOME}"
export TORQDATAHOME="${TORQHOME}"

export KDBCONFIG="${TORQHOME}/config"
export KDBCODE="${TORQHOME}/code"
export KDBLOG="${TORQDATAHOME}/logs"
export KDBHTML="${TORQHOME}/html"
export KDBLIB="${TORQHOME}/lib"
export KDBHDB="${TORQDATAHOME}/hdb/database"
export KDBWDB="${TORQDATAHOME}/wdbhdb"

export RLWRAP="rlwrap"
export QCON="qcon"

export KDBAPPCONFIG="${TORQAPPHOME}/appconfig"
export KDBAPPCODE="${TORQAPPHOME}/code"

# Override KDBBASEPORT on the command line or in the environment before
# sourcing this file if you need a different base port.
export KDBBASEPORT="${KDBBASEPORT:-__PORT__}"

export TORQPROCESSES="${KDBAPPCONFIG}/process.csv"

# SSL certificate — download once if missing
TORQSSLCERT="${KDBLOG}/torqsslcert.txt"
touch "${TORQSSLCERT}" 2>/dev/null || true

if [ -z "${SSL_CA_CERT_FILE:-}" ]; then
    CERT="${TORQHOME}/certs/cabundle.pem"
    if [ ! -f "${CERT}" ]; then
        curl -s https://curl.haxx.se/ca/cacert.pm -o "${CERT}" 2>/dev/null || true
    fi
    export SSL_CA_CERT_FILE="${CERT}"
fi
SETENV_CONTENT

# Substitute the chosen base port into the generated setenv.sh
sed -i "s/__PORT__/${KDB_PORT}/" "${DEPLOY_DIR}/setenv.sh"
chmod +x "${DEPLOY_DIR}/setenv.sh"
echo "  Written: setenv.sh  (KDBBASEPORT=${KDB_PORT})"

echo ""

# ---------------------------------------------------------------------------
# Python virtual environment
# ---------------------------------------------------------------------------
echo "--- Setting up Python virtual environment ---"

VENV_DIR="${DEPLOY_DIR}/.venv"
REQUIREMENTS="${DEPLOY_DIR}/code/processes/feedhandler/requirements.txt"

if [ ! -f "${VENV_DIR}/bin/python" ]; then
    python3 -m venv "${VENV_DIR}"
    echo "  Created venv: .venv/"
else
    echo "  Venv already exists — upgrading packages"
fi

"${VENV_DIR}/bin/pip" install --quiet --upgrade pip
"${VENV_DIR}/bin/pip" install --quiet -r "${REQUIREMENTS}"
echo "  Installed: $(cat "${REQUIREMENTS}" | tr '\n' ' ')"

echo ""

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
echo "==========================================================="
echo "Deployment complete."
echo ""
echo "Location : ${DEPLOY_DIR}"
echo "Base port: ${KDB_PORT}"
echo ""
echo "Quick start:"
echo "  cd ${DEPLOY_DIR}"
echo "  bash bin/start.sh all       # start kdb+ and Python feeds"
echo ""
echo "Start components separately:"
echo "  bash bin/start.sh kdb       # kdb+ processes only"
echo "  bash bin/start.sh feeds     # Python feeds only"
echo ""
echo "Stop:"
echo "  bash bin/stop.sh all"
echo ""
echo "Logs:"
echo "  ${DEPLOY_DIR}/logs/"
echo "==========================================================="
