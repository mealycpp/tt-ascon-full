#!/usr/bin/env python3
import os
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
AUDIT = ROOT / "tools" / "sdmc_gds_risk_audit.py"

USE_COLOR = sys.stdout.isatty() and os.environ.get("NO_COLOR", "") == ""

def color(text, code):
    if not USE_COLOR:
        return text
    return f"\033[{code}m{text}\033[0m"

GREEN = "32"
RED = "31"
YELLOW = "33"
BOLD = "1"

def status_text(status):
    if status == "PASS":
        return color("PASS", GREEN)
    if status == "FAIL":
        return color("FAIL", RED)
    if status == "WARN":
        return color("WARN", YELLOW)
    return status

def table(rows):
    headers = ("Check", "Status", "Detail")
    all_rows = [headers] + rows
    widths = [
        max(len(str(r[i])) for r in all_rows)
        for i in range(3)
    ]

    def plain_len(s):
        return len(re.sub(r"\033\[[0-9;]*m", "", str(s)))

    def pad(s, width):
        s = str(s)
        return s + " " * (width - plain_len(s))

    sep = "+" + "+".join("-" * (w + 2) for w in widths) + "+"

    print()
    print(color("=== SDMC GDS RISK AUDIT SUMMARY ===", BOLD))
    print(sep)
    print("| " + " | ".join(pad(headers[i], widths[i]) for i in range(3)) + " |")
    print(sep)
    for r in rows:
        print("| " + " | ".join(pad(r[i], widths[i]) for i in range(3)) + " |")
    print(sep)

def main():
    proc = subprocess.run(
        [sys.executable, str(AUDIT)],
        cwd=str(ROOT),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
    )

    output = proc.stdout
    print(output, end="" if output.endswith("\n") else "\n")

    lines = output.splitlines()

    files = []
    in_files = False
    warnings = []
    failures = []

    for line in lines:
        stripped = line.strip()

        if stripped == "Files audited:":
            in_files = True
            continue

        if in_files:
            if stripped == "":
                in_files = False
            elif stripped.startswith("src/"):
                files.append(stripped)

        if stripped.startswith("WARN:"):
            warnings.append(stripped)

        if stripped.startswith("FAIL:"):
            failures.append(stripped)

    overall_pass = (proc.returncode == 0) and not failures and any(
        "PASS sdmc_gds_risk_audit" in line for line in lines
    )

    rows = [
        ("Files audited", status_text("PASS" if files else "WARN"), f"{len(files)} files"),
        ("Warnings", status_text("PASS" if len(warnings) == 0 else "WARN"), f"{len(warnings)} warning(s)"),
        ("Failures", status_text("PASS" if len(failures) == 0 else "FAIL"), f"{len(failures)} failure(s)"),
        ("Overall audit", status_text("PASS" if overall_pass else "FAIL"), "ready for GDS gate" if overall_pass else "fix required"),
    ]

    table(rows)

    if warnings:
        print()
        print(color("Warnings:", YELLOW))
        for w in warnings:
            print(f"  - {w}")

    if failures:
        print()
        print(color("Failures:", RED))
        for f in failures:
            print(f"  - {f}")

    return 0 if overall_pass else 1

if __name__ == "__main__":
    raise SystemExit(main())
