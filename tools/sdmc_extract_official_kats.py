#!/usr/bin/env python3
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KAT = ROOT / "kat" / "official" / "ascon-c"
OUT = ROOT / "kat" / "derived" / "sdmc_official_subset.json"

FILES = {
    "aead128": KAT / "asconaead128_LWC_AEAD_KAT_128_128.txt",
    "hash256": KAT / "asconhash256_LWC_HASH_KAT_128_256.txt",
    "xof128": KAT / "asconxof128_LWC_XOF_KAT_128_512.txt",
    "cxof128": KAT / "asconcxof128_LWC_CXOF_KAT_128_512.txt",
}

def parse_lwc(path):
    cases = []
    cur = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            if cur:
                cases.append(cur)
                cur = {}
            continue
        if "=" not in line:
            continue
        k, v = [x.strip() for x in line.split("=", 1)]
        cur[k] = v
    if cur:
        cases.append(cur)
    return cases

def pick_counts(cases, counts):
    wanted = set(str(c) for c in counts)
    out = []
    for c in cases:
        if c.get("Count") in wanted:
            out.append(c)
    return out

def main():
    data = {}

    aead = parse_lwc(FILES["aead128"])
    h = parse_lwc(FILES["hash256"])
    x = parse_lwc(FILES["xof128"])
    c = parse_lwc(FILES["cxof128"])

    # Initial official subset:
    # AEAD: empty, AD-only small cases, and first PT cases will be expanded later.
    data["aead128"] = pick_counts(aead, [1, 2, 3, 4, 5, 17, 18, 19, 20])

    # HASH: empty, short, boundary-ish first 20.
    data["hash256"] = pick_counts(h, list(range(1, 21)))

    # XOF: empty and first 20, each MD is 64 bytes in the official file.
    data["xof128"] = pick_counts(x, list(range(1, 21)))

    # CXOF: first 20, mostly Z/customization coverage with empty Msg.
    data["cxof128"] = pick_counts(c, list(range(1, 21)))

    OUT.parent.mkdir(parents=True, exist_ok=True)
    OUT.write_text(json.dumps(data, indent=2) + "\n")

    print(f"Wrote {OUT}")
    for family, cases in data.items():
        print(f"{family}: {len(cases)} cases")
        for c0 in cases[:3]:
            print(f"  Count={c0.get('Count')} keys={','.join(k for k in c0.keys() if k != 'Count')}")

if __name__ == "__main__":
    main()
