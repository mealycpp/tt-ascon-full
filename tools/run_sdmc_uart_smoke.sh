#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[32m"
RED="\033[31m"
RESET="\033[0m"

mkdir -p reports
RESULTS="reports/sdmc_uart_smoke_results.tsv"
: > "$RESULTS"

PASS_COUNT=0
FAIL_COUNT=0

run_test() {
  local name="$1"
  local tb="test/${name}/tb_${name}.v"
  local vvp="test/${name}/tb_${name}.vvp"

  echo "=== ${name} ==="

  if iverilog -g2012 -I src -I src/sdmc \
    -o "$vvp" \
    src/ascon_round.v \
    src/ascon_permutation.v \
    src/byte_fifo.v \
    src/uart_rx.v \
    src/uart_tx.v \
    src/protocol_parser.v \
    src/sdmc/sdmc_fifo.v \
    src/sdmc/sdmc_token_fifo.v \
    src/sdmc/sdmc_stream_ingress.v \
    src/sdmc/sdmc_stream_egress.v \
    src/sdmc/sdmc_stream_shell.v \
    src/sdmc/sdmc_config_regs.v \
    src/sdmc/sdmc_ascon_perm_unit64.v \
    src/sdmc/sdmc_hash256_core.v \
    src/sdmc/sdmc_xof_family_core.v \
    src/sdmc/sdmc_xof_chain_family_core.v \
        src/sdmc/sdmc_crypto_top_hx.v \
    src/sdmc/sdmc_uart_token_bridge.v \
    src/project_sdmc_uart_top.v \
    "$tb"; then

    if vvp "$vvp"; then
      printf "%s\tPASS\tUART-SDMC smoke passed\n" "$name" >> "$RESULTS"
      PASS_COUNT=$((PASS_COUNT + 1))
    else
      printf "%s\tFAIL\tSimulation failed\n" "$name" >> "$RESULTS"
      FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
  else
    printf "%s\tFAIL\tCompile failed\n" "$name" >> "$RESULTS"
    FAIL_COUNT=$((FAIL_COUNT + 1))
  fi
}

run_test "sdmc_uart_top_hash_empty_fast"

echo
echo "=== SDMC UART SMOKE SUMMARY ==="
printf "+--------------------------------------+--------+--------------------------+\n"
printf "| Test                                 | Status | Detail                   |\n"
printf "+--------------------------------------+--------+--------------------------+\n"

while IFS=$'\t' read -r test status detail; do
  if [ "$status" = "PASS" ]; then
    color="$GREEN"; mark="PASS ✅"
  else
    color="$RED"; mark="FAIL ❌"
  fi
  printf "| %-36s | ${color}%-6s${RESET} | %-24s |\n" "$test" "$mark" "$detail"
done < "$RESULTS"

printf "+--------------------------------------+--------+--------------------------+\n"

if [ "$FAIL_COUNT" -eq 0 ]; then
  echo -e "${GREEN}PASS sdmc_uart_smoke: ${PASS_COUNT} passed, 0 failed${RESET}"
  exit 0
else
  echo -e "${RED}FAIL sdmc_uart_smoke: ${PASS_COUNT} passed, ${FAIL_COUNT} failed${RESET}"
  exit 1
fi
