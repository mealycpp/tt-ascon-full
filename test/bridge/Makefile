SIM ?= icarus
TOPLEVEL_LANG ?= verilog
SRC_DIR = $(PWD)/../../src

ifeq ($(TEST),fifo)
VERILOG_SOURCES = $(SRC_DIR)/byte_fifo.v $(PWD)/tb_byte_fifo.v
TOPLEVEL = tb_byte_fifo
COCOTB_TEST_MODULES = test_byte_fifo
endif

ifeq ($(TEST),packer)
VERILOG_SOURCES = $(SRC_DIR)/byte_to_word_packer.v $(PWD)/tb_packer.v
TOPLEVEL = tb_packer
COCOTB_TEST_MODULES = test_packer
endif

ifeq ($(TEST),unpacker)
VERILOG_SOURCES = $(SRC_DIR)/word_to_byte_unpacker.v $(PWD)/tb_unpacker.v
TOPLEVEL = tb_unpacker
COCOTB_TEST_MODULES = test_unpacker
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
