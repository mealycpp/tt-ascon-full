#!/usr/bin/env bash
set -u -o pipefail

mkdir -p reports
LOG="reports/sdmc_aggressive_regression.log"
RESULTS="reports/sdmc_aggressive_regression_results.tsv"
: > "$RESULTS"
: > "$LOG"

PASS_COUNT=0
FAIL_COUNT=0

run_step() {
  local name="$1"
  shift

  echo
  echo "=== ${name} ===" | tee -a "$LOG"

  if "$@" 2>&1 | tee -a "$LOG"; then
    echo -e "${name}\tPASS" >> "$RESULTS"
    PASS_COUNT=$((PASS_COUNT + 1))
  else
    echo -e "${name}\tFAIL" >> "$RESULTS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_step "uart_hx_top_syntax" ./tools/check_sdmc_uart_top_syntax.sh
run_step "uart_hx_hash_smoke" ./tools/run_sdmc_uart_smoke.sh

if [ -x ./tools/run_sdmc_aead_official_matrix.sh ]; then
  run_step "aead_official_matrix_preserved" ./tools/run_sdmc_aead_official_matrix.sh
fi

if [ -x ./tools/run_sdmc_chain_vector_matrix.sh ]; then
  run_step "xof_cxof_chain_vector_matrix" ./tools/run_sdmc_chain_vector_matrix.sh
fi

if [ -x ./tools/run_sdmc_massive_regression.sh ]; then
  run_step "massive_regression" ./tools/run_sdmc_massive_regression.sh
fi

run_step "gds_filelist_audit" ./tools/check_sdmc_gds_filelist.sh
run_step "gds_risk_audit" python3 tools/sdmc_gds_risk_audit_pretty.py

echo
echo "=== SDMC AGGRESSIVE REGRESSION SUMMARY ===" | tee -a "$LOG"
cat "$RESULTS" | tee -a "$LOG"

echo
if [ "$FAIL_COUNT" -eq 0 ]; then
  echo "PASS sdmc_aggressive_regression: ${PASS_COUNT} passed, 0 failed" | tee -a "$LOG"
  exit 0
else
  echo "FAIL sdmc_aggressive_regression: ${PASS_COUNT} passed, ${FAIL_COUNT} failed" | tee -a "$LOG"
  exit 1
fi
