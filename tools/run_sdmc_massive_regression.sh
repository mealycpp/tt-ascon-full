
echo
echo "=== sdmc_crypto_top_syntax ==="
./tools/check_sdmc_crypto_top_syntax.sh

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

echo
echo "=== sdmc_chain_vector_regression ==="
./tools/run_sdmc_chain_vector_regression.sh

echo
echo "=== sdmc_aead_official_matrix ==="
./tools/run_sdmc_aead_official_matrix.sh

