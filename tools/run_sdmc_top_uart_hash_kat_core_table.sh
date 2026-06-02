#!/usr/bin/env bash
set -u -o pipefail
BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

ORIG_RUNNER="tools/run_sdmc_top_uart_hash_kat_massive_table.sh"
TMP_RUNNER="tools/.run_sdmc_top_uart_hash_kat_core_from_massive_table.sh"

TESTDIR="test/sdmc_top_uart_hash_kat_massive"
MANIFEST="$TESTDIR/manifest.txt"

REPORTDIR="reports/sdmc_top_uart_hash_kat_core"
SELECTOR="$REPORTDIR/select_hash_core_manifest.py"

mkdir -p "$REPORTDIR"

echo "=== SDMC TOP UART HASH KAT CORE TABLE ==="

if [ ! -f "$ORIG_RUNNER" ]; then
    echo "FAIL: missing existing runner: $ORIG_RUNNER"
    exit 1
fi

cat > "$SELECTOR" <<'PY'
from pathlib import Path
import re

manifest = Path("test/sdmc_top_uart_hash_kat_massive/manifest.txt")
reportdir = Path("reports/sdmc_top_uart_hash_kat_core")
core_manifest = reportdir / "core_manifest.txt"
full_manifest = reportdir / "full_manifest.generated.txt"

want = {
    0, 1, 2, 3,
    7, 8, 9,
    15, 16, 17,
    31, 32, 33,
    63, 64, 65,
    127, 128, 129,
    255, 256,
    511, 512,
    1024,
}

if not manifest.exists() or manifest.stat().st_size == 0:
    raise SystemExit(f"FAIL: generated manifest missing or empty: {manifest}")

lines = [x.strip() for x in manifest.read_text().splitlines() if x.strip()]
full_manifest.write_text("\n".join(lines) + "\n")

selected = []
for name in lines:
    m = re.search(r"_m([0-9]+)$", name)
    if not m:
        continue
    msg_len = int(m.group(1))
    if msg_len in want:
        selected.append(name)

if not selected:
    raise SystemExit("FAIL: selected zero HASH core vectors")

manifest.write_text("\n".join(selected) + "\n")
core_manifest.write_text("\n".join(selected) + "\n")

print(f"Core HASH vectors selected: {len(selected)}")
print(f"Core manifest: {core_manifest}")
PY

python3 - <<'PY'
from pathlib import Path

orig = Path("tools/run_sdmc_top_uart_hash_kat_massive_table.sh")
tmp = Path("tools/.run_sdmc_top_uart_hash_kat_core_from_massive_table.sh")

s = orig.read_text()

old = "python3 tools/sdmc_generate_top_uart_hash_kat_massive.py"
new = """python3 tools/sdmc_generate_top_uart_hash_kat_massive.py
python3 reports/sdmc_top_uart_hash_kat_core/select_hash_core_manifest.py"""

if old not in s:
    raise SystemExit("FAIL: could not find generator line in massive runner")

s = s.replace(old, new, 1)

s = s.replace(
    "reports/sdmc_top_uart_hash_kat_massive",
    "reports/sdmc_top_uart_hash_kat_core"
)

s = s.replace(
    "TOP UART OFFICIAL HASH256 KAT MASSIVE TABLE",
    "TOP UART OFFICIAL HASH256 KAT CORE TABLE"
)

s = s.replace(
    "sdmc_top_uart_hash_kat_massive_table",
    "sdmc_top_uart_hash_kat_core_table"
)

tmp.write_text(s)
PY

chmod +x "$TMP_RUNNER"

"$TMP_RUNNER"
rc=$?

rm -f "$TMP_RUNNER"

echo
echo "=== CORE HASH RUN COMPLETE ==="
echo "Core manifest:        $REPORTDIR/core_manifest.txt"
echo "Full manifest backup: $REPORTDIR/full_manifest.generated.txt"
echo "Reports:              $REPORTDIR"

exit "$rc"
