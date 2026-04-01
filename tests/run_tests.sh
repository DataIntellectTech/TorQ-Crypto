#!/usr/bin/env bash
# Run all unit test suites. Exit 1 if any fail.
#
# Usage: bash tests/run_tests.sh
#
# Integration tests (require a running stack) are NOT run here.
# See tests/integration/ for: smoke_test.sh, reconnect_test.sh, two_hour_run.sh

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PASS=0
FAIL=0

run_q_test() {
  local name="$1"
  local script="$2"
  if q "${REPO_ROOT}/${script}" 2>/dev/null; then
    echo "PASS: ${name}"
    ((PASS+=1)) || true
  else
    echo "FAIL: ${name}"
    ((FAIL+=1)) || true
  fi
}

# ---------------------------------------------------------------------------
# q unit tests
# ---------------------------------------------------------------------------
run_q_test "test_schemas" "tests/test_schemas.q"

# ---------------------------------------------------------------------------
# Python unit tests (uncomment as each phase is completed)
# ---------------------------------------------------------------------------
# run_pytest() {
#   local name="$1"
#   local file="$2"
#   if python -m pytest "${REPO_ROOT}/${file}" -q 2>/dev/null; then
#     echo "PASS: ${name}"
#     ((PASS+=1)) || true
#   else
#     echo "FAIL: ${name}"
#     ((FAIL+=1)) || true
#   fi
# }
# run_pytest "test_symmap"        "tests/test_symmap.py"
# run_pytest "test_binance_feed"  "tests/test_binance_feed.py"
# run_pytest "test_kraken_feed"   "tests/test_kraken_feed.py"
# run_pytest "test_okx_feed"      "tests/test_okx_feed.py"
# run_pytest "test_ui_server"     "tests/test_ui_server.py"
# run_pytest "test_replay"        "tests/test_replay.py"

# q integration tests (manual — require running stack)
# q tests/test_pythonfeed.q
# q tests/test_cryptoagg.q       (unit — uncomment when cryptoagg.q exists)
# q tests/test_eod.q             (unit — uncomment when eod config is complete)

# ---------------------------------------------------------------------------
# Result
# ---------------------------------------------------------------------------
echo ""
if [ "${FAIL}" -eq 0 ]; then
  echo "All ${PASS} test(s) passed."
  exit 0
else
  echo "${FAIL} test(s) FAILED, ${PASS} passed."
  exit 1
fi