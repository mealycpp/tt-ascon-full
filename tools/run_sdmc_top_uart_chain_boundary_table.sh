#!/usr/bin/env bash
set -u

GREEN="\033[0;32m"
RED="\033[0;31m"
RESET="\033[0m"

TESTDIR="test/sdmc_top_uart_chain_boundary"
REPORTDIR="reports/sdmc_top_uart_chain_boundary"
mkdir -p "$REPORTDIR"

PASS_COUNT=0
FAIL_COUNT=0

printf "\n=== TOP UART DERIVED XOF/CXOF CHAIN BOUNDARY TABLE ===\n"
printf "+---------------------------------------------+----------+--------------------------------+\n"
printf "| Test                                        | Status   | Detail                         |\n"
printf "+---------------------------------------------+----------+--------------------------------+\n"

while read -r name; do
    [ -z "$name" ] && continue

    tb="$TESTDIR/tb_${name}.v"
    vvp="/tmp/${name}.vvp"
    clog="$REPORTDIR/${name}.compile.log"
    log="$REPORTDIR/${name}.run.log"

    rm -f "$vvp" "$clog" "$log"

    if ! iverilog -g2012 -I src -I src/sdmc \
        -o "$vvp" \
        src/ascon_round.v \
        src/ascon_permutation.v \
        src/uart_rx.v \
        src/uart_tx.v \
        src/sdmc/sdmc_aead_uart_frontend.v \
        src/sdmc/sdmc_aead128_core.v \
        src/sdmc/sdmc_hash256_core.v \
        src/sdmc/sdmc_xof_family_core.v \
        src/sdmc/sdmc_xof_chain_family_core.v \
        src/sdmc/sdmc_ascon_perm_unit64.v \
        src/sdmc/sdmc_crypto_helpers.v \
        src/project_sdmc_uart_top.v \
        "$tb" > "$clog" 2>&1; then

        detail="$(head -n 1 "$clog" | cut -c1-30)"
        printf "| %-43s | ${RED}%-8s${RESET} | %-30s |\n" "$name" "COMPILE" "$detail"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    timeout 600s stdbuf -oL -eL vvp "$vvp" > "$log" 2>&1
    rc=$?

    if [ "$rc" -ne 0 ]; then
        detail="timeout/runtime rc=$rc"
        printf "| %-43s | ${RED}%-8s${RESET} | %-30s |\n" "$name" "FAIL" "$detail"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    if grep -q "PASS CHAIN_TOP" "$log"; then
        detail="$(grep "PASS CHAIN_TOP" "$log" | tail -n 1 | sed 's/^PASS CHAIN_TOP //' | cut -c1-30)"
        printf "| %-43s | ${GREEN}%-8s${RESET} | %-30s |\n" "$name" "PASS" "$detail"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        detail="$(grep -E "FAIL CHAIN_TOP|FIRST_MISMATCH|TIMEOUT" "$log" | head -n 1 | cut -c1-30)"
        [ -z "$detail" ] && detail="no PASS marker"
        printf "| %-43s | ${RED}%-8s${RESET} | %-30s |\n" "$name" "FAIL" "$detail"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < "$TESTDIR/manifest.txt"

printf "+---------------------------------------------+----------+--------------------------------+\n"
printf "PASS: ${GREEN}%d${RESET}  FAIL: " "$PASS_COUNT"
if [ "$FAIL_COUNT" -eq 0 ]; then
    printf "${GREEN}%d${RESET}\n" "$FAIL_COUNT"
    printf "${GREEN}PASS sdmc_top_uart_chain_boundary_table${RESET}\n"
else
    printf "${RED}%d${RESET}\n" "$FAIL_COUNT"
    printf "${RED}FAIL sdmc_top_uart_chain_boundary_table${RESET}\n"
fi

exit "$FAIL_COUNT"
