SIM ?= icarus
TOPLEVEL_LANG = verilog

REPO_ROOT := $(shell cd ../.. && pwd)

TOPLEVEL = tt_um_mealycpp_ascon_sdmc_uart
COCOTB_TEST_MODULES = test_anubis_aead

COMPILE_ARGS += -g2012
COMPILE_ARGS += -I$(REPO_ROOT)
COMPILE_ARGS += -I$(REPO_ROOT)/src
COMPILE_ARGS += -I$(REPO_ROOT)/src/sdmc

VERILOG_SOURCES += $(REPO_ROOT)/src/uart_rx.v
VERILOG_SOURCES += $(REPO_ROOT)/src/uart_tx.v
VERILOG_SOURCES += $(REPO_ROOT)/src/ascon_round.v
VERILOG_SOURCES += $(REPO_ROOT)/src/ascon_permutation.v
VERILOG_SOURCES += $(REPO_ROOT)/src/sdmc/sdmc_ascon_perm_unit64.v
VERILOG_SOURCES += $(REPO_ROOT)/src/sdmc/sdmc_hash256_core.v
VERILOG_SOURCES += $(REPO_ROOT)/src/sdmc/sdmc_hash_family_shell.v
VERILOG_SOURCES += $(REPO_ROOT)/src/sdmc/sdmc_xof_family_core.v
VERILOG_SOURCES += $(REPO_ROOT)/src/sdmc/sdmc_xof_chain_family_core.v
VERILOG_SOURCES += $(REPO_ROOT)/src/sdmc/sdmc_aead128_core.v
VERILOG_SOURCES += $(REPO_ROOT)/src/sdmc/sdmc_aead_uart_frontend.v
VERILOG_SOURCES += $(REPO_ROOT)/src/project_sdmc_uart_top.v

WAVES ?= 1

include $(shell cocotb-config --makefiles)/Makefile.sim
