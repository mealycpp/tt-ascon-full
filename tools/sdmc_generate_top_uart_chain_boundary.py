#!/usr/bin/env python3
from pathlib import Path
import re
import shutil

ROOT = Path(".")
CORE_DIR = ROOT / "test/sdmc_chain_vector_matrix"
TEMPLATE_DIR = ROOT / "test/sdmc_top_uart_xof_cxof_kat_massive"
OUT_DIR = ROOT / "test/sdmc_top_uart_chain_boundary"

WANT = [
    "sdmc_xof_chain_empty_c1_out32",
    "sdmc_xof_chain_empty_c2_out32",
    "sdmc_xof_chain_empty_c5_out32",
    "sdmc_xof_chain_empty_c16_out32",
    "sdmc_xof_chain_m16_c1_out32",
    "sdmc_xof_chain_m16_c2_out32",
    "sdmc_xof_chain_m16_c5_out32",
    "sdmc_xof_chain_m16_c16_out32",
    "sdmc_xof_chain_m17_c1_out32",
    "sdmc_xof_chain_m17_c5_out32",
    "sdmc_xof_chain_m32_c1_out32",
    "sdmc_xof_chain_m32_c5_out32",
    "sdmc_cxof_chain_z8_empty_c1_out32",
    "sdmc_cxof_chain_z8_empty_c2_out32",
    "sdmc_cxof_chain_z8_empty_c5_out32",
    "sdmc_cxof_chain_z8_empty_c16_out32",
    "sdmc_cxof_chain_z8_m16_c1_out32",
    "sdmc_cxof_chain_z8_m16_c2_out32",
    "sdmc_cxof_chain_z8_m16_c5_out32",
    "sdmc_cxof_chain_z8_m16_c16_out32",
    "sdmc_cxof_chain_z8_m17_c1_out32",
    "sdmc_cxof_chain_z8_m17_c5_out32",
    "sdmc_cxof_chain_z8_m32_c1_out32",
    "sdmc_cxof_chain_z8_m32_c5_out32",
]

def pick_template(cxof: bool) -> Path:
    pattern = "tb_cxof*.v" if cxof else "tb_xof*.v"
    candidates = sorted(TEMPLATE_DIR.glob(pattern))
    for p in candidates:
        txt = p.read_text()
        if "uart_send_byte" in txt and "CHAIN_COUNT" in txt:
            return p
    raise SystemExit(f"FAIL: no usable template found in {TEMPLATE_DIR} for {'CXOF' if cxof else 'XOF'}")

def parse_core_tb(name: str):
    core_tb = CORE_DIR / name / f"tb_{name}.v"
    if not core_tb.exists():
        raise SystemExit(f"FAIL: missing core TB: {core_tb}")

    txt = core_tb.read_text()

    m = re.search(r"got\s*!==\s*256'h([0-9a-fA-F]+)", txt)
    if not m:
        raise SystemExit(f"FAIL: could not parse expected digest from {core_tb}")

    exp_hex = m.group(1).lower()
    exp_bytes = list(reversed([exp_hex[i:i+2] for i in range(0, len(exp_hex), 2)]))

    msg = []
    cs = []

    tok_re = re.compile(
        r"token_mem\[\d+\]\s*=\s*\{\s*1'b[01]\s*,\s*`SDMC_TOK_(MSG|CS)\s*,\s*4'd(\d+)\s*,\s*64'h([0-9a-fA-F]+)\s*\}\s*;"
    )

    for tm in tok_re.finditer(txt):
        kind = tm.group(1)
        count = int(tm.group(2))
        word_hex = tm.group(3).zfill(16).lower()

        # token data is consumed little-endian: tok_data[7:0], [15:8], ...
        be = [word_hex[i:i+2] for i in range(0, 16, 2)]
        le = list(reversed(be))[:count]

        if kind == "MSG":
            msg.extend(le)
        elif kind == "CS":
            cs.extend(le)

    cm = re.search(r"_c(\d+)_out(\d+)$", name)
    if not cm:
        raise SystemExit(f"FAIL: could not parse chain/out length from name: {name}")

    chain_count = int(cm.group(1))
    out_len = int(cm.group(2))
    cxof = name.startswith("sdmc_cxof_")
    mode = 3 if cxof else 2

    return {
        "core_tb": core_tb,
        "cxof": cxof,
        "mode": mode,
        "chain_count": chain_count,
        "out_len": out_len,
        "msg": msg,
        "cs": cs,
        "exp": exp_bytes,
    }

def replace_localparam(txt: str, key: str, value: int) -> str:
    pat = rf"localparam integer {key}\s*=\s*\d+\s*;"
    rep = f"localparam integer {key} = {value};"
    if re.search(pat, txt):
        return re.sub(pat, rep, txt)
    raise SystemExit(f"FAIL: template missing localparam {key}")

