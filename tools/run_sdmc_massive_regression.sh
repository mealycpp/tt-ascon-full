#!/usr/bin/env bash
set -euo pipefail

mkdir -p reports

echo "=== SDMC MASSIVE REGRESSION ==="

echo
echo "=== sdmc_uart_top_syntax ==="
./tools/check_sdmc_uart_top_syntax.sh

echo
echo "=== sdmc_crypto_top_syntax preserved full top ==="
./tools/check_sdmc_crypto_top_syntax.sh

echo
echo "=== sdmc_regression preserved cores ==="
./tools/run_sdmc_regression.sh | tee reports/sdmc_massive_regression_core.log

echo
echo "=== sdmc_chain_vector_regression ==="
./tools/run_sdmc_chain_vector_regression.sh | tee reports/sdmc_massive_chain_vector_regression.log

echo
echo "=== sdmc_aead_official_matrix preserved ==="
./tools/run_sdmc_aead_official_matrix.sh | tee reports/sdmc_massive_aead_official_matrix.log

echo
echo "=== sdmc_uart_smoke shared-HX GDS top ==="
./tools/run_sdmc_uart_smoke.sh | tee reports/sdmc_massive_uart_smoke.log

echo
echo "=== sdmc_gds_filelist_audit ==="
./tools/check_sdmc_gds_filelist.sh | tee reports/sdmc_massive_gds_filelist_audit.log

echo
echo "=== sdmc_gds_risk_audit ==="
python3 tools/sdmc_gds_risk_audit_pretty.py | tee reports/sdmc_massive_gds_risk_audit.txt

echo
echo "PASS sdmc_massive_regression"
