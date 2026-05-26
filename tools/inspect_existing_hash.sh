#!/usr/bin/env bash
set -euo pipefail

echo "=== Existing HASH-related RTL files ==="
ls -l src/*hash*.v src/*xof*.v 2>/dev/null || true

echo
echo "=== HASH constants / IV / rate / states ==="
grep -RniE "HASH|HASHA|XOF|CXOF|IV|RATE|ROUND|p12|p8|64'h|localparam|parameter" \
  src/hash_controller.v \
  src/hash_patch_controller.v \
  src/xof_controller.v \
  src/xof_patch_controller.v \
  src/cxof_controller.v \
  src/cxof_patch_controller.v \
  2>/dev/null | head -260 || true

echo
echo "=== HASH controller module headers ==="
grep -RniE "^module (hash|hash_patch|xof|xof_patch|cxof|cxof_patch)" src/*.v 2>/dev/null || true

echo
echo "=== Existing test vectors in tests ==="
grep -RniE "hash_empty|hash_abc|xof_empty|xof_abc|cxof|exp|expected|digest|hash" test src 2>/dev/null | head -260 || true

echo
echo "=== Existing dispatcher HASH/XOF/CXOF vectors around code ==="
grep -RniE "hash_empty|hash_abc|xof_empty_32|xof_abc_32|cxof_empty_abc|cxof_a_abc" test/dispatcher 2>/dev/null || true