def patch_array_decl(txt: str, name: str, depth_expr: str) -> str:
    pat = rf"reg\s+\[7:0\]\s+{name}\s*\[[^\n;]+\]\s*;"
    rep = (
        f"localparam integer {name.upper()}_DEPTH = {depth_expr};\n"
        f"    reg [7:0] {name} [0:{name.upper()}_DEPTH-1];"
    )
    if re.search(pat, txt):
        return re.sub(pat, rep, txt, count=1)
    raise SystemExit(f"FAIL: template missing array declaration for {name}")

def emit_assign(arr: str, values):
    return "\n".join(f"        {arr}[{i}] = 8'h{b};" for i, b in enumerate(values))

def make_tb(name: str):
    info = parse_core_tb(name)
    template = pick_template(info["cxof"])
    txt = template.read_text()

    old_mod = re.search(r"module\s+(\w+)\s*;", txt)
    if not old_mod:
        raise SystemExit(f"FAIL: could not parse module name from {template}")

    old_module = old_mod.group(1)
    old_case = old_module.replace("tb_", "")

    txt = re.sub(r"module\s+\w+\s*;", f"module tb_{name};", txt, count=1)
    txt = txt.replace(old_case, name)

    txt = replace_localparam(txt, "MODE", info["mode"])
    txt = replace_localparam(txt, "MSG_LEN", len(info["msg"]))
    txt = replace_localparam(txt, "CS_LEN", len(info["cs"]))
    txt = replace_localparam(txt, "OUT_LEN", info["out_len"])
    txt = replace_localparam(txt, "CHAIN_COUNT", info["chain_count"])

    # Critical fix: never leave msg/cs/exp_md as [0:0] when length > 1.
    # Also avoid illegal zero-depth memories when length is 0.
    txt = patch_array_decl(txt, "msg", "((MSG_LEN > 0) ? MSG_LEN : 1)")
    txt = patch_array_decl(txt, "cs", "((CS_LEN > 0) ? CS_LEN : 1)")
    txt = patch_array_decl(txt, "exp_md", "((OUT_LEN > 0) ? OUT_LEN : 1)")

    # Remove old generated assignments.
    txt = re.sub(r"^\s*msg\[\d+\]\s*=\s*8'h[0-9a-fA-F]{2}\s*;\s*$", "", txt, flags=re.M)
    txt = re.sub(r"^\s*cs\[\d+\]\s*=\s*8'h[0-9a-fA-F]{2}\s*;\s*$", "", txt, flags=re.M)
    txt = re.sub(r"^\s*exp_md\[\d+\]\s*=\s*8'h[0-9a-fA-F]{2}\s*;\s*$", "", txt, flags=re.M)

    init = []
    init.append(f"        // Auto-generated top-UART chain vector: {name}")
    init.append(f"        // Source core TB: {info['core_tb']}")
    if info["msg"]:
        init.append(emit_assign("msg", info["msg"]))
    if info["cs"]:
        init.append(emit_assign("cs", info["cs"]))
    init.append(emit_assign("exp_md", info["exp"]))
    init_block = "\n".join(init) + "\n\n"

    if "        wait_cycles(100);" not in txt:
        raise SystemExit(f"FAIL: template missing wait_cycles(100) insertion point: {template}")
    txt = txt.replace("        wait_cycles(100);", init_block + "        wait_cycles(100);", 1)

    # Important: replace CXOF_TOP first, otherwise CXOF_TOP becomes CCHAIN_TOP.
    txt = txt.replace("CXOF_TOP", "CHAIN_TOP")
    txt = txt.replace("XOF_TOP", "CHAIN_TOP")

    case_dir = OUT_DIR / name
    case_dir.mkdir(parents=True, exist_ok=True)
    out_tb = case_dir / f"tb_{name}.v"
    out_tb.write_text(txt)

    return out_tb

def main():
    if not CORE_DIR.exists():
        raise SystemExit(f"FAIL: missing core chain directory: {CORE_DIR}")
    if not TEMPLATE_DIR.exists():
        raise SystemExit(f"FAIL: missing top-UART XOF/CXOF template directory: {TEMPLATE_DIR}")

    if OUT_DIR.exists():
        shutil.rmtree(OUT_DIR)
    OUT_DIR.mkdir(parents=True, exist_ok=True)

    made = []
    for name in WANT:
        tb = make_tb(name)
        made.append(name)

    manifest = OUT_DIR / "manifest.txt"
    manifest.write_text("\n".join(made) + "\n")

    print(f"Generated {len(made)} top-UART XOF/CXOF chain tests")
    print(f"Manifest: {manifest}")

if __name__ == "__main__":
    main()
