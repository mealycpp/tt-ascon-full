#!/usr/bin/env python3
import json
from pathlib import Path
from datetime import datetime

cfg = Path("src/config.json")
if not cfg.exists():
    raise SystemExit("ERROR: src/config.json not found")

import sys
if len(sys.argv) != 2:
    raise SystemExit("Usage: tools/set_sdmc_clock.py <30|45|50>")

mhz = float(sys.argv[1])
period = 1000.0 / mhz

backup = cfg.with_suffix(cfg.suffix + ".bak_clock_" + datetime.now().strftime("%Y%m%d_%H%M%S"))
backup.write_text(cfg.read_text())

data = json.loads(cfg.read_text())
data["CLOCK_PERIOD"] = f"{period:.3f}"
cfg.write_text(json.dumps(data, indent=2) + "\n")

print(f"Set CLOCK_PERIOD={period:.3f} ns for {mhz:.1f} MHz")
print(f"Backup: {backup}")
