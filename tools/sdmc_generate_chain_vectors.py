#!/usr/bin/env python3
import json
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
XOF = ROOT / "tools/ref/sdmc_xof_ref_cli"
CXOF = ROOT / "tools/ref/sdmc_cxof_ref_cli"
OUT = ROOT / "kat/derived/sdmc_chain_generated_vectors.json"

MSG_CASES = {
    "empty": "",
    "m1": "00",
    "m8": "0001020304050607",
    "m16": "000102030405060708090a0b0c0d0e0f",
    "m17": "000102030405060708090a0b0c0d0e0f10",
    "m32": "000102030405060708090a0b0c0d0e0f101112131415161718191a1b1c1d1e1f",
}

CS_CASES = {
    "z0": "",
    "z1": "10",
    "z8": "1011121314151617",
    "z16": "101112131415161718191a1b1c1d1e1f",
}

CHAIN_COUNTS = [1, 2, 5, 16]
OUT_LENS = [16, 32, 64]

def run(cmd):
    out = subprocess.check_output(cmd, text=True)
    return out.strip().splitlines()[-1].strip()

def xof(out_len, msg_hex):
    return run([str(XOF), str(out_len), msg_hex])

def cxof(out_len, cs_hex, msg_hex):
    return run([str(CXOF), str(out_len), cs_hex, msg_hex])

def xof_chain(count, out_len, msg_hex):
    cur = msg_hex
    for i in range(count):
        n = out_len if i == count - 1 else 32
        cur = xof(n, cur)
    return cur

def cxof_chain(count, out_len, cs_hex, msg_hex):
    cur = msg_hex
    for i in range(count):
        n = out_len if i == count - 1 else 32
        cur = cxof(n, cs_hex, cur)
    return cur

def main():
    if not XOF.exists():
        raise SystemExit(f"missing {XOF}")
    if not CXOF.exists():
        raise SystemExit(f"missing {CXOF}")

    vectors = []

    for msg_name, msg_hex in MSG_CASES.items():
        for count in CHAIN_COUNTS:
            for out_len in OUT_LENS:
                expected = xof_chain(count, out_len, msg_hex)
                vectors.append({
                    "family": "xof_chain",
                    "name": f"xof_chain_{msg_name}_c{count}_out{out_len}",
                    "msg_name": msg_name,
                    "msg_hex": msg_hex,
                    "cs_name": "",
                    "cs_hex": "",
                    "chain_count": count,
                    "out_len": out_len,
                    "expected_hex": expected,
                    "count1_equals_primitive": expected == xof(out_len, msg_hex) if count == 1 else None,
                })

    for cs_name, cs_hex in CS_CASES.items():
        for msg_name, msg_hex in MSG_CASES.items():
            for count in CHAIN_COUNTS:
                for out_len in OUT_LENS:
                    expected = cxof_chain(count, out_len, cs_hex, msg_hex)
                    vectors.append({
                        "family": "cxof_chain",
                        "name": f"cxof_chain_{cs_name}_{msg_name}_c{count}_out{out_len}",
                        "msg_name": msg_name,
                        "msg_hex": msg_hex,
                        "cs_name": cs_name,
                        "cs_hex": cs_hex,
                        "chain_count": count,
                        "out_len": out_len,
                        "expected_hex": expected,
                        "count1_equals_primitive": expected == cxof(out_len, cs_hex, msg_hex) if count == 1 else None,
                    })

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "description": "Generated SDMC XOF-chain and CXOF-chain vectors using local ascon-c reference CLIs.",
        "chain_rule": "cur=msg; for i in 1..chain_count: cur=XOF/CXOF(32 bytes, cur) except final iteration uses requested out_len.",
        "vectors": vectors,
    }, indent=2) + "\n")

    eq = [v for v in vectors if v["chain_count"] == 1]
    if not all(v["count1_equals_primitive"] for v in eq):
        raise SystemExit("FAIL chain_count=1 equivalence")

    print(f"Wrote {OUT}")
    print(f"vectors={len(vectors)}")
    print("PASS chain_count_1_equivalence")

if __name__ == "__main__":
    main()
