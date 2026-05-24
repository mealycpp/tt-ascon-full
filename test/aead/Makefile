SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v \
                  $(SRC_DIR)/aead_controller.v
VERILOG_SOURCES += $(PWD)/tb_aead.v
TOPLEVEL = tb_aead
COCOTB_TEST_MODULES = test_aead
include $(shell cocotb-config --makefiles)/Makefile.sim
