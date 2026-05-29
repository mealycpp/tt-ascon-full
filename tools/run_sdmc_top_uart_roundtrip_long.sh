#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

python3 tools/sdmc_generate_top_uart_roundtrip_long.py

MANIFEST="test/sdmc_top_uart_roundtrip_long/manifest.txt"
LOGDIR="reports/sdmc_top_uart_roundtrip_long"
mkdir -p "$LOGDIR"

PASS_COUNT=0
FAIL_COUNT=0

echo
echo "=== TOP UART LONG ROUNDTRIP SUMMARY ==="

while IFS= read -r name; do
    [ -z "$name" ] && continue

    tb="test/sdmc_top_uart_roundtrip_long/tb_${name}.v"
    vvp="/tmp/tb_long_${name}.vvp"
    log="${LOGDIR}/${name}.log"

    echo "=== ${name} ==="

    if [ ! -f "$tb" ]; then
        echo "FAIL ❌ ${name} [MISSING_TB] ${tb}"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    rm -f "$vvp" "$log"

    if ! iverilog -g2012 -I src -I src/sdmc \
        -o "$vvp" \
        src/ascon_round.v \
        src/ascon_permutation.v \
        src/uart_rx.v \
        src/uart_tx.v \
        src/sdmc/sdmc_aead_uart_frontend.v \
        src/sdmc/sdmc_aead128_core.v \
        src/sdmc/sdmc_ascon_perm_unit64.v \
        src/sdmc/sdmc_crypto_helpers.v \
        src/project_sdmc_uart_top.v \
        "$tb" > "${log}.compile" 2>&1; then
        echo "FAIL ❌ ${name} [COMPILE]"
        cat "${log}.compile"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    timeout 900s stdbuf -oL -eL vvp "$vvp" | tee "$log"
    run_rc=${PIPESTATUS[0]}

    if grep -q "PASS ${name}" "$log" && ! grep -q "FAIL" "$log"; then
        echo "PASS ✅ ${name}"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        echo "FAIL ❌ ${name} [SIM rc=${run_rc}]"
        tail -n 80 "$log"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < "$MANIFEST"

echo
echo "PASS: ${PASS_COUNT}  FAIL: ${FAIL_COUNT}"

if [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -gt 0 ]; then
    echo "PASS sdmc_top_uart_roundtrip_long"
    exit 0
else
    echo "FAIL sdmc_top_uart_roundtrip_long"
    exit 1
fi
