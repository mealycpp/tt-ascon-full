#!/usr/bin/env bash
set -u -o pipefail
BASE="$(cd "$(dirname "$0")/.." && pwd)"
cd "$BASE"

ORIG_RUNNER="tools/run_sdmc_top_uart_xof_cxof_kat_massive_table.sh"
TMP_RUNNER="tools/.run_sdmc_top_uart_xof_cxof_kat_core_from_massive_table.sh"

TESTDIR="test/sdmc_top_uart_xof_cxof_kat_massive"
MANIFEST="$TESTDIR/manifest.txt"

GEN="tools/sdmc_generate_top_uart_xof_cxof_kat_massive.py"

REPORTDIR="reports/sdmc_top_uart_xof_cxof_kat_core"
SELECTOR="$REPORTDIR/select_xof_cxof_core_manifest.py"

mkdir -p "$REPORTDIR"

echo "=== SDMC TOP UART XOF/CXOF KAT CORE TABLE ==="

if [ ! -f "$ORIG_RUNNER" ]; then
    echo "FAIL: missing existing runner: $ORIG_RUNNER"
    exit 1
fi

if [ -f "$GEN" ]; then
    echo "Generating XOF/CXOF KAT pool..."
    python3 "$GEN"
fi

if [ ! -s "$MANIFEST" ]; then
    echo "FAIL: missing or empty manifest: $MANIFEST"
    echo "Expected existing/generated XOF/CXOF KAT manifest."
    exit 1
fi

cat > "$SELECTOR" <<'PY'
from pathlib import Path
import re

manifest = Path("test/sdmc_top_uart_xof_cxof_kat_massive/manifest.txt")
reportdir = Path("reports/sdmc_top_uart_xof_cxof_kat_core")
core_manifest = reportdir / "core_manifest.txt"
full_manifest = reportdir / "full_manifest.generated.txt"

want_xof_m = {
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

# CXOF should not explode. Cover empty/nonempty customization and message boundaries.
want_cxof_pairs = {
    (0, 0),
    (1, 0),
    (8, 0),
    (16, 0),
    (32, 0),

    (0, 1),
    (1, 1),
    (8, 1),
    (16, 1),
    (32, 1),

    (0, 8),
    (1, 8),
    (8, 8),
    (16, 8),
    (32, 8),

    (0, 16),
    (1, 16),
    (8, 16),
    (16, 16),
    (32, 16),

    (0, 32),
    (1, 32),
    (8, 32),
    (16, 32),
    (32, 32),
}

if not manifest.exists() or manifest.stat().st_size == 0:
    raise SystemExit(f"FAIL: generated manifest missing or empty: {manifest}")

lines = [x.strip() for x in manifest.read_text().splitlines() if x.strip()]
full_manifest.write_text("\n".join(lines) + "\n")

selected = []

for name in lines:
    if name.startswith("xof_"):
        m = re.search(r"_m([0-9]+)_cs0_out64$", name)
        if m and int(m.group(1)) in want_xof_m:
            selected.append(name)

    elif name.startswith("cxof_"):
        m = re.search(r"_m([0-9]+)_cs([0-9]+)_out64$", name)
        if m:
            msg_len = int(m.group(1))
            custom_len = int(m.group(2))
            if (msg_len, custom_len) in want_cxof_pairs:
                selected.append(name)

if not selected:
    raise SystemExit("FAIL: selected zero XOF/CXOF core vectors")

manifest.write_text("\n".join(selected) + "\n")
core_manifest.write_text("\n".join(selected) + "\n")

xof_count = sum(1 for x in selected if x.startswith("xof_"))
cxof_count = sum(1 for x in selected if x.startswith("cxof_"))

print(f"Core XOF/CXOF vectors selected: {len(selected)}")
print(f"  XOF : {xof_count}")
print(f"  CXOF: {cxof_count}")
print(f"Core manifest: {core_manifest}")
PY

python3 "$SELECTOR"

python3 - <<'PY'
from pathlib import Path

orig = Path("tools/run_sdmc_top_uart_xof_cxof_kat_massive_table.sh")
tmp = Path("tools/.run_sdmc_top_uart_xof_cxof_kat_core_from_massive_table.sh")

s = orig.read_text()

s = s.replace(
    "reports/sdmc_top_uart_xof_cxof_kat_massive",
    "reports/sdmc_top_uart_xof_cxof_kat_core"
)

s = s.replace(
    "TOP UART OFFICIAL XOF/CXOF KAT MASSIVE TABLE",
    "TOP UART OFFICIAL XOF/CXOF KAT CORE TABLE"
)

s = s.replace(
    "sdmc_top_uart_xof_cxof_kat_massive_table",
    "sdmc_top_uart_xof_cxof_kat_core_table"
)

tmp.write_text(s)
PY

chmod +x "$TMP_RUNNER"

"$TMP_RUNNER"
rc=$?

rm -f "$TMP_RUNNER"

echo
echo "=== CORE XOF/CXOF RUN COMPLETE ==="
echo "Core manifest:        $REPORTDIR/core_manifest.txt"
echo "Full manifest backup: $REPORTDIR/full_manifest.generated.txt"
echo "Reports:              $REPORTDIR"

exit "$rc"
