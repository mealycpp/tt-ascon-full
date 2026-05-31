#!/usr/bin/env bash
set -euo pipefail

LOG="reports/sdmc_uart_smoke_inner.log"
mkdir -p reports

GREEN="\033[0;32m"
RED="\033[0;31m"
BLUE="\033[0;34m"
NC="\033[0m"

echo -e "${BLUE}=== sdmc_uart_top_hash_abc_uart_path ===${NC}"
echo "Running current UART top smoke: make -C test/top"
echo "Live output is shown below."
echo "Raw log also saved to: $LOG"
echo

set +e
stdbuf -oL -eL make -C test/top 2>&1 | tee "$LOG" | awk '
BEGIN {
  esc=sprintf("%c", 27)
  green=esc "[0;32m"
  red=esc "[0;31m"
  yellow=esc "[0;93m"
  nc=esc "[0m"
}
{
  line=$0

  # Real error/failure lines only. Do not match debug fields like err=0 or frame_error=0.
  if (line ~ /(ERROR|Error|Traceback|AssertionError)/) {
    print red line nc
  }

  else if (line ~ /(^|[[:space:]])FAIL([[:space:]:]|$)/ && line !~ /FAIL=0/) {
    print red line nc
  }

  else if (line ~ /TESTS=.*FAIL=[1-9][0-9]*/) {
    print red line nc
  }

  else {
    # Token-level coloring only:
    # PASS = green, FAIL = red, SKIP = yellow.
    gsub(/PASS=[0-9]+/, green "&" nc, line)
    gsub(/FAIL=[0-9]+/, red "&" nc, line)
    gsub(/SKIP=[0-9]+/, yellow "&" nc, line)
    gsub(/(^|[[:space:]])PASS([[:space:]]|$)/, green "&" nc, line)
    gsub(/passed/, green "&" nc, line)
    print line
  }

  fflush()
}'
RC=${PIPESTATUS[0]}
set -e

echo
echo -e "${BLUE}=== Checking UART HASH pass marker ===${NC}"

if [ "$RC" -ne 0 ]; then
  echo -e "${RED}FAIL sdmc_uart_smoke: make -C test/top failed${NC}"
  exit 1
fi

if grep -q "test_project_smoke.test_e2e_hash_abc_uart_top passed" "$LOG" || \
   grep -q "PASS e2e_hash_abc_uart_top" "$LOG"; then
  echo
  echo -e "${BLUE}=== SDMC UART SMOKE SUMMARY ===${NC}"
  echo "+--------------------------------------+--------+--------------------------------------+"
  echo "| Test                                 | Status | Detail                               |"
  echo "+--------------------------------------+--------+--------------------------------------+"
  printf "| %-36s | ${GREEN}%-6s${NC} | %-36s |\n" \
    "sdmc_uart_top_hash_abc_uart_path" "PASS" "current top UART HASH path"
  echo "+--------------------------------------+--------+--------------------------------------+"
  echo -e "${GREEN}PASS sdmc_uart_smoke${NC}"
  exit 0
fi

echo -e "${RED}FAIL sdmc_uart_smoke: UART HASH pass marker not found${NC}"
exit 1
