#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
BOLD="\033[1m"
NC="\033[0m"

BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

REPORTDIR="reports/anubis_gatelevel_smoke"
LOGDIR="$REPORTDIR/logs"
WORKDIR="$REPORTDIR/work"
RESULTS="$REPORTDIR/results.tsv"

mkdir -p "$LOGDIR" "$WORKDIR"
: > "$RESULTS"

NETLIST="$(find ci_artifacts/sdmc-single-uart-gds-pass/GDS_logs/runs/wokwi ci_artifacts/GDS_logs/runs/wokwi reports/final_gds_artifacts/input/GDS_logs/runs/wokwi 2>/dev/null \
  -type f -name "tt_um_mealycpp_ascon_sdmc_uart.nl.v" \
  | sort -V | tail -1)"

CELL_LIB="$(find ${PDK_ROOT:-/nonexistent} /opt ~/.volare ~/.local 2>/dev/null \
  -type f \
  \( -name "*gf180mcu*sc*mcu*sim*.v" -o -name "gf180mcu_fd_sc_mcu7t5v0.v" -o -name "cells_sim.v" \) \
  | sort | head -1)"

if [ -z "${NETLIST:-}" ] || [ ! -f "$NETLIST" ]; then
    echo "FAIL: gate-level netlist not found"
    exit 1
fi

if [ -z "${CELL_LIB:-}" ] || [ ! -f "$CELL_LIB" ]; then
    echo "FAIL: GF180 cell simulation library not found"
    echo "Set PDK_ROOT correctly or locate gf180mcu_fd_sc_mcu7t5v0.v / cells_sim.v."
    exit 1
fi

echo -e "${BOLD}Using netlist:${NC} $NETLIST"
echo -e "${BOLD}Using cell lib:${NC} $CELL_LIB"
echo

vectors=(
"hash_m0:test/sdmc_top_uart_hash_kat_massive/tb_hash_c0001_m0.v:tb_hash_c0001_m0:PASS HASH_KAT"
"hash_m1:test/sdmc_top_uart_hash_kat_massive/tb_hash_c0002_m1.v:tb_hash_c0002_m1:PASS HASH_KAT"
"xof_empty:test/sdmc_top_uart_xof_cxof_kat_massive/tb_xof_c0001_m0_cs0_out64.v:tb_xof_c0001_m0_cs0_out64:PASS XOF_TOP"
"cxof_empty:test/sdmc_top_uart_xof_cxof_kat_massive/tb_cxof_c0001_m0_cs0_out64.v:tb_cxof_c0001_m0_cs0_out64:PASS CXOF_TOP"
"xof_chain_c1:test/sdmc_top_uart_chain_boundary/sdmc_xof_chain_empty_c1_out32/tb_sdmc_xof_chain_empty_c1_out32.v:tb_sdmc_xof_chain_empty_c1_out32:PASS CHAIN_TOP"
"xof_chain_c16:test/sdmc_top_uart_chain_boundary/sdmc_xof_chain_empty_c16_out32/tb_sdmc_xof_chain_empty_c16_out32.v:tb_sdmc_xof_chain_empty_c16_out32:PASS CHAIN_TOP"
"cxof_chain_c16:test/sdmc_top_uart_chain_boundary/sdmc_cxof_chain_z8_empty_c16_out32/tb_sdmc_cxof_chain_z8_empty_c16_out32.v:tb_sdmc_cxof_chain_z8_empty_c16_out32:PASS CHAIN_TOP"
"aead_enc:test/sdmc_top_uart_aead_matrix/sdmc_top_uart_kat_c001_ad0_pt0_enc/tb_sdmc_top_uart_kat_c001_ad0_pt0_enc.v:tb_sdmc_top_uart_kat_c001_ad0_pt0_enc:PASS sdmc_top_uart_kat_c001_ad0_pt0_enc"
"aead_dec:test/sdmc_top_uart_aead_matrix/sdmc_top_uart_kat_c001_ad0_pt0_dec/tb_sdmc_top_uart_kat_c001_ad0_pt0_dec.v:tb_sdmc_top_uart_kat_c001_ad0_pt0_dec:PASS sdmc_top_uart_kat_c001_ad0_pt0_dec"
"aead_badtag:test/sdmc_top_uart_aead_matrix/sdmc_top_uart_kat_c001_ad0_pt0_badtag/tb_sdmc_top_uart_kat_c001_ad0_pt0_badtag.v:tb_sdmc_top_uart_kat_c001_ad0_pt0_badtag:PASS sdmc_top_uart_kat_c001_ad0_pt0_badtag"
)

