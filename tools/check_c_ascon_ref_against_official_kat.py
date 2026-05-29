#!/usr/bin/env python3
from pathlib import Path
import subprocess
import sys

KAT = Path("kat/official/ascon-c/asconaead128_LWC_AEAD_KAT_128_128.txt")
CLI = Path("tools/ascon_aead128_ref_cli")

def parse_kat(path):
    cases = []
    cur = {}
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line:
            if cur:
                cases.append(cur)
                cur = {}
            continue
        if " = " in line:
            k, v = line.split(" = ", 1)
            cur[k.strip()] = v.strip()
    if cur:
        cases.append(cur)
    return cases

def field(c, *names):
    for n in names:
        if n in c:
            return c[n]
    return ""

cases = parse_kat(KAT)
print(f"Loaded {len(cases)} official KAT cases from {KAT}")

checked = 0
for c in cases:
    if "Count" not in c:
        continue

    count = int(c["Count"])
    key = field(c, "Key", "K")
    nonce = field(c, "Nonce", "N", "NPub")
    ad = field(c, "AD", "Adata", "Associated Data")
    pt = field(c, "PT", "Msg", "Message")
    exp = field(c, "CT", "C", "Ciphertext")

    got = subprocess.check_output(
        [str(CLI), "enc", key, nonce, ad, pt],
        text=True
    ).strip()

    if got.lower() != exp.lower():
        print(f"FAIL Count={count}")
        print(f"  AD_len={len(ad)//2} PT_len={len(pt)//2}")
        print(f"  got={got}")
        print(f"  exp={exp}")
        sys.exit(1)

    checked += 1

print(f"PASS official C ASCON-AEAD128 ref matches KAT: {checked} cases")
