#!/usr/bin/env bash
set -euo pipefail

python3 tools/sdmc_generate_thin_frontend_aead_matrix.py

while read -r name; do
  [ -n "$name" ] || continue
  echo "=== $name ==="
  iverilog -g2012 -I src -I src/sdmc \
    -o "test/sdmc_thin_frontend_aead_matrix/${name}/tb_${name}.vvp" \
    src/ascon_round.v \
    src/ascon_permutation.v \
    src/sdmc/sdmc_aead_uart_frontend.v \
    src/sdmc/sdmc_aead128_core.v \
    src/sdmc/sdmc_ascon_perm_unit64.v \
    src/sdmc/sdmc_crypto_helpers.v \
    "test/sdmc_thin_frontend_aead_matrix/${name}/tb_${name}.v"
  vvp "test/sdmc_thin_frontend_aead_matrix/${name}/tb_${name}.vvp"
done < test/sdmc_thin_frontend_aead_matrix/manifest.txt

echo "PASS sdmc_thin_frontend_aead_matrix"
