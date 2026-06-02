#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[0;32m"
RED="\033[0;31m"
YELLOW="\033[0;33m"
CYAN="\033[0;36m"
BOLD="\033[1m"
NC="\033[0m"

REPORTDIR="reports/sdmc_uart_shipping_tables"
LOGDIR="$REPORTDIR/logs"
RESULTS="$REPORTDIR/results.tsv"

mkdir -p "$LOGDIR"
: > "$RESULTS"

PASS_COUNT=0
FAIL_COUNT=0
RUN_COUNT=0

strip_ansi() {
    sed -r 's/\x1B\[[0-9;]*[mK]//g'
}

run_table() {
    local label="$1"
    local script="$2"
    local log="$LOGDIR/$(basename "$script" .sh).log"

    RUN_COUNT=$((RUN_COUNT + 1))

    echo
    echo "============================================================"
    echo "RUNNING: $label"
    echo "CMD:     $script"
    echo "LOG:     $log"
    echo "============================================================"

    if [ ! -x "$script" ]; then
        echo -e "${RED}FAIL: missing executable script: $script${NC}"
        printf "%s\tFAIL\tMISSING\tmissing script\n" "$label" >> "$RESULTS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
        return
    fi

    : > "$log"

    echo -e "${CYAN}[START] $label${NC}"

    # Stream child output live, save it, and show heartbeat if quiet.
    (
        if command -v stdbuf >/dev/null 2>&1; then
            stdbuf -oL -eL bash "$script"
        else
            bash "$script"
        fi
    ) 2>&1 | tee "$log" &
    local pipe_pid="$!"

    local heartbeat=0
    while kill -0 "$pipe_pid" 2>/dev/null; do
        sleep 10
        if kill -0 "$pipe_pid" 2>/dev/null; then
            heartbeat=$((heartbeat + 1))
            echo -e "${YELLOW}[progress] $label still running... heartbeat=${heartbeat}${NC}"
        fi
    done

    wait "$pipe_pid"
    local rc="$?"

    echo -e "${CYAN}[DONE] $label rc=$rc${NC}"

    local clean_log="$log.clean"
    strip_ansi < "$log" > "$clean_log"

    local summary
    summary="$(grep -E "PASS:[[:space:]]*[0-9]+[[:space:]]+FAIL:[[:space:]]*[0-9]+" "$clean_log" | tail -n 1 || true)"

    local pass_n=""
    local fail_n=""

    if [ -n "$summary" ]; then
        pass_n="$(echo "$summary" | awk '{
            for (i=1; i<=NF; i++) {
                if ($i ~ /^PASS:/) {
                    if ($i == "PASS:") print $(i+1);
                    else { sub("PASS:", "", $i); print $i; }
                }
            }
        }' | tail -n 1)"

        fail_n="$(echo "$summary" | awk '{
            for (i=1; i<=NF; i++) {
                if ($i ~ /^FAIL:/) {
                    if ($i == "FAIL:") print $(i+1);
                    else { sub("FAIL:", "", $i); print $i; }
                }
            }
        }' | tail -n 1)"
    fi

    [ -n "$pass_n" ] || pass_n=0
    [ -n "$fail_n" ] || fail_n=999

    # Official truth rule:
    # If child table reports PASS>0 and FAIL=0, it passed.
    # This avoids false failure from cosmetic child banners.
    if [ "$pass_n" -gt 0 ] && [ "$fail_n" -eq 0 ]; then
        printf "%s\tPASS\tSIM\tPASS=%s FAIL=%s\n" "$label" "$pass_n" "$fail_n" >> "$RESULTS"
        PASS_COUNT=$((PASS_COUNT + 1))
    else
        local detail
        detail="$(grep -m 1 -Ei "FAIL:|FAIL |error|missing|compile|timeout|mismatch|No such" "$clean_log" | sed 's/\t/ /g' | cut -c1-40 || true)"
        [ -n "$detail" ] || detail="rc=$rc PASS=$pass_n FAIL=$fail_n"
        printf "%s\tFAIL\tSIM\t%s\n" "$label" "$detail" >> "$RESULTS"
        FAIL_COUNT=$((FAIL_COUNT + 1))
    fi
}

echo "=== SDMC UART SHIPPING TABLES ==="
echo "Reports: $REPORTDIR"
echo "Logs:    $LOGDIR"

run_table "TOP_UART_AEAD" \
    "tools/run_sdmc_top_uart_aead_matrix_table.sh"

run_table "TOP_UART_HASH256_CORE" \
    "tools/run_sdmc_top_uart_hash_kat_core_table.sh"

run_table "TOP_UART_XOF_CXOF_SINGLE" \
    "tools/run_sdmc_top_uart_xof_cxof_kat_core_table.sh"

run_table "TOP_UART_XOF_CXOF_CHAIN" \
    "tools/run_sdmc_top_uart_xof_cxof_chain_core_table.sh"

echo
printf "+----------------------------+------------+---------+------------------------------------------+\n"
printf "| %-26s | %-10s | %-7s | %-40s |\n" "UART_TABLE" "STATUS" "STAGE" "DETAIL"
printf "+----------------------------+------------+---------+------------------------------------------+\n"

while IFS=$'\t' read -r label status stage detail; do
    if [ "$status" = "PASS" ]; then
        printf "| %-26s | ${GREEN}%-10s${NC} | %-7s | %-40s |\n" "$label" "PASS [OK]" "$stage" "$detail"
    else
        printf "| %-26s | ${RED}%-10s${NC} | %-7s | %-40s |\n" "$label" "FAIL [X]" "$stage" "$detail"
    fi
done < "$RESULTS"

printf "+----------------------------+------------+---------+------------------------------------------+\n"
echo
echo "RUN:  $RUN_COUNT"
echo "PASS: $PASS_COUNT  FAIL: $FAIL_COUNT"

if [ "$PASS_COUNT" -eq 4 ] && [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}PASS sdmc_uart_shipping_tables${NC}"
    echo
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo -e "${GREEN}${BOLD}              \\(^_^)/   ALL UART TABLES PASSED   \\(^_^)/${NC}"
    echo -e "${GREEN}${BOLD}                    CHIP UART PATH IS HEALTHY${NC}"
    echo -e "${GREEN}${BOLD}============================================================${NC}"
    echo
    echo "Results: $RESULTS"
    echo "Logs:    $LOGDIR"
    exit 0
else
    echo -e "${RED}FAIL sdmc_uart_shipping_tables [X]${NC}"
    echo
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo -e "${RED}${BOLD}                    (T_T)   SOME FAILURES   (T_T)${NC}"
    echo -e "${RED}${BOLD}              DO NOT CLAIM CHIP UART PATH IS COMPLETE${NC}"
    echo -e "${RED}${BOLD}============================================================${NC}"
    echo
    echo "Results: $RESULTS"
    echo "Logs:    $LOGDIR"
    exit 1
fi
