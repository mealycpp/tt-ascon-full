SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v $(SRC_DIR)/cxof_controller.v
VERILOG_SOURCES += $(PWD)/tb_cxof.v
TOPLEVEL = tb_cxof
COCOTB_TEST_MODULES = test_cxof
include $(shell cocotb-config --makefiles)/Makefile.sim
