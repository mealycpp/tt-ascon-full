#!/usr/bin/env bash
set -euo pipefail

BASE="$(pwd)"
TS="$(date +%Y%m%d_%H%M%S)"
REPORT="$BASE/reports/restore_gds_pass"
CAND="$BASE/ci_artifacts/sdmc-single-uart-gds-pass/tt_submission/src"

mkdir -p "$REPORT"

echo "===== RESTORE SDMC SINGLE-UART GDS PASS RTL =====" | tee "$REPORT/run.log"
echo "BASE=$BASE" | tee -a "$REPORT/run.log"
echo "CAND=$CAND" | tee -a "$REPORT/run.log"

if [ ! -d "$CAND" ]; then
  echo "ERROR: missing candidate src: $CAND" | tee -a "$REPORT/run.log"
  exit 1
fi

echo "===== BACKUP CURRENT SRC =====" | tee -a "$REPORT/run.log"
cp -a src "src.before_restore_gds_pass_$TS"

echo "===== RESTORE SRC FROM GDS PASS ARTIFACT =====" | tee -a "$REPORT/run.log"
rm -rf src
cp -a "$CAND" src

echo "===== RESTORE OLD SINGLE-UART TESTBENCH FILES =====" | tee -a "$REPORT/run.log"
find test/sdmc_top_uart_aead_matrix -name '*.v.bak_single_uart_aead' -print0 2>/dev/null \
  | while IFS= read -r -d '' f; do
      cp "$f" "${f%.bak_single_uart_aead}"
    done

echo "===== FIND UART RX/TX SOURCES =====" | tee -a "$REPORT/run.log"
UART_RX_SRC="$(grep -RslE '^[[:space:]]*module[[:space:]]+uart_rx\b' src test | head -n 1 || true)"
UART_TX_SRC="$(grep -RslE '^[[:space:]]*module[[:space:]]+uart_tx\b' src test | head -n 1 || true)"
echo "UART_RX_SRC=$UART_RX_SRC" | tee -a "$REPORT/run.log"
echo "UART_TX_SRC=$UART_TX_SRC" | tee -a "$REPORT/run.log"

if [ -z "$UART_RX_SRC" ] || [ -z "$UART_TX_SRC" ]; then
  echo "ERROR: uart_rx or uart_tx not found" | tee -a "$REPORT/run.log"
  exit 1
fi

echo "===== OFFICIAL CORE MATRIX =====" | tee -a "$REPORT/run.log"
bash tools/run_sdmc_aead_official_matrix.sh 2>&1 | tee "$REPORT/official_core_matrix.log"

grep -iE "PASS|FAIL|error|syntax|unknown module|unable to bind|not a port|already been declared|failed" \
  "$REPORT/official_core_matrix.log" | tee -a "$REPORT/run.log"

echo "===== OLD SINGLE-UART C001 TESTS =====" | tee -a "$REPORT/run.log"

for MODE in enc dec badtag; do
  TB="test/sdmc_top_uart_aead_matrix/sdmc_top_uart_kat_c001_ad0_pt0_${MODE}/tb_sdmc_top_uart_kat_c001_ad0_pt0_${MODE}.v"
  VVP="/tmp/sdmc_gds_pass_c001_${MODE}.vvp"
  CLOG="$REPORT/compile_c001_${MODE}.log"
  RLOG="$REPORT/run_c001_${MODE}.log"

  echo "===== COMPILE C001 $MODE =====" | tee -a "$REPORT/run.log"

  iverilog -g2012 -I src -I src/sdmc \
    -o "$VVP" \
    "$TB" \
    src/project_sdmc_uart_top.v \
    "$UART_RX_SRC" \
    "$UART_TX_SRC" \
    src/ascon_round.v \
    src/ascon_permutation.v \
    src/sdmc/*.v \
    > "$CLOG" 2>&1 || true

  if grep -qiE "error|syntax|unknown module|unable to bind|not a port|already been declared|failed" "$CLOG"; then
    echo "COMPILE_FAIL $MODE" | tee -a "$REPORT/run.log"
    grep -iE "error|syntax|unknown module|unable to bind|not a port|already been declared|failed" "$CLOG" | tee -a "$REPORT/run.log"
    exit 1
  fi

  echo "COMPILE CLEAN $MODE" | tee -a "$REPORT/run.log"

  echo "===== RUN C001 $MODE =====" | tee -a "$REPORT/run.log"
  timeout 240s vvp "$VVP" > "$RLOG" 2>&1 || true

  grep -iE "PASS|FAIL|output bytes|auth_ok|busy|done|error" "$RLOG" | tee -a "$REPORT/run.log"

  if grep -qi "FAIL" "$RLOG"; then
    echo "RUN_FAIL $MODE" | tee -a "$REPORT/run.log"
    exit 1
  fi

  if ! grep -qi "PASS" "$RLOG"; then
    echo "NO_PASS $MODE" | tee -a "$REPORT/run.log"
    exit 1
  fi
done

echo "===== STABLE SINGLE-UART RESTORE PASSED =====" | tee -a "$REPORT/run.log"
git status --short | tee "$REPORT/git_status_after_restore.txt"
