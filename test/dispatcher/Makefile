SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v \
                  $(SRC_DIR)/hash_controller.v $(SRC_DIR)/xof_controller.v \
                  $(SRC_DIR)/cxof_controller.v $(SRC_DIR)/mode_controller.v
VERILOG_SOURCES += $(PWD)/tb_dispatcher.v
TOPLEVEL = tb_dispatcher
COCOTB_TEST_MODULES = test_dispatcher
include $(shell cocotb-config --makefiles)/Makefile.sim
