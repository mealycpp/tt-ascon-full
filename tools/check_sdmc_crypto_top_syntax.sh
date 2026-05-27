#!/usr/bin/env bash
set -euo pipefail

echo "=== sdmc_crypto_top_syntax ==="

iverilog -g2012 -I src/sdmc \
  -o /tmp/sdmc_crypto_top_syntax.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
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
  src/sdmc/sdmc_aead128_core.v \
  src/sdmc/sdmc_crypto_top.v

echo "PASS sdmc_crypto_top_syntax"
