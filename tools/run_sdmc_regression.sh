#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

mkdir -p reports

run_one() {
  name="$1"
  out="$2"
  shift 2

  echo
  echo "=== $name ==="
  iverilog -g2012 -I src/sdmc -o "$out" "$@"
  vvp "$out" | tee "reports/${name}.log"
  grep -q "PASS ${name}" "reports/${name}.log"
  rm -f "$out"
}

run_one ascon_perm_round_window /tmp/ascon_perm_round_window.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  test/ascon_perm_round_window/tb_ascon_perm_round_window.v

run_one sdmc_crypto_helpers /tmp/sdmc_crypto_helpers.vvp \
  src/sdmc/sdmc_crypto_helpers.v \
  test/sdmc_crypto_helpers/tb_sdmc_crypto_helpers.v

run_one sdmc_hash256_core_empty /tmp/sdmc_hash256_core_empty.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_hash256_core.v \
  test/sdmc_hash256_core_empty/tb_sdmc_hash256_core_empty.v

run_one sdmc_hash256_core_msg /tmp/sdmc_hash256_core_msg.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_hash256_core.v \
  test/sdmc_hash256_core_msg/tb_sdmc_hash256_core_msg.v

run_one sdmc_xof_family_core_64 /tmp/sdmc_xof_family_core_64.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_xof_family_core.v \
  test/sdmc_xof_family_core_64/tb_sdmc_xof_family_core_64.v

run_one sdmc_xof_family_core_cxof /tmp/sdmc_xof_family_core_cxof.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_xof_family_core.v \
  test/sdmc_xof_family_core_cxof/tb_sdmc_xof_family_core_cxof.v

run_one sdmc_xof_chain_family_core /tmp/sdmc_xof_chain_family_core.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_xof_family_core.v \
  src/sdmc/sdmc_xof_chain_family_core.v \
  test/sdmc_xof_chain_family_core/tb_sdmc_xof_chain_family_core.v

run_one sdmc_cxof_chain_family_core_full /tmp/sdmc_cxof_chain_family_core_full.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_xof_family_core.v \
  src/sdmc/sdmc_xof_chain_family_core.v \
  test/sdmc_cxof_chain_family_core_full/tb_sdmc_cxof_chain_family_core_full.v

run_one sdmc_aead128_empty /tmp/sdmc_aead128_empty.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_empty/tb_sdmc_aead128_empty.v

run_one sdmc_aead128_ad1 /tmp/sdmc_aead128_ad1.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad1/tb_sdmc_aead128_ad1.v

run_one sdmc_aead128_ad2 /tmp/sdmc_aead128_ad2.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad2/tb_sdmc_aead128_ad2.v

run_one sdmc_aead128_ad3 /tmp/sdmc_aead128_ad3.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad3/tb_sdmc_aead128_ad3.v

run_one sdmc_aead128_ad4 /tmp/sdmc_aead128_ad4.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad4/tb_sdmc_aead128_ad4.v

run_one sdmc_aead128_ad5 /tmp/sdmc_aead128_ad5.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad5/tb_sdmc_aead128_ad5.v

run_one sdmc_aead128_ad6 /tmp/sdmc_aead128_ad6.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad6/tb_sdmc_aead128_ad6.v

run_one sdmc_aead128_ad7 /tmp/sdmc_aead128_ad7.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad7/tb_sdmc_aead128_ad7.v

run_one sdmc_aead128_pt1 /tmp/sdmc_aead128_pt1.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt1/tb_sdmc_aead128_pt1.v

run_one sdmc_aead128_pt2 /tmp/sdmc_aead128_pt2.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt2/tb_sdmc_aead128_pt2.v

run_one sdmc_aead128_pt3 /tmp/sdmc_aead128_pt3.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt3/tb_sdmc_aead128_pt3.v

run_one sdmc_aead128_pt4 /tmp/sdmc_aead128_pt4.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt4/tb_sdmc_aead128_pt4.v

run_one sdmc_aead128_pt5 /tmp/sdmc_aead128_pt5.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt5/tb_sdmc_aead128_pt5.v

run_one sdmc_aead128_pt6 /tmp/sdmc_aead128_pt6.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt6/tb_sdmc_aead128_pt6.v

