#!/usr/bin/env bash
set -euo pipefail

python3 tools/sdmc_generate_aead_official_matrix.py

while read -r name; do
  [ -n "$name" ] || continue
  echo "=== $name ==="
  iverilog -g2012 -I src/sdmc \
    -o "test/sdmc_aead128_official_matrix/${name}/tb_${name}.vvp" \
    src/ascon_round.v \
    src/ascon_permutation.v \
    src/sdmc/sdmc_ascon_perm_unit64.v \
    src/sdmc/sdmc_aead128_core.v \
    "test/sdmc_aead128_official_matrix/${name}/tb_${name}.v"
  vvp "test/sdmc_aead128_official_matrix/${name}/tb_${name}.vvp"
done < test/sdmc_aead128_official_matrix/manifest.txt

echo "PASS sdmc_aead_official_matrix"
