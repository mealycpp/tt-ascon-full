# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

TOPLEVEL_LANG ?= verilog
SIM ?= icarus

PWD := $(shell pwd)

TOPLEVEL = tb
MODULE = test

# Needed because SDMC files include "src/sdmc/..."
COMPILE_ARGS += -I$(PWD)/.. -I$(PWD)/../src -I$(PWD)/../src/sdmc

VERILOG_SOURCES = \
  $(PWD)/../src/ascon_round.v \
  $(PWD)/../src/ascon_permutation.v \
  $(PWD)/../src/uart_rx.v \
  $(PWD)/../src/uart_tx.v \
  $(PWD)/../src/sdmc/sdmc_aead_uart_frontend.v \
  $(PWD)/../src/sdmc/sdmc_aead128_core.v \
  $(PWD)/../src/sdmc/sdmc_ascon_perm_unit64.v \
  $(PWD)/../src/sdmc/sdmc_crypto_helpers.v \
  $(PWD)/../src/project_sdmc_uart_top.v \
  $(PWD)/tb.v

include $(shell cocotb-config --makefiles)/Makefile.sim