run_one sdmc_aead128_pt7 /tmp/sdmc_aead128_pt7.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt7/tb_sdmc_aead128_pt7.v

run_one sdmc_aead128_ad8 /tmp/sdmc_aead128_ad8.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_ad8/tb_sdmc_aead128_ad8.v

run_one sdmc_aead128_pt8 /tmp/sdmc_aead128_pt8.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_pt8/tb_sdmc_aead128_pt8.v

run_one sdmc_aead128_abc /tmp/sdmc_aead128_abc.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_abc/tb_sdmc_aead128_abc.v

run_one sdmc_aead128_dec_abc /tmp/sdmc_aead128_dec_abc.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_aead128_core.v \
  test/sdmc_aead128_dec_abc/tb_sdmc_aead128_dec_abc.v

run_one sdmc_crypto_top_hash_empty /tmp/sdmc_crypto_top_hash_empty.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_fifo.v \
  src/sdmc/sdmc_token_fifo.v \
  src/sdmc/sdmc_stream_ingress.v \
  src/sdmc/sdmc_stream_egress.v \
  src/sdmc/sdmc_stream_shell.v \
  src/sdmc/sdmc_config_regs.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_hash256_core.v \
  src/sdmc/sdmc_xof_family_core.v \
  src/sdmc/sdmc_xof_chain_family_core.v \
  src/sdmc/sdmc_aead128_core.v \
  src/sdmc/sdmc_crypto_top.v \
  test/sdmc_crypto_top_hash_empty/tb_sdmc_crypto_top_hash_empty.v

run_one sdmc_crypto_top_hash_abc /tmp/sdmc_crypto_top_hash_abc.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_fifo.v \
  src/sdmc/sdmc_token_fifo.v \
  src/sdmc/sdmc_stream_ingress.v \
  src/sdmc/sdmc_stream_egress.v \
  src/sdmc/sdmc_stream_shell.v \
  src/sdmc/sdmc_config_regs.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_hash256_core.v \
  src/sdmc/sdmc_xof_family_core.v \
  src/sdmc/sdmc_xof_chain_family_core.v \
  src/sdmc/sdmc_aead128_core.v \
  src/sdmc/sdmc_crypto_top.v \
  test/sdmc_crypto_top_hash_abc/tb_sdmc_crypto_top_hash_abc.v

run_one sdmc_crypto_top_xof_abc /tmp/sdmc_crypto_top_xof_abc.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_fifo.v \
  src/sdmc/sdmc_token_fifo.v \
  src/sdmc/sdmc_stream_ingress.v \
  src/sdmc/sdmc_stream_egress.v \
  src/sdmc/sdmc_stream_shell.v \
  src/sdmc/sdmc_config_regs.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_hash256_core.v \
  src/sdmc/sdmc_xof_family_core.v \
  src/sdmc/sdmc_xof_chain_family_core.v \
  src/sdmc/sdmc_aead128_core.v \
  src/sdmc/sdmc_crypto_top.v \
  test/sdmc_crypto_top_xof_abc/tb_sdmc_crypto_top_xof_abc.v

run_one sdmc_crypto_top_aead_abc /tmp/sdmc_crypto_top_aead_abc.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_fifo.v \
  src/sdmc/sdmc_token_fifo.v \
  src/sdmc/sdmc_stream_ingress.v \
  src/sdmc/sdmc_stream_egress.v \
  src/sdmc/sdmc_stream_shell.v \
  src/sdmc/sdmc_config_regs.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_hash256_core.v \
  src/sdmc/sdmc_xof_family_core.v \
  src/sdmc/sdmc_xof_chain_family_core.v \
  src/sdmc/sdmc_aead128_core.v \
  src/sdmc/sdmc_crypto_top.v \
  test/sdmc_crypto_top_aead_abc/tb_sdmc_crypto_top_aead_abc.v

run_one sdmc_xof_family_core_empty /tmp/sdmc_xof_family_core_empty.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_xof_family_core.v \
  test/sdmc_xof_family_core_empty/tb_sdmc_xof_family_core_empty.v

run_one sdmc_xof_family_core_msg /tmp/sdmc_xof_family_core_msg.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_xof_family_core.v \
  test/sdmc_xof_family_core_msg/tb_sdmc_xof_family_core_msg.v

