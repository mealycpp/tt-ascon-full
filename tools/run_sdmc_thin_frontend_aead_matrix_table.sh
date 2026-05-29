#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

mkdir -p reports
RESULTS="reports/sdmc_thin_frontend_aead_matrix_results.tsv"
LOGDIR="reports/thin_frontend_aead_matrix_logs"
mkdir -p "$LOGDIR"
: > "$RESULTS"

python3 tools/sdmc_generate_thin_frontend_aead_matrix.py

PASS_COUNT=0
FAIL_COUNT=0

while read -r name; do
  [ -n "$name" ] || continue

  tb="test/sdmc_thin_frontend_aead_matrix/${name}/tb_${name}.v"
  vvp="test/sdmc_thin_frontend_aead_matrix/${name}/tb_${name}.vvp"
  log="${LOGDIR}/${name}.log"

  echo "=== $name ==="

  if ! iverilog -g2012 -I src -I src/sdmc \
    -o "$vvp" \
    src/ascon_round.v \
    src/ascon_permutation.v \
    src/sdmc/sdmc_aead_uart_frontend.v \
    src/sdmc/sdmc_aead128_core.v \
    src/sdmc/sdmc_ascon_perm_unit64.v \
    src/sdmc/sdmc_crypto_helpers.v \
    "$tb" > "$log" 2>&1; then

    detail="$(tail -n 1 "$log" | sed 's/\t/ /g')"
    printf "%s\tFAIL\tCOMPILE\t%s\n" "$name" "$detail" >> "$RESULTS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
    continue
  fi

  if timeout 30s vvp "$vvp" >> "$log" 2>&1; then
    if grep -q "PASS ${name}" "$log"; then
      printf "%s\tPASS\tSIM\tOK\n" "$name" >> "$RESULTS"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      detail="$(grep -E "FAIL|ERROR|timeout" "$log" | tail -n 1 | sed 's/\t/ /g')"
      [ -n "$detail" ] || detail="No PASS line found"
      printf "%s\tFAIL\tSIM\t%s\n" "$name" "$detail" >> "$RESULTS"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    detail="$(grep -E "FAIL|ERROR|timeout" "$log" | tail -n 1 | sed 's/\t/ /g')"
    [ -n "$detail" ] || detail="vvp timeout/crash"
    printf "%s\tFAIL\tSIM\t%s\n" "$name" "$detail" >> "$RESULTS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi

done < test/sdmc_thin_frontend_aead_matrix/manifest.txt

echo
echo "=== THIN FRONTEND AEAD MATRIX SUMMARY ==="
printf "+------------------------------------------------------+--------+---------+------------------------------------------------------------+\n"
printf "| Test                                                 | Status | Stage   | Detail                                                     |\n"
printf "+------------------------------------------------------+--------+---------+------------------------------------------------------------+\n"

while IFS=$'\t' read -r test status stage detail; do
  if [ "$status" = "PASS" ]; then
    mark="${GREEN}PASS ✅${RESET}"
  else
    mark="${RED}FAIL ❌${RESET}"
  fi
  short_detail="$(echo "$detail" | cut -c1-58)"
  printf "| %-52s | %-15b | %-7s | %-58s |\n" "$test" "$mark" "$stage" "$short_detail"
done < "$RESULTS"

printf "+------------------------------------------------------+--------+---------+------------------------------------------------------------+\n"
echo -e "${GREEN}PASS: ${PASS_COUNT}${RESET}  ${RED}FAIL: ${FAIL_COUNT}${RESET}"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}PASS sdmc_thin_frontend_aead_matrix_table${RESET}"
  exit 0
else
  echo -e "${RED}FAIL sdmc_thin_frontend_aead_matrix_table${RESET}"
  echo -e "${YELLOW}Full logs: ${LOGDIR}${RESET}"
  echo -e "${YELLOW}Results TSV: ${RESULTS}${RESET}"
  exit 1
fi
