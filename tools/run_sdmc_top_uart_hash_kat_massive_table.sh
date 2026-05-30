#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

OUTDIR="test/sdmc_top_uart_hash_kat_massive"
RPTDIR="reports/sdmc_top_uart_hash_kat_massive"
mkdir -p "$RPTDIR"

GREEN=$'\033[0;32m'
RED=$'\033[0;31m'
YELLOW=$'\033[1;33m'
CYAN=$'\033[0;36m'
BOLD=$'\033[1m'
NC=$'\033[0m'

python3 tools/sdmc_generate_top_uart_hash_kat_massive.py

if [ ! -s "$OUTDIR/manifest.txt" ]; then
    echo "FAIL: missing or empty manifest: $OUTDIR/manifest.txt"
    exit 1
fi

PASS=0
FAIL=0

printf "\n${BOLD}${CYAN}=== TOP UART OFFICIAL HASH256 KAT MASSIVE TABLE ===${NC}\n"
printf "+----------------------+----------+-------------------------------+\n"
printf "| Test                 | Status   | Detail                        |\n"
printf "+----------------------+----------+-------------------------------+\n"

while read -r name; do
    [ -z "$name" ] && continue

    tb="$OUTDIR/tb_${name}.v"
    vvp="/tmp/${name}.vvp"
    clog="$RPTDIR/${name}.compile.log"
    rlog="$RPTDIR/${name}.run.log"

    if ! iverilog -g2012 -I src -I src/sdmc \
        -o "$vvp" \
        src/ascon_round.v \
        src/ascon_permutation.v \
        src/uart_rx.v \
        src/uart_tx.v \
        src/sdmc/sdmc_aead_uart_frontend.v \
        src/sdmc/sdmc_aead128_core.v \
        src/sdmc/sdmc_xof_family_core.v \
        src/sdmc/sdmc_xof_chain_family_core.v \
          src/sdmc/sdmc_ascon_perm_unit64.v \
        src/sdmc/sdmc_crypto_helpers.v \
        src/project_sdmc_uart_top.v \
        "$tb" >"$clog" 2>&1; then
        printf "| %-20s | ${RED}%-8s${NC} | %-29s |\n" "$name" "FAIL" "COMPILE - see log"
        FAIL=$((FAIL+1))
        continue
    fi

    if timeout 1200s stdbuf -oL -eL vvp "$vvp" >"$rlog" 2>&1; then
        if grep -q "PASS HASH_KAT" "$rlog"; then
            printf "| %-20s | ${GREEN}%-8s${NC} | %-29s |\n" "$name" "PASS" "official HASH KAT match"
            PASS=$((PASS+1))
        else
            first="$(grep -E "FAIL HASH_FIRST_MISMATCH" "$rlog" | head -n 1 | cut -c1-29)"
            got="$(grep -E "^GOT_MD" "$rlog" | head -n 1 | sed 's/.*got=//' | cut -c1-16)"
            exp="$(grep -E "^EXP_MD" "$rlog" | head -n 1 | sed 's/.*exp=//' | cut -c1-16)"
            [ -z "$first" ] && first="no PASS marker"
            printf "| %-20s | ${RED}%-8s${NC} | got=%-16s exp=%-16s |\n" "$name" "FAIL" "$got" "$exp"
            printf "  -> %s\n" "$first"
            FAIL=$((FAIL+1))
        fi
    else
        detail="$(tail -n 1 "$rlog" | cut -c1-29)"
        [ -z "$detail" ] && detail="timeout/run failure"
        printf "| %-20s | ${YELLOW}%-8s${NC} | %-29s |\n" "$name" "TIMEOUT" "$detail"
        FAIL=$((FAIL+1))
    fi
done < "$OUTDIR/manifest.txt"

printf "+----------------------+----------+-------------------------------+\n"

if [ "$PASS" -gt 0 ] && [ "$FAIL" -eq 0 ]; then
    printf "${GREEN}${BOLD}PASS: %d  FAIL: %d${NC}\n" "$PASS" "$FAIL"
    printf "${GREEN}${BOLD}PASS sdmc_top_uart_hash_kat_massive_table${NC}\n"
    exit 0
else
    printf "${RED}${BOLD}PASS: %d  FAIL: %d${NC}\n" "$PASS" "$FAIL"
    printf "${RED}${BOLD}FAIL sdmc_top_uart_hash_kat_massive_table${NC}\n"
    exit 1
fi
