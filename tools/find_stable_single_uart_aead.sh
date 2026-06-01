#!/usr/bin/env bash
set -euo pipefail

BASE="$(pwd)"
WT="${BASE}/../tt-ascon-full-stable-hunt"
REPORT="${BASE}/reports/stable_hunt"
mkdir -p "$REPORT"

echo "===== BASE REPO =====" | tee "$REPORT/run.log"
pwd | tee -a "$REPORT/run.log"
git rev-parse HEAD | tee -a "$REPORT/run.log"
git status --short | tee "$REPORT/base_status.txt"

echo "===== SNAPSHOT CURRENT SOURCE =====" | tee -a "$REPORT/run.log"
tar czf "$REPORT/current_src_snapshot.tgz" src tools test 2>/dev/null || true
git diff > "$REPORT/current_diff.patch" || true

echo "===== BUILD CANDIDATE COMMIT LIST =====" | tee -a "$REPORT/run.log"
{
  git reflog --date=iso --format='%H %gd %ci %gs' -n 80
  git log --date=iso --format='%H HEADLOG %ci %s' -n 80
} | awk '!seen[$1]++ {print $1}' > "$REPORT/candidates.txt"

wc -l "$REPORT/candidates.txt" | tee -a "$REPORT/run.log"

echo "===== PREPARE WORKTREE =====" | tee -a "$REPORT/run.log"
git worktree remove -f "$WT" >/dev/null 2>&1 || true
git worktree add -f "$WT" HEAD >/dev/null

test_one_commit() {
  local C="$1"
  local OUTDIR="$REPORT/$C"
  mkdir -p "$OUTDIR"

  echo "===== TEST $C =====" | tee -a "$REPORT/run.log"

  git -C "$WT" checkout -f "$C" >/dev/null 2>&1 || {
    echo "CHECKOUT_FAIL $C" | tee -a "$REPORT/run.log"
    return 1
  }

  # Use the known generated old single-UART tests from the base repo.
  rm -rf "$WT/test/sdmc_top_uart_aead_matrix"
  mkdir -p "$WT/test"
  cp -a "$BASE/test/sdmc_top_uart_aead_matrix" "$WT/test/" 2>/dev/null || {
    echo "NO_TOP_UART_TEST_DIR $C" | tee -a "$REPORT/run.log"
    return 1
  }

  cd "$WT"

  local UART_RX_SRC
  local UART_TX_SRC
  UART_RX_SRC="$(grep -RslE '^[[:space:]]*module[[:space:]]+uart_rx\b' src test | head -n 1 || true)"
  UART_TX_SRC="$(grep -RslE '^[[:space:]]*module[[:space:]]+uart_tx\b' src test | head -n 1 || true)"

  if [ -z "$UART_RX_SRC" ] || [ -z "$UART_TX_SRC" ]; then
    echo "NO_UART_SRC $C" | tee "$OUTDIR/result.txt"
    cd "$BASE"
    return 1
  fi

  local OK=1

  for MODE in enc dec badtag; do
    local TB="test/sdmc_top_uart_aead_matrix/sdmc_top_uart_kat_c001_ad0_pt0_${MODE}/tb_sdmc_top_uart_kat_c001_ad0_pt0_${MODE}.v"
    local VVP="/tmp/sdmc_top_uart_${C}_${MODE}.vvp"
    local CLOG="$OUTDIR/compile_${MODE}.log"
    local RLOG="$OUTDIR/run_${MODE}.log"

    if [ ! -f "$TB" ]; then
      echo "MISSING_TB $TB" | tee -a "$OUTDIR/result.txt"
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
      echo "COMPILE_FAIL $MODE" | tee -a "$OUTDIR/result.txt"
      grep -iE "error|syntax|unknown module|unable to bind|not a port|already been declared|failed" "$CLOG" | head -40 | tee -a "$OUTDIR/result.txt"
      OK=0
      break
    fi

    timeout 120s vvp "$VVP" > "$RLOG" 2>&1 || true

    grep -iE "PASS|FAIL|output bytes|auth_ok|busy|done|error" "$RLOG" > "$OUTDIR/summary_${MODE}.txt" || true

    if grep -qi "FAIL" "$RLOG"; then
      echo "RUN_FAIL $MODE" | tee -a "$OUTDIR/result.txt"
      cat "$OUTDIR/summary_${MODE}.txt" | tee -a "$OUTDIR/result.txt"
      OK=0
      break
    fi

    if ! grep -qi "PASS" "$RLOG"; then
      echo "NO_PASS_LINE $MODE" | tee -a "$OUTDIR/result.txt"
      cat "$OUTDIR/summary_${MODE}.txt" | tee -a "$OUTDIR/result.txt"
      OK=0
      break
    fi

    echo "PASS $MODE" | tee -a "$OUTDIR/result.txt"
  done

  cd "$BASE"

  if [ "$OK" = "1" ]; then
    echo "$C" > "$REPORT/PASSING_COMMIT.txt"
    echo "FOUND_PASSING_COMMIT $C" | tee -a "$REPORT/run.log"
    return 0
  fi

  return 1
}

FOUND=0
while read -r C; do
  [ -z "$C" ] && continue
  if test_one_commit "$C"; then
    FOUND=1
    break
  fi
done < "$REPORT/candidates.txt"

echo "===== DONE =====" | tee -a "$REPORT/run.log"

if [ "$FOUND" = "1" ]; then
  C="$(cat "$REPORT/PASSING_COMMIT.txt")"
  echo "PASSING_COMMIT=$C" | tee -a "$REPORT/run.log"
  echo
  echo "To restore the stable RTL into the main repo, run:"
  echo "  git checkout $C -- src"
  echo
  echo "Then rerun the old top UART AEAD tests."
else
  echo "NO PASSING COMMIT FOUND IN RECENT REFLOG/LOG" | tee -a "$REPORT/run.log"
  echo "Check reports/stable_hunt/*/result.txt"
  exit 1
fi
