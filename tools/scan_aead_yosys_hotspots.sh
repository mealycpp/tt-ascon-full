#!/usr/bin/env bash
set -euo pipefail

mkdir -p reports hotspot_scan

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;93m"
BLUE="\033[0;34m"
NC="\033[0m"

LOG="reports/yosys_aead_hotspot_after_staged_maskpad.log"
SUM="hotspot_scan/aead_yosys_hotspot_summary.txt"

rm -f "$LOG" "$SUM"

echo -e "${BLUE}=== AEAD hotspot scan ===${NC}"
echo "Local source scan always runs."
echo "Yosys scan runs only if yosys exists locally."
echo "Summary: $SUM"
echo

echo "=== source-level AEAD memories/arrays ===" | tee -a "$SUM"
if grep -n 'reg .*\[.*:.*\].*\[.*\]' src/sdmc/sdmc_aead128_core.v | tee -a "$SUM"; then
  echo -e "${RED}FAIL: source-level reg-array memory found in AEAD.${NC}"
  exit 1
else
  echo "OK: no reg-array memories in AEAD core" | tee -a "$SUM"
fi

echo | tee -a "$SUM"
echo "=== source-level AEAD old repeated mask/pad calls ===" | tee -a "$SUM"
if grep -n "mask_n(w0_bytes_q)\|mask_n(w1_bytes_q)\|pad_n(w0_bytes_q\|pad_n(w1_bytes_q\|pad_n(3'd0)" \
  src/sdmc/sdmc_aead128_core.v | tee -a "$SUM"; then
  echo -e "${RED}FAIL: old repeated mask/pad calls still exist.${NC}"
  exit 1
else
  echo "OK: old repeated calls removed" | tee -a "$SUM"
fi

echo | tee -a "$SUM"
echo "=== source-level AEAD function/case scan ===" | tee -a "$SUM"
awk '
  /function/ {inside=1}
  inside {print NR ":" $0}
  /endfunction/ {inside=0}
' src/sdmc/sdmc_aead128_core.v | grep "case\|function\|endfunction" | tee -a "$SUM" || true

echo | tee -a "$SUM"
echo "=== local yosys availability ===" | tee -a "$SUM"

if ! command -v yosys >/dev/null 2>&1; then
  echo "SKIP: yosys is not installed locally; GitHub GDS action will run Yosys remotely." | tee -a "$SUM"
  echo
  echo -e "${YELLOW}SKIP: local Yosys scan unavailable.${NC}"
  echo -e "${GREEN}PASS: source-level AEAD scan is clean.${NC}"
  exit 0
fi

echo "Yosys found: $(command -v yosys)" | tee -a "$SUM"

echo | tee -a "$SUM"
echo "=== running bounded Yosys proc/opt scan ===" | tee -a "$SUM"

set +e
timeout 240s yosys -l "$LOG" -p "
  read_verilog -I src -I src/sdmc \
    src/project_sdmc_uart_top.v \
    src/uart_rx.v src/uart_tx.v \
    src/sdmc/sdmc_aead_uart_frontend.v \
    src/sdmc/sdmc_aead128_core.v \
    src/sdmc/sdmc_xof_family_core.v \
    src/sdmc/sdmc_xof_chain_family_core.v \
    src/sdmc/sdmc_ascon_perm_unit64.v \
    src/ascon_permutation.v src/ascon_round.v;
  hierarchy -check -top tt_um_mealycpp_ascon_sdmc_uart;
  proc;
  opt;
  memory;
  opt;
  stat;
"
RC=$?
set -e

echo "YOSYS_RC=$RC" | tee -a "$SUM"

if [ "$RC" -ne 0 ]; then
  echo -e "${RED}FAIL: Yosys scan did not complete cleanly. See $LOG${NC}"
  exit 1
fi

echo | tee -a "$SUM"
echo "=== AEAD memory/proc_rom/rdmux suspects ===" | tee -a "$SUM"
grep -n '\$memory\|proc_rom\|rdmux\|flatten\\u_aead\|flatten.u_aead\|u_aead' "$LOG" | tail -n 200 | tee -a "$SUM" || true

if grep -q '\$memory.*u_aead\|proc_rom.*u_aead\|flatten\\u_aead.*rdmux\|flatten.u_aead.*rdmux' "$LOG"; then
  echo -e "${RED}FAIL: AEAD still has Yosys memory/proc_rom/rdmux hotspot signatures.${NC}"
  echo "Read: $SUM"
  exit 1
fi

echo -e "${GREEN}PASS: no AEAD memory/proc_rom/rdmux hotspot signature found.${NC}"
echo "Read: $SUM"
