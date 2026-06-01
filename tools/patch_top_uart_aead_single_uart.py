#!/usr/bin/env python3
from pathlib import Path
import re

root = Path("test/sdmc_top_uart_aead_matrix")
if not root.exists():
    raise SystemExit(f"ERROR: missing {root}")

checked = 0
patched = 0

for tb in sorted(root.glob("*/tb_*.v")):
    checked += 1
    s0 = tb.read_text()
    s = s0

    # Current project_sdmc_uart_top.v exposes only ui_in[0] as real UART RX.
    # Therefore command, key, nonce, AD, message, and tag must all be serialized on line 0.
    s = re.sub(r"uart_send_byte\(\s*1\s*,", "uart_send_byte(0,", s)
    s = re.sub(r"uart_send_byte\(\s*2\s*,", "uart_send_byte(0,", s)

    if s != s0:
        tb.write_text(s)
        patched += 1

bad = []
for tb in sorted(root.glob("*/tb_*.v")):
    s = tb.read_text()
    if "uart_send_byte(1" in s or "uart_send_byte(2" in s:
        bad.append(str(tb))

print(f"TOP_UART_AEAD_TB_CHECKED={checked}")
print(f"TOP_UART_AEAD_TB_PATCHED={patched}")

if bad:
    print("ERROR: non-single-UART stimulus remains:")
    for b in bad[:20]:
        print(b)
    raise SystemExit(1)

print("TOP_UART_AEAD_SINGLE_UART_PATCH_OK")
