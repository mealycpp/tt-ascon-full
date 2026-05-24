SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v
VERILOG_SOURCES += $(PWD)/tb_perm.v
TOPLEVEL = tb_perm
COCOTB_TEST_MODULES = test_perm
include $(shell cocotb-config --makefiles)/Makefile.sim
