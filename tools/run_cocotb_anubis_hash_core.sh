#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[1;33m"
BOLD="\033[1m"
NC="\033[0m"

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

TESTDIR="test/cocotb_anubis_uart"
REPORTDIR="reports/anubis_cocotb_hash_core"
LOGDIR="$REPORTDIR/logs"
RESULTS="$REPORTDIR/results.tsv"

mkdir -p "$LOGDIR"
: > "$RESULTS"

vectors=(
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0001_m0.v
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0002_m1.v
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0003_m2.v
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0004_m3.v
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0008_m7.v
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0009_m8.v
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0017_m16.v
test/sdmc_top_uart_hash_kat_massive/tb_hash_c0033_m32.v
)

pass=0
fail=0

echo -e "${BOLD}=== ANUBIS-SDMC COCOTB HASH256 TOP-UART CORE TABLE ===${NC}"
printf "+----------------------+------------+------------+----------------------------------------------+\n"
printf "| %-20s | %-10s | %-10s | %-44s |\n" "VECTOR" "STATUS" "CYCLES" "DETAIL"
printf "+----------------------+------------+------------+----------------------------------------------+\n"

for tb in "${vectors[@]}"; do
    name="$(basename "$tb" .v)"
    log="$LOGDIR/${name}.log"

    (
      cd "$TESTDIR"
      make clean >/dev/null 2>&1
      HASH_TB="$tb" make
    ) > "$log" 2>&1

    if grep -q "PASS HASH256_TOP_UART" "$log" && grep -q "TESTS=1 PASS=1 FAIL=0" "$log"; then
        metric="$(grep -m1 "METRIC mode=HASH256" "$log" | sed 's/.*METRIC/METRIC/')"
        cycles="$(echo "$metric" | sed -n 's/.*cycles=\([0-9][0-9]*\).*/\1/p')"
        printf "| %-20s | ${GREEN}%-10s${NC} | %-10s | %-44s |\n" "$name" "PASS [OK]" "$cycles" "top UART HASH256 KAT"
        echo -e "$name\tPASS\t$metric" >> "$RESULTS"
        pass=$((pass + 1))
    else
        detail="$(grep -m1 -Ei "AssertionError|FAIL|mismatch|Timeout|Error" "$log" | cut -c1-44)"
        [ -n "$detail" ] || detail="see log"
        printf "| %-20s | ${RED}%-10s${NC} | %-10s | %-44s |\n" "$name" "FAIL [X]" "-" "$detail"
        echo -e "$name\tFAIL\t$detail" >> "$RESULTS"
        fail=$((fail + 1))
    fi
done

printf "+----------------------+------------+------------+----------------------------------------------+\n"
echo
echo -e "${GREEN}PASS=$pass${NC} ${RED}FAIL=$fail${NC}"
echo "Results: $RESULTS"
echo "Logs:    $LOGDIR"

if [ "$fail" -eq 0 ]; then
    echo
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}        \\(^_^)/  HASH256 TOP-UART COCOTB PASSED  \\(^_^)/${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    exit 0
else
    echo
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD}              (T_T)  HASH COCOTB FAILURES  (T_T)${NC}"
    echo -e "${RED}${BOLD}============================================================${NC}"
    exit 1
fi
