#!/bin/bash
# deploy.sh — Deploy TorQ-Crypto and its dependencies into the deploy/ folder.
#
# Downloads the TorQ framework, overlays the local TorQ-Crypto application
# files, creates runtime directories, and sets up the Python virtual environment.
#
# Usage:
#   bash deploy.sh [OPTIONS]
#
# Options:
#   --torq-version VERSION   TorQ release tag to use (default: latest)
#   --dir PATH               Deployment directory (default: ./deploy)
#   --python BIN             Python binary to use for venv (default: python3)
#   --skip-venv              Skip Python virtual environment setup
#   --skip-torq              Skip TorQ download (redeploy app files only)
#
# Environment:
#   COINBASE_API_KEY         Set before starting if using Coinbase feed
#   COINBASE_API_SECRET      Set before starting if using Coinbase feed

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defaults
DEPLOY_DIR="${SCRIPT_DIR}/deploy"
TORQ_VERSION=""
PYTHON_BIN="python3"
SKIP_VENV=0
SKIP_TORQ=0

# ---------------------------------------------------------------------------
# Parse arguments
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
  case "$1" in
    --torq-version) TORQ_VERSION="$2"; shift 2 ;;
    --dir)          DEPLOY_DIR="$2";   shift 2 ;;
    --python)       PYTHON_BIN="$2";   shift 2 ;;
    --skip-venv)    SKIP_VENV=1;       shift ;;
    --skip-torq)    SKIP_TORQ=1;       shift ;;
    -h|--help)
      sed -n '/^# Usage:/,/^[^#]/{ /^[^#]/d; s/^# \?//; p }' "$0"
      exit 0 ;;
    *) echo "[deploy] Unknown argument: $1"; exit 1 ;;
  esac
done

echo "[deploy] ============================================================="
echo "[deploy] TorQ-Crypto Deployment"
echo "[deploy] Deploy directory : ${DEPLOY_DIR}"
echo "[deploy] ============================================================="

# ---------------------------------------------------------------------------
# Helper: resolve latest GitHub release tag
# ---------------------------------------------------------------------------
get_latest_release() {
  curl --silent --fail --max-time 15 \
    "https://api.github.com/repos/$1/releases/latest" \
    | grep -Po '"tag_name": "\K.*?(?=")'
}

# ---------------------------------------------------------------------------
# 1. Download and extract TorQ framework
# ---------------------------------------------------------------------------
if [ "${SKIP_TORQ}" -eq 0 ]; then
  if [ -z "${TORQ_VERSION}" ]; then
    echo "[deploy] Fetching latest TorQ release tag..."
    TORQ_VERSION="$(get_latest_release DataIntellectTech/TorQ)" || true
    if [ -z "${TORQ_VERSION}" ]; then
      echo "[deploy] ERROR: Could not fetch TorQ release tag from GitHub."
      echo "[deploy] Check your network connection, or specify a version manually:"
      echo "[deploy]   bash deploy.sh --torq-version v2.7.0"
      exit 1
    fi
  fi
  echo "[deploy] TorQ version : ${TORQ_VERSION}"

  TORQ_VER_BARE="${TORQ_VERSION#v}"
  TORQ_URL="https://github.com/DataIntellectTech/TorQ/archive/${TORQ_VERSION}.tar.gz"
  TORQ_ARCHIVE="/tmp/TorQ-${TORQ_VER_BARE}.tar.gz"

  if [ ! -f "${TORQ_ARCHIVE}" ]; then
    echo "[deploy] Downloading TorQ..."
    curl -fsSL "${TORQ_URL}" -o "${TORQ_ARCHIVE}"
  else
    echo "[deploy] Using cached archive: ${TORQ_ARCHIVE}"
  fi

  echo "[deploy] Extracting TorQ into ${DEPLOY_DIR}..."
  mkdir -p "${DEPLOY_DIR}"
  tar -xzf "${TORQ_ARCHIVE}" -C "${DEPLOY_DIR}" --strip-components=1
else
  echo "[deploy] Skipping TorQ download (--skip-torq)."
  mkdir -p "${DEPLOY_DIR}"
fi

# ---------------------------------------------------------------------------
# 2. Overlay TorQ-Crypto application files
# ---------------------------------------------------------------------------
echo "[deploy] Overlaying TorQ-Crypto application files..."

