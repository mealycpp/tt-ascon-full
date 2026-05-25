SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v \
                  $(SRC_DIR)/hash_controller.v $(SRC_DIR)/hash_patch_controller.v $(SRC_DIR)/xof_patch_controller.v $(SRC_DIR)/cxof_patch_controller.v $(SRC_DIR)/aead_patch_controller.v $(SRC_DIR)/ascon_sponge_core.v $(SRC_DIR)/xof_controller.v \
                  $(SRC_DIR)/cxof_controller.v $(SRC_DIR)/aead_controller.v $(SRC_DIR)/mode_controller.v
VERILOG_SOURCES += $(PWD)/tb_dispatcher.v
TOPLEVEL = tb_dispatcher
COCOTB_TEST_MODULES = test_dispatcher
include $(shell cocotb-config --makefiles)/Makefile.sim
