#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

ASCON_DIR="external/ascon-c"
REFDIR="$ASCON_DIR/crypto_aead/asconaead128/ref"
HDRDIR="$ASCON_DIR/tests"

if [ ! -d "$ASCON_DIR/.git" ]; then
    mkdir -p external
    git clone https://github.com/ascon/ascon-c.git "$ASCON_DIR"
fi

if [ ! -f "$REFDIR/aead.c" ]; then
    echo "ERROR: missing $REFDIR/aead.c"
    exit 1
fi

if [ ! -f "$HDRDIR/crypto_aead.h" ]; then
    echo "ERROR: missing $HDRDIR/crypto_aead.h"
    exit 1
fi

gcc -std=c99 -O2 -Wall -Wextra \
  -I "$REFDIR" \
  -I "$HDRDIR" \
  -o tools/ascon_aead128_ref_cli \
  tools/ascon_aead128_ref_cli.c \
  "$REFDIR/aead.c"

echo "Built tools/ascon_aead128_ref_cli"

got="$(tools/ascon_aead128_ref_cli enc \
  000102030405060708090a0b0c0d0e0f \
  101112131415161718191a1b1c1d1e1f \
  "" \
  "")"

exp="4f9c278211bec9316bf68f46ee8b2ec6"

if [ "$got" != "$exp" ]; then
    echo "ERROR: ASCON-C reference smoke test failed"
    echo "got=$got"
    echo "exp=$exp"
    exit 1
fi

echo "PASS ASCON-C reference smoke test"
