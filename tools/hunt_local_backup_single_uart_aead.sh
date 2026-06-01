#!/usr/bin/env bash
set -euo pipefail

BASE="$(pwd)"
WT="${BASE}/../tt-ascon-full-local-backup-hunt"
REPORT="${BASE}/reports/local_backup_hunt"
mkdir -p "$REPORT"

echo "===== LOCAL BACKUP HUNT =====" | tee "$REPORT/run.log"
echo "BASE=$BASE" | tee -a "$REPORT/run.log"

git worktree remove -f "$WT" >/dev/null 2>&1 || true
git worktree add -f "$WT" HEAD >/dev/null

# Find backup snapshots that contain a full src/ tree.
find "$BASE/backup_before_bak_restore" -type f -path '*/src/project_sdmc_uart_top.v' 2>/dev/null \
  | sed 's#/src/project_sdmc_uart_top.v##' \
  | sort -u > "$REPORT/source_snapshots.txt" || true

echo "===== SOURCE SNAPSHOTS FOUND =====" | tee -a "$REPORT/run.log"
cat "$REPORT/source_snapshots.txt" | tee -a "$REPORT/run.log"

if [ ! -s "$REPORT/source_snapshots.txt" ]; then
  echo "NO FULL SOURCE SNAPSHOT FOUND IN backup_before_bak_restore" | tee -a "$REPORT/run.log"
  echo "Now list candidate individual backups:"
  find "$BASE" -type f \( \
      -name 'project_sdmc_uart_top.v*' -o \
      -name 'sdmc_aead128_core.v*' -o \
      -name 'sdmc_aead_uart_frontend.v*' \
    \) \
    ! -path '*/.git/*' \
    | sort | tee "$REPORT/individual_backup_files.txt"
  exit 1
fi

restore_old_single_uart_tbs() {
  find test/sdmc_top_uart_aead_matrix -name '*.v.bak_single_uart_aead' -print0 2>/dev/null \
    | while IFS= read -r -d '' f; do
        cp "$f" "${f%.bak_single_uart_aead}"
      done
}

test_snapshot() {
  local SNAP="$1"
  local SAFE
  SAFE="$(echo "$SNAP" | tr '/ ' '__')"
  local OUT="$REPORT/$SAFE"
  mkdir -p "$OUT"

  echo "===== TEST SNAPSHOT $SNAP =====" | tee -a "$REPORT/run.log"

  git -C "$WT" checkout -f HEAD >/dev/null
  rm -rf "$WT/src"
  cp -a "$SNAP/src" "$WT/src"

  # Use current old single-UART test directory, then restore the .bak_single_uart_aead TBs if present.
  rm -rf "$WT/test/sdmc_top_uart_aead_matrix"
  mkdir -p "$WT/test"
  cp -a "$BASE/test/sdmc_top_uart_aead_matrix" "$WT/test/"

  cd "$WT"
  restore_old_single_uart_tbs

  local UART_RX_SRC
  local UART_TX_SRC
  UART_RX_SRC="$(grep -RslE '^[[:space:]]*module[[:space:]]+uart_rx\b' src test | head -n 1 || true)"
  UART_TX_SRC="$(grep -RslE '^[[:space:]]*module[[:space:]]+uart_tx\b' src test | head -n 1 || true)"

  if [ -z "$UART_RX_SRC" ] || [ -z "$UART_TX_SRC" ]; then
    echo "NO_UART_RX_TX" | tee "$OUT/result.txt"
    cd "$BASE"
    return 1
  fi

  local OK=1

  for MODE in enc dec badtag; do
    local TB="test/sdmc_top_uart_aead_matrix/sdmc_top_uart_kat_c001_ad0_pt0_${MODE}/tb_sdmc_top_uart_kat_c001_ad0_pt0_${MODE}.v"
    local VVP="/tmp/local_backup_${MODE}.vvp"
    local CLOG="$OUT/compile_${MODE}.log"
    local RLOG="$OUT/run_${MODE}.log"

    if [ ! -f "$TB" ]; then
      echo "MISSING_TB $TB" | tee -a "$OUT/result.txt"
      OK=0
      break
    fi

    iverilog -g2012 -I src -I src/sdmc \
      -o "$VVP" \
      "$TB" \
      src/project_sdmc_uart_top.v \
      "$UART_RX_SRC" \
      "$UART_TX_SRC" \
      src/ascon_round.v \
      src/ascon_permutation.v \
      src/sdmc/*.v \
      > "$CLOG" 2>&1 || true

    if grep -qiE "error|syntax|unknown module|unable to bind|not a port|already been declared|failed" "$CLOG"; then
      echo "COMPILE_FAIL $MODE" | tee -a "$OUT/result.txt"
      grep -iE "error|syntax|unknown module|unable to bind|not a port|already been declared|failed" "$CLOG" | head -60 | tee -a "$OUT/result.txt"
      OK=0
      break
    fi

    timeout 180s vvp "$VVP" > "$RLOG" 2>&1 || true
    grep -iE "PASS|FAIL|output bytes|auth_ok|busy|done|error" "$RLOG" > "$OUT/summary_${MODE}.txt" || true

    if grep -qi "FAIL" "$RLOG"; then
      echo "RUN_FAIL $MODE" | tee -a "$OUT/result.txt"
      cat "$OUT/summary_${MODE}.txt" | tee -a "$OUT/result.txt"
      OK=0
      break
    fi

    if ! grep -qi "PASS" "$RLOG"; then
      echo "NO_PASS $MODE" | tee -a "$OUT/result.txt"
      cat "$OUT/summary_${MODE}.txt" | tee -a "$OUT/result.txt"
      OK=0
      break
    fi

    echo "PASS $MODE" | tee -a "$OUT/result.txt"
  done

  cd "$BASE"

  if [ "$OK" = "1" ]; then
    echo "$SNAP" > "$REPORT/PASSING_BACKUP_SNAPSHOT.txt"
    echo "FOUND_BACKUP_SNAPSHOT $SNAP" | tee -a "$REPORT/run.log"
    return 0
  fi

  return 1
}

FOUND=0
while read -r SNAP; do
  [ -z "$SNAP" ] && continue
  if test_snapshot "$SNAP"; then
    FOUND=1
    break
  fi
done < "$REPORT/source_snapshots.txt"

echo "===== DONE =====" | tee -a "$REPORT/run.log"

if [ "$FOUND" = "1" ]; then
  SNAP="$(cat "$REPORT/PASSING_BACKUP_SNAPSHOT.txt")"
  echo
  echo "PASSING_BACKUP_SNAPSHOT=$SNAP"
  echo
  echo "Restore stable RTL with:"
  echo "  rm -rf src"
  echo "  cp -a \"$SNAP/src\" src"
else
  echo "NO PASSING BACKUP SNAPSHOT FOUND" | tee -a "$REPORT/run.log"
  echo "Inspect reports/local_backup_hunt/*/result.txt"
  exit 1
fi
