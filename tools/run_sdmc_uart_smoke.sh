#!/usr/bin/env bash
set -u -o pipefail

mkdir -p reports
RESULTS="reports/sdmc_uart_smoke_results.tsv"
: > "$RESULTS"

echo "=== sdmc_uart_aead_only_compile_smoke ==="

if iverilog -g2012 -I src -I src/sdmc \
  -o /tmp/sdmc_uart_aead_only_compile_smoke.vvp \
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
  src/sdmc/sdmc_aead128_core.v \
  src/sdmc/sdmc_crypto_top.v \
  src/sdmc/sdmc_uart_token_bridge.v \
  src/project_sdmc_uart_top.v; then
  printf "sdmc_uart_aead_only_compile_smoke\tPASS\tAEAD-only UART top compiled\n" >> "$RESULTS"
  echo "PASS sdmc_uart_smoke: AEAD-only UART top compiled"
  exit 0
else
  printf "sdmc_uart_aead_only_compile_smoke\tFAIL\tCompile failed\n" >> "$RESULTS"
  echo "FAIL sdmc_uart_smoke: AEAD-only UART top compile failed"
  exit 1
fi
