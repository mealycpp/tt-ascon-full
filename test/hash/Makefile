SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v $(SRC_DIR)/hash_controller.v
VERILOG_SOURCES += $(PWD)/tb_hash.v
TOPLEVEL = tb_hash
COCOTB_TEST_MODULES = test_hash
include $(shell cocotb-config --makefiles)/Makefile.sim
