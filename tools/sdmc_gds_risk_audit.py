from pathlib import Path
import re
import sys

root = Path(".")
srcs = sorted((root / "src" / "sdmc").glob("*.v"))

allowed_320 = {"sdmc_ascon_perm_unit64.v"}
allowed_comb = {"sdmc_word_alu64.v", "sdmc_word_to_byte.v"}

fail = []
warn = []

print("=== SDMC GDS RISK AUDIT ===")

for p in srcs:
    s = p.read_text(errors="ignore")
    name = p.name

    if re.search(r"\[(319|320):0\]|\[0:(319|320)\]", s) and name not in allowed_320:
        fail.append(f"{name}: 320-bit object outside permutation unit")

    if "`default_nettype none" not in s:
        fail.append(f"{name}: missing default_nettype none")

    if "`default_nettype wire" not in s:
        fail.append(f"{name}: missing default_nettype wire at end")

    if re.search(r"EOFfault|^fault_nettype|PY'\)|S sdmc_|id=%b", s, re.M):
        fail.append(f"{name}: paste-corruption marker found")

    if re.search(r"rom_instr\(.*\)\s*\[", s):
        fail.append(f"{name}: function-call bit-select found")

    if name == "sdmc_uop_sequencer64p.v":
        issue_pos = s.find("S_ISSUE:")
        wait_pos  = s.find("S_WAIT:")
        done_pos  = s.find("S_DONE:")

        if issue_pos < 0 or wait_pos < 0 or done_pos < 0:
            fail.append(f"{name}: missing S_ISSUE/S_WAIT/S_DONE state labels")
        else:
            issue_body = s[issue_pos:wait_pos]
            wait_body  = s[wait_pos:done_pos]

            if "cmd_valid <= 1'b0" in issue_body:
                fail.append(f"{name}: bad ready/valid pattern clears cmd_valid inside S_ISSUE")

            if "cmd_valid <= 1'b0" not in wait_body:
                fail.append(f"{name}: S_WAIT does not clear cmd_valid")

    if re.search(r"always\s*@\*", s) and name not in allowed_comb:
        warn.append(f"{name}: combinational always block exists; inspect for mux fanout")

    for i, line in enumerate(s.splitlines(), 1):
        if "?" in line and "[63:0]" in line:
            warn.append(f"{name}:{i}: possible 64-bit ternary mux: {line.strip()}")

print()
print("Files audited:")
for p in srcs:
    print("  ", p)

print()
if warn:
    print("WARNINGS:")
    for w in warn:
        print("  WARN:", w)
else:
    print("WARNINGS: none")

print()
if fail:
    print("FAILURES:")
    for f in fail:
        print("  FAIL:", f)
    sys.exit(1)

print("PASS sdmc_gds_risk_audit")
