#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

python3 tools/sdmc_generate_chain_rtl_tests.py || exit 1

RESULTS_FILE="reports/sdmc_chain_vector_regression_results.tsv"
mkdir -p reports
: > "$RESULTS_FILE"

PASS_COUNT=0
FAIL_COUNT=0

while read -r name; do
  [ -n "$name" ] || continue

  echo "=== $name ==="

  vvp_file="test/sdmc_chain_vector_matrix/${name}/tb_${name}.vvp"
  tb_file="test/sdmc_chain_vector_matrix/${name}/tb_${name}.v"

  if iverilog -g2012 -I src/sdmc \
    -o "$vvp_file" \
    src/ascon_round.v \
    src/ascon_permutation.v \
    src/sdmc/sdmc_ascon_perm_unit64.v \
    src/sdmc/sdmc_xof_family_core.v \
    src/sdmc/sdmc_xof_chain_family_core.v \
    "$tb_file"; then

    if vvp "$vvp_file"; then
      printf "%s\tPASS\tSimulation passed\n" "$name" >> "$RESULTS_FILE"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      printf "%s\tFAIL\tSimulation failed\n" "$name" >> "$RESULTS_FILE"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    printf "%s\tFAIL\tCompile failed\n" "$name" >> "$RESULTS_FILE"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
done < test/sdmc_chain_vector_matrix/manifest.txt

echo
echo "=== SDMC CHAIN VECTOR REGRESSION SUMMARY ==="
printf "+---------------------------------------------------------------+--------+-------------------+\n"
printf "| Test                                                          | Status | Detail            |\n"
printf "+---------------------------------------------------------------+--------+-------------------+\n"

while IFS=$'\t' read -r test status detail; do
  short="$test"
  if [ ${#short} -gt 61 ]; then
    short="${short:0:58}..."
  fi

  if [ "$status" = "PASS" ]; then
    color="$GREEN"
    mark="PASS ✅"
  else
    color="$RED"
    mark="FAIL ❌"
  fi

  printf "| %-61s | ${color}%-6s${RESET} | %-17s |\n" "$short" "$mark" "$detail"
done < "$RESULTS_FILE"

printf "+---------------------------------------------------------------+--------+-------------------+\n"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}PASS sdmc_chain_vector_regression: ${PASS_COUNT} passed, 0 failed${RESET}"
  exit 0
else
  echo -e "${RED}FAIL sdmc_chain_vector_regression: ${PASS_COUNT} passed, ${FAIL_COUNT} failed${RESET}"
  exit 1
fi
