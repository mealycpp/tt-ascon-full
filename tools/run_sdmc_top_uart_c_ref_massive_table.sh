#!/usr/bin/env bash
set -u
set -o pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

./tools/setup_ascon_c_ref.sh

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

python3 tools/sdmc_generate_top_uart_c_ref_crazy.py
python3 tools/patch_c_ref_expected_into_tb.py

MANIFEST="test/sdmc_top_uart_c_ref_crazy/manifest.txt"
LOGDIR="reports/sdmc_top_uart_c_ref_massive"
mkdir -p "$LOGDIR"

PASS_COUNT=0
FAIL_COUNT=0

printf "\n=== TOP UART OFFICIAL C-REFERENCE MASSIVE TABLE ===\n"
printf "+----------------------+--------+----------+----------+-------------------------------+\n"
printf "| Test                 | Status | C-Ref    | Roundtrip| Detail                        |\n"
printf "+----------------------+--------+----------+----------+-------------------------------+\n"

while IFS= read -r name; do
    [ -z "$name" ] && continue

    tb="test/sdmc_top_uart_c_ref_crazy/tb_${name}.v"
    vvp="/tmp/tb_${name}.vvp"
    log="${LOGDIR}/${name}.log"
    clog="${LOGDIR}/${name}.compile.log"

    rm -f "$vvp" "$log" "$clog"

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
    src/sdmc/sdmc_hash256_core.v \
        src/project_sdmc_uart_top.v \
        "$tb" > "$clog" 2>&1; then

        printf "| %-20s | ${RED}FAIL${RESET}   | COMPILE  | -        | see %-25s |\n" "$name" "$clog"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    timeout 3600s stdbuf -oL -eL vvp "$vvp" > "$log" 2>&1
    rc=$?

    cref="FAIL"
    rt="FAIL"
    detail=""

    if grep -q "PASS C_REF_ENC" "$log"; then
        cref="PASS"
    fi

    if grep -q "PASS ${name}" "$log"; then
        rt="PASS"
    fi

    if [ "$cref" = "PASS" ] && [ "$rt" = "PASS" ] && ! grep -q "FAIL" "$log"; then
        printf "| %-20s | ${GREEN}PASS${RESET}   | ${GREEN}PASS${RESET}     | ${GREEN}PASS${RESET}     | official C match + decrypt OK |\n" "$name"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        detail="$(grep -m 1 -E "FAIL|mismatch|timeout|error" "$log" || true)"
        [ -z "$detail" ] && detail="rc=${rc}; see log"
        printf "| %-20s | ${RED}FAIL${RESET}   | %-8s | %-8s | %-29.29s |\n" "$name" "$cref" "$rt" "$detail"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi

done < "$MANIFEST"

printf "+----------------------+--------+----------+----------+-------------------------------+\n"
printf "PASS: ${GREEN}%d${RESET}  FAIL: " "$PASS_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
    printf "${GREEN}%d${RESET}\n" "$FAIL_COUNT"
else
    printf "${RED}%d${RESET}\n" "$FAIL_COUNT"
fi

if [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}PASS sdmc_top_uart_c_ref_massive_table${RESET}"
    exit 0
else
    echo -e "${RED}FAIL sdmc_top_uart_c_ref_massive_table${RESET}"
    exit 1
fi
