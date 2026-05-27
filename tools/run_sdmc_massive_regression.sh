#!/usr/bin/env bash
set -euo pipefail

mkdir -p reports

echo "=== SDMC MASSIVE REGRESSION ==="
./tools/run_sdmc_regression.sh | tee reports/sdmc_massive_regression.log

echo
echo "=== SDMC PRETTY GDS RISK AUDIT ==="
python3 tools/sdmc_gds_risk_audit_pretty.py | tee reports/sdmc_massive_gds_risk_audit.txt

echo
echo "PASS sdmc_massive_regression"
