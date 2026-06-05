#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

TESTDIR="test/cocotb_anubis_xof_cxof"
REPORTDIR="reports/anubis_cocotb_xof_cxof_core"
LOGDIR="$REPORTDIR/logs"
RESULTS="$REPORTDIR/results.tsv"

mkdir -p "$LOGDIR"
: > "$RESULTS"

mapfile -t vectors < <(
  {
    find test/sdmc_top_uart_xof_cxof_kat_massive -type f -name "tb_xof_*_cs0_out64.v" | sort | grep -E "_m(0|1|2|3|8|16|32)_cs0_out64.v$" | head -8
    find test/sdmc_top_uart_xof_cxof_kat_massive -type f -name "tb_cxof_*_out64.v" | sort | grep -E "_m(0|1|8|16|32)_cs(0|1|8|16|32)_out64.v$" | head -12
  } | sort -u
)

pass=0
fail=0

echo -e "${BOLD}=== ANUBIS-SDMC COCOTB XOF/CXOF TOP-UART CORE TABLE ===${NC}"
printf "+--------------------------------------+------------+------------+----------------------------------------------+\n"
printf "| %-36s | %-10s | %-10s | %-44s |\n" "VECTOR" "STATUS" "CYCLES" "DETAIL"
printf "+--------------------------------------+------------+------------+----------------------------------------------+\n"

for tb in "${vectors[@]}"; do
    name="$(basename "$tb" .v)"
    log="$LOGDIR/${name}.log"

    (
      cd "$TESTDIR"
      make clean >/dev/null 2>&1
      XOF_TB="$tb" make
    ) > "$log" 2>&1

    if grep -Eq "PASS (XOF|CXOF)_TOP_UART" "$log" && grep -q "TESTS=1 PASS=1 FAIL=0" "$log"; then
        metric="$(grep -m1 "METRIC mode=" "$log" | sed 's/.*METRIC/METRIC/')"
        cycles="$(echo "$metric" | sed -n 's/.*cycles=\([0-9][0-9]*\).*/\1/p')"
        printf "| %-36s | ${GREEN}%-10s${NC} | %-10s | %-44s |\n" "$name" "PASS [OK]" "$cycles" "top UART XOF/CXOF KAT"
        echo -e "$name\tPASS\t$metric" >> "$RESULTS"
        pass=$((pass + 1))
    else
        detail="$(grep -m1 -Ei "AssertionError|FAIL|mismatch|Timeout|Error" "$log" | cut -c1-44)"
        [ -n "$detail" ] || detail="see log"
        printf "| %-36s | ${RED}%-10s${NC} | %-10s | %-44s |\n" "$name" "FAIL [X]" "-" "$detail"
        echo -e "$name\tFAIL\t$detail" >> "$RESULTS"
        fail=$((fail + 1))
    fi
done

printf "+--------------------------------------+------------+------------+----------------------------------------------+\n"
echo
echo -e "${GREEN}PASS=$pass${NC} ${RED}FAIL=$fail${NC}"
echo "Results: $RESULTS"
echo "Logs:    $LOGDIR"

if [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]; then
    echo
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}       \\(^_^)/  XOF/CXOF TOP-UART COCOTB PASSED  \\(^_^)/${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    exit 0
else
    echo
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD}             (T_T)  XOF/CXOF COCOTB FAILURES  (T_T)${NC}"
    echo -e "${RED}${BOLD}============================================================${NC}"
    exit 1
fi
