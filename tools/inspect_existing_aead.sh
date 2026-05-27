#!/usr/bin/env bash
set -euo pipefail

echo "=== AEAD vectors from dispatcher ==="
sed -n '70,170p' test/dispatcher/test_dispatcher.py

echo
echo "=== AEAD RTL files ==="
ls -l src/*aead*.v src/sdmc/*aead*.v 2>/dev/null || true

echo
echo "=== AEAD constants / states / IV / tag / key / nonce ==="
grep -RniE "AEAD|aead|IV|KEY|NONCE|TAG|AD|PT|CT|encrypt|decrypt|localparam|64'h|S_|PATCH|mask|pad" \
  src/aead_controller.v \
  src/aead_patch_controller.v \
  src/*aead*.v \
  2>/dev/null | head -320 || true

echo
echo "=== AEAD module headers ==="
grep -RniE "^module .*aead" src/*.v src/sdmc/*.v 2>/dev/null || true
