#!/usr/bin/env bash
set -euo pipefail

echo "=== sdmc_uart_top_syntax ==="

iverilog -g2012 -I src -I src/sdmc \
  -o /tmp/project_sdmc_uart_top_syntax.vvp \
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
    src/sdmc/sdmc_xof_family_core.v \
  src/sdmc/sdmc_xof_chain_family_core.v \
    src/sdmc/sdmc_crypto_top_hx.v \
  src/sdmc/sdmc_uart_token_bridge.v \
  src/project_sdmc_uart_top.v

echo "PASS sdmc_uart_top_syntax"
