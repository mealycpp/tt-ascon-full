#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

TESTDIR="test/cocotb_anubis_aead"
REPORTDIR="reports/anubis_cocotb_aead_core"
LOGDIR="$REPORTDIR/logs"
RESULTS="$REPORTDIR/results.tsv"

mkdir -p "$LOGDIR"
: > "$RESULTS"

mapfile -t vectors < <(
  find test/sdmc_top_uart_aead_matrix -type f -name "tb_sdmc_top_uart_kat_*.v" | sort | head -45
)

pass=0
fail=0

echo -e "${BOLD}=== ANUBIS-SDMC COCOTB AEAD TOP-UART TABLE ===${NC}"
printf "+----------------------------------------------+------------+------------+----------------------------------------------+\n"
printf "| %-44s | %-10s | %-10s | %-44s |\n" "VECTOR" "STATUS" "CYCLES" "DETAIL"
printf "+----------------------------------------------+------------+------------+----------------------------------------------+\n"

for tb in "${vectors[@]}"; do
    name="$(basename "$tb" .v)"
    log="$LOGDIR/${name}.log"

    (
      cd "$TESTDIR"
      make clean >/dev/null 2>&1
      AEAD_TB="$tb" make
    ) > "$log" 2>&1

    if grep -q "PASS AEAD_TOP_UART" "$log" && grep -q "TESTS=1 PASS=1 FAIL=0" "$log"; then
        metric="$(grep -m1 "METRIC mode=" "$log" | sed 's/.*METRIC/METRIC/')"
        cycles="$(echo "$metric" | sed -n 's/.*cycles=\([0-9][0-9]*\).*/\1/p')"
        printf "| %-44s | ${GREEN}%-10s${NC} | %-10s | %-44s |\n" "$name" "PASS [OK]" "$cycles" "top UART AEAD KAT"
        echo -e "$name\tPASS\t$metric" >> "$RESULTS"
        pass=$((pass + 1))
    else
        detail="$(grep -m1 -Ei "AssertionError|FAIL|mismatch|Timeout|Error" "$log" | cut -c1-44)"
        [ -n "$detail" ] || detail="see log"
        printf "| %-44s | ${RED}%-10s${NC} | %-10s | %-44s |\n" "$name" "FAIL [X]" "-" "$detail"
        echo -e "$name\tFAIL\t$detail" >> "$RESULTS"
        fail=$((fail + 1))
    fi
done

printf "+----------------------------------------------+------------+------------+----------------------------------------------+\n"
echo
echo -e "${GREEN}PASS=$pass${NC} ${RED}FAIL=$fail${NC}"
echo "Results: $RESULTS"
echo "Logs:    $LOGDIR"

if [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]; then
    echo
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}          \\(^_^)/  AEAD TOP-UART COCOTB PASSED  \\(^_^)/${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    exit 0
else
    echo
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD}            (T_T)  AEAD COCOTB FAILURES  (T_T)${NC}"
    echo -e "${RED}${BOLD}============================================================${NC}"
    exit 1
fi
