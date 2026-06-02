#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

GEN="tools/sdmc_generate_top_uart_chain_boundary.py"
TESTDIR="test/sdmc_top_uart_chain_boundary"
MANIFEST="$TESTDIR/manifest.txt"

REPORTDIR="reports/sdmc_top_uart_xof_cxof_chain_core"
LOGDIR="$REPORTDIR/logs"
WORKDIR="$REPORTDIR/work"
RESULTS="$REPORTDIR/results.tsv"
CORE_MANIFEST="$REPORTDIR/core_manifest.txt"

mkdir -p "$LOGDIR" "$WORKDIR"
: > "$RESULTS"

echo "=== SDMC TOP UART XOF/CXOF CHAIN CORE TABLE ==="
echo "Generating top-UART chain boundary tests..."
python3 "$GEN"

if [ ! -s "$MANIFEST" ]; then
    echo "FAIL: missing or empty manifest: $MANIFEST"
    exit 1
fi

cp "$MANIFEST" "$CORE_MANIFEST"

PASS_COUNT=0
FAIL_COUNT=0
RUN_COUNT=0

print_row() {
    local name="$1"
    local status="$2"
    local stage="$3"
    local detail="$4"

    if [ "$status" = "PASS" ]; then
        printf "| %-43s | ${GREEN}%-10s${NC} | %-7s | %-40s |\n" "$name" "PASS [OK]" "$stage" "$detail"
    else
        printf "| %-43s | ${RED}%-10s${NC} | %-7s | %-40s |\n" "$name" "FAIL [X]" "$stage" "$detail"
    fi
}

echo
printf "+---------------------------------------------+------------+---------+------------------------------------------+\n"
printf "| %-43s | %-10s | %-7s | %-40s |\n" "CHAIN_VECTOR" "STATUS" "STAGE" "DETAIL"
printf "+---------------------------------------------+------------+---------+------------------------------------------+\n"

while IFS= read -r name || [ -n "$name" ]; do
    [ -n "$name" ] || continue

    tb="$TESTDIR/$name/tb_${name}.v"
    case_work="$WORKDIR/$name"
    mkdir -p "$case_work"

    vvp="$case_work/${name}.vvp"
    clog="$LOGDIR/${name}.compile.log"
    rlog="$LOGDIR/${name}.run.log"

    if [ ! -f "$tb" ]; then
        detail="missing tb"
        print_row "$name" "FAIL" "MISSING" "$detail"
        printf "%s\tFAIL\tMISSING\t%s\n" "$name" "$detail" >> "$RESULTS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    iverilog -g2012 -I src -I src/sdmc \
      -s "tb_${name}" \
      -o "$vvp" \
      src/uart_rx.v \
      src/uart_tx.v \
      src/ascon_round.v \
      src/ascon_permutation.v \
      src/sdmc/sdmc_ascon_perm_unit64.v \
      src/sdmc/sdmc_aead_uart_frontend.v \
      src/sdmc/sdmc_aead128_core.v \
      src/sdmc/sdmc_xof_family_core.v \
      src/sdmc/sdmc_xof_chain_family_core.v \
      src/project_sdmc_uart_top.v \
      "$tb" > "$clog" 2>&1

    if [ "$?" -ne 0 ]; then
        detail="$(grep -m 1 -Ei "error|syntax|unknown module|not a port|No such|failed|duplicate|already" "$clog" | cut -c1-40)"
        [ -n "$detail" ] || detail="compile failed"
        print_row "$name" "FAIL" "COMPILE" "$detail"
        printf "%s\tFAIL\tCOMPILE\t%s\n" "$name" "$detail" >> "$RESULTS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        continue
    fi

    RUN_COUNT=$((RUN_COUNT + 1))

    timeout 240s stdbuf -oL -eL vvp "$vvp" > "$rlog" 2>&1
    rc="$?"

    if grep -q "PASS CHAIN_TOP" "$rlog"; then
        detail="$(grep -m 1 "PASS CHAIN_TOP" "$rlog" | cut -c1-40)"
        print_row "$name" "PASS" "SIM" "$detail"
        printf "%s\tPASS\tSIM\t%s\n" "$name" "$detail" >> "$RESULTS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        if [ "$rc" -eq 124 ]; then
            detail="timeout"
        else
            detail="$(grep -m 1 -Ei "FAIL|TIMEOUT|MISMATCH|error" "$rlog" | cut -c1-40)"
            [ -n "$detail" ] || detail="no PASS marker"
        fi
        print_row "$name" "FAIL" "SIM" "$detail"
        printf "%s\tFAIL\tSIM\t%s\n" "$name" "$detail" >> "$RESULTS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
done < "$MANIFEST"

printf "+---------------------------------------------+------------+---------+------------------------------------------+\n"
echo
echo "RUN:  $RUN_COUNT"
echo "PASS: $PASS_COUNT  FAIL: $FAIL_COUNT"

if [ "$FAIL_COUNT" -eq 0 ] && [ "$PASS_COUNT" -gt 0 ]; then
    echo -e "${GREEN}PASS sdmc_top_uart_xof_cxof_chain_core_table [OK]${NC}"
    echo
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}              \\(^_^)/   ALL UART CHAIN TESTS PASSED   \\(^_^)/${NC}"
    echo -e "${GREEN}${BOLD}                  XOF/CXOF CHAIN UART PATH IS HEALTHY${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo
    echo "Core manifest: $CORE_MANIFEST"
    echo "Results:       $RESULTS"
    echo "Logs:          $LOGDIR"
    echo "Work:          $WORKDIR"
    exit 0
else
    echo -e "${RED}FAIL sdmc_top_uart_xof_cxof_chain_core_table [X]${NC}"
    echo
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD}                    (T_T)   SOME FAILURES   (T_T)${NC}"
    echo -e "${RED}${BOLD}              STOP AND INSPECT TOP-UART CHAIN PATH${NC}"
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo
    echo "Core manifest: $CORE_MANIFEST"
    echo "Results:       $RESULTS"
    echo "Logs:          $LOGDIR"
    echo "Work:          $WORKDIR"
    exit 1
fi
