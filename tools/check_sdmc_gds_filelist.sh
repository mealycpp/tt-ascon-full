#!/usr/bin/env bash
set -u -o pipefail

GREEN="\033[32m"
RED="\033[31m"
YELLOW="\033[33m"
RESET="\033[0m"

REQUIRED=(
  "src/ascon_round.v"
  "src/ascon_permutation.v"
  "src/sdmc/sdmc_fifo.v"
  "src/sdmc/sdmc_token_fifo.v"
  "src/sdmc/sdmc_stream_ingress.v"
  "src/sdmc/sdmc_stream_egress.v"
  "src/sdmc/sdmc_stream_shell.v"
  "src/sdmc/sdmc_config_regs.v"
  "src/sdmc/sdmc_ascon_perm_unit64.v"
  "src/sdmc/sdmc_hash256_core.v"
  "src/sdmc/sdmc_xof_family_core.v"
  "src/sdmc/sdmc_xof_chain_family_core.v"
  "src/sdmc/sdmc_aead128_core.v"
  "src/sdmc/sdmc_crypto_top.v"
)

MANIFESTS=(
  "info.yaml"
  "Makefile"
  "src/Makefile"
  "src/config.tcl"
  "openlane/config.json"
  "openlane/config.tcl"
  "config.json"
  "config.tcl"
)

mkdir -p reports
RESULTS="reports/sdmc_gds_filelist_results.tsv"
: > "$RESULTS"

fail=0
warn=0

echo "=== SDMC GDS FILELIST AUDIT ==="

for f in "${REQUIRED[@]}"; do
  if [ -f "$f" ]; then
    printf "%s\tPASS\tfile exists\n" "$f" >> "$RESULTS"
  else
    printf "%s\tFAIL\tmissing required RTL file\n" "$f" >> "$RESULTS"
    fail=$((fail + 1))
  fi
done

found_manifest=0
for m in "${MANIFESTS[@]}"; do
  if [ -f "$m" ]; then
    found_manifest=1
    printf "%s\tPASS\tmanifest found\n" "$m" >> "$RESULTS"
  fi
done

if [ "$found_manifest" -eq 0 ]; then
  printf "manifest\tWARN\tno known GDS/YAML manifest found\n" >> "$RESULTS"
  warn=$((warn + 1))
fi

for f in "${REQUIRED[@]}"; do
  base="$(basename "$f")"
  seen=0
  for m in "${MANIFESTS[@]}"; do
    if [ -f "$m" ] && grep -q "$base" "$m"; then
      seen=1
    fi
  done

  if [ "$seen" -eq 1 ]; then
    printf "%s\tPASS\treferenced by manifest/source list\n" "$f" >> "$RESULTS"
  else
    printf "%s\tWARN\tnot referenced in common manifest/source lists\n" "$f" >> "$RESULTS"
    warn=$((warn + 1))
  fi
done

echo
echo "=== Backup / generated RTL check ==="
bad_files="$(find src -type f \( -name '*.before*' -o -name '*.backup*' -o -name '*.bad_paste' -o -name '*~' \) | sort || true)"
if [ -n "$bad_files" ]; then
  while read -r bf; do
    [ -n "$bf" ] || continue
    printf "%s\tWARN\tbackup/generated file under src\n" "$bf" >> "$RESULTS"
    warn=$((warn + 1))
  done <<< "$bad_files"
else
  printf "src backup files\tPASS\tno backup/generated RTL under src\n" >> "$RESULTS"
fi

echo
echo "=== SDMC GDS FILELIST SUMMARY ==="
printf "+-------------------------------------------------------------------+--------+------------------------------------------+\n"
printf "| Item                                                              | Status | Detail                                   |\n"
printf "+-------------------------------------------------------------------+--------+------------------------------------------+\n"

while IFS=$'\t' read -r item status detail; do
  short="$item"
  if [ ${#short} -gt 65 ]; then
    short="${short:0:62}..."
  fi

  if [ "$status" = "PASS" ]; then
    color="$GREEN"; mark="PASS ✅"
  elif [ "$status" = "WARN" ]; then
    color="$YELLOW"; mark="WARN ⚠️"
  else
    color="$RED"; mark="FAIL ❌"
  fi

  printf "| %-65s | ${color}%-6s${RESET} | %-40s |\n" "$short" "$mark" "$detail"
done < "$RESULTS"

printf "+-------------------------------------------------------------------+--------+------------------------------------------+\n"

if [ "$fail" -eq 0 ]; then
  echo -e "${GREEN}PASS sdmc_gds_filelist_audit: 0 failures, ${warn} warning(s)${RESET}"
  exit 0
else
  echo -e "${RED}FAIL sdmc_gds_filelist_audit: ${fail} failure(s), ${warn} warning(s)${RESET}"
  exit 1
fi
