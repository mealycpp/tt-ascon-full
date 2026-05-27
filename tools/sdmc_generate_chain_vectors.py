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
    return subprocess.check_output(cmd, text=True).strip().splitlines()[-1].strip()

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
    vectors = []

    for msg_name, msg_hex in MSG_CASES.items():
        for count in CHAIN_COUNTS:
            for out_len in OUT_LENS:
                vectors.append({
                    "family": "xof_chain",
                    "name": f"xof_chain_{msg_name}_c{count}_out{out_len}",
                    "msg_name": msg_name,
                    "msg_hex": msg_hex,
                    "cs_name": "",
                    "cs_hex": "",
                    "chain_count": count,
                    "out_len": out_len,
                    "expected_hex": xof_chain(count, out_len, msg_hex),
                })

    for cs_name, cs_hex in CS_CASES.items():
        for msg_name, msg_hex in MSG_CASES.items():
            for count in CHAIN_COUNTS:
                for out_len in OUT_LENS:
                    vectors.append({
                        "family": "cxof_chain",
                        "name": f"cxof_chain_{cs_name}_{msg_name}_c{count}_out{out_len}",
                        "msg_name": msg_name,
                        "msg_hex": msg_hex,
                        "cs_name": cs_name,
                        "cs_hex": cs_hex,
                        "chain_count": count,
                        "out_len": out_len,
                        "expected_hex": cxof_chain(count, out_len, cs_hex, msg_hex),
                    })

    # Add explicit equivalence checks as metadata:
    # count=1 should equal primitive XOF/CXOF.
    for v in vectors:
        if v["chain_count"] == 1:
            if v["family"] == "xof_chain":
                primitive = xof(v["out_len"], v["msg_hex"])
            else:
                primitive = cxof(v["out_len"], v["cs_hex"], v["msg_hex"])
            v["count1_equals_primitive"] = (primitive == v["expected_hex"])

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps({
        "description": "Generated SDMC XOF-chain and CXOF-chain vectors using local ascon-c reference CLIs. Intermediate chain outputs are 32 bytes; final output uses out_len.",
        "chain_rule": "cur=msg; for i in 1..chain_count: cur=XOF/CXOF(32 bytes, cur) except final iteration uses requested out_len.",
        "vectors": vectors,
    }, indent=2) + "\n")

    print(f"Wrote {OUT}")
    print(f"vectors={len(vectors)}")
    assert all(v.get("count1_equals_primitive", True) for v in vectors), "chain_count=1 equivalence failed"
    print("PASS chain_count_1_equivalence")

if __name__ == "__main__":
    main()
