SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src
VERILOG_SOURCES = $(SRC_DIR)/project.v \
                  $(SRC_DIR)/uart_bridge.v \
                  $(SRC_DIR)/byte_fifo.v \
                  $(SRC_DIR)/byte_to_word_packer.v \
                  $(SRC_DIR)/word_to_byte_unpacker.v \
                  $(SRC_DIR)/uart_rx.v $(SRC_DIR)/uart_tx.v $(SRC_DIR)/baud_gen.v \
                  $(SRC_DIR)/protocol_parser.v $(SRC_DIR)/lane_router.v \
                  $(SRC_DIR)/mode_controller.v \
                  $(SRC_DIR)/hash_controller.v $(SRC_DIR)/hash_patch_controller.v $(SRC_DIR)/xof_patch_controller.v $(SRC_DIR)/cxof_patch_controller.v $(SRC_DIR)/ascon_sponge_core.v $(SRC_DIR)/xof_controller.v \
                  $(SRC_DIR)/cxof_controller.v $(SRC_DIR)/aead_controller.v \
                  $(SRC_DIR)/ascon_permutation.v $(SRC_DIR)/ascon_round.v \
                  $(PWD)/tb_project.v
TOPLEVEL = tb_project
COCOTB_TEST_MODULES = test_project_smoke
include $(shell cocotb-config --makefiles)/Makefile.sim