pass=0
fail=0

echo -e "${BOLD}=== ANUBIS-SDMC GATE-LEVEL TOP-UART SMOKE ===${NC}"
printf "+----------------+------------+----------+------------------------------------------+\n"
printf "| %-14s | %-10s | %-8s | %-40s |\n" "VECTOR" "STATUS" "STAGE" "DETAIL"
printf "+----------------+------------+----------+------------------------------------------+\n"

for item in "${vectors[@]}"; do
    IFS=":" read -r name tb top pass_marker <<< "$item"

    vvp="$WORKDIR/${name}.vvp"
    clog="$LOGDIR/${name}.compile.log"
    rlog="$LOGDIR/${name}.run.log"

    if [ ! -f "$tb" ]; then
        printf "| %-14s | ${RED}%-10s${NC} | %-8s | %-40s |\n" "$name" "FAIL [X]" "MISSING" "missing tb"
        echo -e "$name\tFAIL\tMISSING\tmissing tb" >> "$RESULTS"
        fail=$((fail + 1))
        continue
    fi

    iverilog -g2012 \
      -I src -I src/sdmc -I "$BASE" \
      -s "$top" \
      -o "$vvp" \
      "$CELL_LIB" \
      "$NETLIST" \
      "$tb" > "$clog" 2>&1

    if [ "$?" -ne 0 ]; then
        detail="$(grep -m1 -Ei "error|unknown module|not a port|syntax|failed|No such" "$clog" | cut -c1-40)"
        [ -n "$detail" ] || detail="compile failed"
        printf "| %-14s | ${RED}%-10s${NC} | %-8s | %-40s |\n" "$name" "FAIL [X]" "COMPILE" "$detail"
        echo -e "$name\tFAIL\tCOMPILE\t$detail" >> "$RESULTS"
        fail=$((fail + 1))
        continue
    fi

    timeout 600s stdbuf -oL -eL vvp "$vvp" > "$rlog" 2>&1
    rc="$?"

    if grep -q "$pass_marker" "$rlog"; then
        detail="$(grep -m1 "$pass_marker" "$rlog" | cut -c1-40)"
        printf "| %-14s | ${GREEN}%-10s${NC} | %-8s | %-40s |\n" "$name" "PASS [OK]" "SIM" "$detail"
        echo -e "$name\tPASS\tSIM\t$detail" >> "$RESULTS"
        pass=$((pass + 1))
    else
        if [ "$rc" -eq 124 ]; then
            detail="timeout"
        else
            detail="$(grep -m1 -Ei "FAIL|MISMATCH|TIMEOUT|error|x" "$rlog" | cut -c1-40)"
            [ -n "$detail" ] || detail="no PASS marker"
        fi
        printf "| %-14s | ${RED}%-10s${NC} | %-8s | %-40s |\n" "$name" "FAIL [X]" "SIM" "$detail"
        echo -e "$name\tFAIL\tSIM\t$detail" >> "$RESULTS"
        fail=$((fail + 1))
    fi
done

printf "+----------------+------------+----------+------------------------------------------+\n"
echo
echo -e "${GREEN}PASS=$pass${NC} ${RED}FAIL=$fail${NC}"
echo "Results: $RESULTS"
echo "Logs:    $LOGDIR"
echo "Work:    $WORKDIR"

if [ "$fail" -eq 0 ] && [ "$pass" -gt 0 ]; then
    echo
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}          \\(^_^)/  GATE-LEVEL SMOKE PASSED  \\(^_^)/${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    exit 0
else
    echo
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD}              (T_T)  GATE-LEVEL SMOKE FAIL  (T_T)${NC}"
    echo -e "${RED}${BOLD}============================================================${NC}"
    exit 1
fi
