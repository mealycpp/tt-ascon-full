#!/usr/bin/env bash
set -euo pipefail

LOG="reports/sdmc_uart_smoke_inner.log"
mkdir -p reports

echo "=== sdmc_uart_top_hash_abc_uart_path ==="
echo "Running current UART top smoke: make -C test/top"
echo "Live output is shown below."
echo "Log also saved to: $LOG"
echo

rm -f "$LOG"

if timeout 120s stdbuf -oL -eL make -C test/top 2>&1 | tee "$LOG"; then
  echo
  echo "=== Checking UART HASH pass marker ==="

  if grep -q "test_e2e_hash_abc_uart_top passed" "$LOG" || grep -q "PASS e2e_hash_abc_uart_top" "$LOG"; then
    echo
    echo "=== SDMC UART SMOKE SUMMARY ==="
    echo "+--------------------------------------+--------+--------------------------------------+"
    echo "| Test                                 | Status | Detail                               |"
    echo "+--------------------------------------+--------+--------------------------------------+"
    printf "| %-36s | %-6s | %-36s |\n" "sdmc_uart_top_hash_abc_uart_path" "PASS" "current top UART HASH path"
    echo "+--------------------------------------+--------+--------------------------------------+"
    echo "PASS sdmc_uart_smoke"
    exit 0
  fi

  echo "FAIL sdmc_uart_smoke: make passed but UART HASH marker was not found"
else
  echo
  echo "FAIL sdmc_uart_smoke: make failed or timed out"
fi

echo "See: $LOG"
echo
echo "=== Last 80 log lines ==="
tail -n 80 "$LOG" || true
exit 1