# Configuration — TorQ-Crypto appconfig takes precedence
cp -r "${SCRIPT_DIR}/appconfig"     "${DEPLOY_DIR}/"
# Permissions — overlay on top of TorQ defaults so ui/admin users are registered
if [ -d "${SCRIPT_DIR}/config/permissions" ]; then
  mkdir -p "${DEPLOY_DIR}/config/permissions"
  cp "${SCRIPT_DIR}/config/permissions/"*.csv "${DEPLOY_DIR}/config/permissions/"
fi
# Application code
cp -r "${SCRIPT_DIR}/code"          "${DEPLOY_DIR}/"
# Schema definitions
cp    "${SCRIPT_DIR}/database.q"    "${DEPLOY_DIR}/"
# Environment and start/stop scripts
cp    "${SCRIPT_DIR}/setenv.sh"      "${DEPLOY_DIR}/"
cp    "${SCRIPT_DIR}/start_all.sh"   "${DEPLOY_DIR}/"
cp    "${SCRIPT_DIR}/start_feeds.sh" "${DEPLOY_DIR}/"
cp    "${SCRIPT_DIR}/start_ui.sh"    "${DEPLOY_DIR}/"
cp    "${SCRIPT_DIR}/stop_all.sh"    "${DEPLOY_DIR}/"
cp    "${SCRIPT_DIR}/stop_feeds.sh"  "${DEPLOY_DIR}/"
cp    "${SCRIPT_DIR}/stop_ui.sh"     "${DEPLOY_DIR}/"

chmod +x "${DEPLOY_DIR}/setenv.sh"      \
         "${DEPLOY_DIR}/start_all.sh"   \
         "${DEPLOY_DIR}/start_feeds.sh" \
         "${DEPLOY_DIR}/start_ui.sh"    \
         "${DEPLOY_DIR}/stop_all.sh"    \
         "${DEPLOY_DIR}/stop_feeds.sh"  \
         "${DEPLOY_DIR}/stop_ui.sh"

echo "[deploy] Application files copied."

# ---------------------------------------------------------------------------
# 3. Create runtime directories (logs, HDB, WDB)
# ---------------------------------------------------------------------------
echo "[deploy] Creating runtime directories..."
mkdir -p "${DEPLOY_DIR}/logs"
mkdir -p "${DEPLOY_DIR}/hdb/database"
mkdir -p "${DEPLOY_DIR}/wdbhdb"
mkdir -p "${DEPLOY_DIR}/certs"

# ---------------------------------------------------------------------------
# 4. Set up Python virtual environment
# ---------------------------------------------------------------------------
REQUIREMENTS="${SCRIPT_DIR}/code/processes/feedhandler/requirements.txt"
VENV_DIR="${DEPLOY_DIR}/.venv"

if [ "${SKIP_VENV}" -eq 0 ]; then
  if [ -f "${REQUIREMENTS}" ]; then
    echo "[deploy] Setting up Python virtual environment at ${VENV_DIR}..."
    "${PYTHON_BIN}" -m venv "${VENV_DIR}"
    "${VENV_DIR}/bin/pip" install --quiet --upgrade pip
    "${VENV_DIR}/bin/pip" install -r "${REQUIREMENTS}"
    echo "[deploy] Python dependencies installed."
  else
    echo "[deploy] WARNING: ${REQUIREMENTS} not found — skipping venv setup."
  fi
else
  echo "[deploy] Skipping Python venv setup (--skip-venv)."
fi

# ---------------------------------------------------------------------------
# 5. Done
# ---------------------------------------------------------------------------
echo ""
echo "[deploy] ============================================================="
echo "[deploy] Deployment complete."
echo ""
echo "  Next steps:"
echo "  1. Edit ${DEPLOY_DIR}/setenv.sh to set exchange credentials and symbols."
echo "  2. Ensure kdb+ (q) is on your PATH."
echo "  3. Start the system:"
echo ""
echo "       bash ${DEPLOY_DIR}/start_all.sh"
echo ""
echo "  4. To stop the system:"
echo ""
echo "       bash ${DEPLOY_DIR}/stop_all.sh"
echo ""
echo "[deploy] ============================================================="
