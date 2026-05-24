SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v $(SRC_DIR)/xof_controller.v
VERILOG_SOURCES += $(PWD)/tb_xof.v
TOPLEVEL = tb_xof
COCOTB_TEST_MODULES = test_xof
include $(shell cocotb-config --makefiles)/Makefile.sim