run_one sdmc_hash_family_shell /tmp/sdmc_hash_family_shell.vvp \
  src/sdmc/sdmc_stream_ingress.v \
  src/sdmc/sdmc_stream_egress.v \
  src/sdmc/sdmc_token_fifo.v \
  src/sdmc/sdmc_stream_shell.v \
  src/sdmc/sdmc_hash_family_shell.v \
  test/sdmc_hash_family_shell/tb_sdmc_hash_family_shell.v

run_one sdmc_stream_shell /tmp/sdmc_stream_shell.vvp \
  src/sdmc/sdmc_stream_ingress.v \
  src/sdmc/sdmc_stream_egress.v \
  src/sdmc/sdmc_token_fifo.v \
  src/sdmc/sdmc_stream_shell.v \
  test/sdmc_stream_shell/tb_sdmc_stream_shell.v

run_one sdmc_stream_egress /tmp/sdmc_stream_egress.vvp \
  src/sdmc/sdmc_stream_egress.v \
  test/sdmc_stream_egress/tb_sdmc_stream_egress.v

run_one sdmc_token_fifo /tmp/sdmc_token_fifo.vvp \
  src/sdmc/sdmc_token_fifo.v \
  test/sdmc_token_fifo/tb_sdmc_token_fifo.v

run_one sdmc_config_regs /tmp/sdmc_config_regs.vvp \
  src/sdmc/sdmc_config_regs.v \
  test/sdmc_config_regs/tb_sdmc_config_regs.v

run_one sdmc_fifo /tmp/sdmc_fifo.vvp \
  src/sdmc/sdmc_fifo.v \
  test/sdmc_fifo/tb_sdmc_fifo.v

run_one sdmc_word_io /tmp/sdmc_word_io.vvp \
  src/sdmc/sdmc_byte_to_word.v \
  src/sdmc/sdmc_word_to_byte.v \
  test/sdmc_word_io/tb_sdmc_word_io.v

run_one sdmc_word_alu64 /tmp/sdmc_word_alu64.vvp \
  src/sdmc/sdmc_word_alu64.v \
  test/sdmc_word_alu64/tb_sdmc_word_alu64.v

run_one sdmc_regfile64 /tmp/sdmc_regfile64.vvp \
  src/sdmc/sdmc_regfile64.v \
  test/sdmc_regfile64/tb_sdmc_regfile64.v

run_one sdmc_uop_exec64 /tmp/sdmc_uop_exec64.vvp \
  src/sdmc/sdmc_regfile64.v \
  src/sdmc/sdmc_word_alu64.v \
  src/sdmc/sdmc_uop_exec64.v \
  test/sdmc_uop_exec64/tb_sdmc_uop_exec64.v

run_one sdmc_perm_unit64 /tmp/sdmc_perm_unit64.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  test/sdmc_perm_unit64/tb_sdmc_perm_unit64.v

run_one sdmc_uop_exec64p /tmp/sdmc_uop_exec64p.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_regfile64.v \
  src/sdmc/sdmc_word_alu64.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_uop_exec64p.v \
  test/sdmc_uop_exec64p/tb_sdmc_uop_exec64p.v

run_one sdmc_uop_sequencer64p /tmp/sdmc_uop_sequencer64p.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_regfile64.v \
  src/sdmc/sdmc_word_alu64.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_uop_exec64p.v \
  src/sdmc/sdmc_uop_sequencer64p.v \
  test/sdmc_uop_sequencer64p/tb_sdmc_uop_sequencer64p.v

run_one sdmc_engine64p /tmp/sdmc_engine64p.vvp \
  src/ascon_round.v \
  src/ascon_permutation.v \
  src/sdmc/sdmc_config_regs.v \
  src/sdmc/sdmc_regfile64.v \
  src/sdmc/sdmc_word_alu64.v \
  src/sdmc/sdmc_ascon_perm_unit64.v \
  src/sdmc/sdmc_uop_exec64p.v \
  src/sdmc/sdmc_uop_sequencer64p.v \
  src/sdmc/sdmc_engine64p.v \
  test/sdmc_engine64p/tb_sdmc_engine64p.v

echo
echo "PASS sdmc_regression"
