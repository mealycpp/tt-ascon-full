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


ifeq ($(TEST),bridge)
VERILOG_SOURCES = $(SRC_DIR)/uart_rx.v $(SRC_DIR)/uart_tx.v $(SRC_DIR)/baud_gen.v \
                  $(SRC_DIR)/byte_fifo.v $(SRC_DIR)/byte_to_word_packer.v \
                  $(SRC_DIR)/word_to_byte_unpacker.v $(SRC_DIR)/uart_bridge.v \
                  $(PWD)/tb_uart_bridge.v
TOPLEVEL = tb_uart_bridge
COCOTB_TEST_MODULES = test_uart_bridge
endif


ifeq ($(TEST),parser)
VERILOG_SOURCES = $(SRC_DIR)/protocol_parser.v $(PWD)/tb_protocol_parser.v
TOPLEVEL = tb_protocol_parser
COCOTB_TEST_MODULES = test_protocol_parser
endif

include $(shell cocotb-config --makefiles)/Makefile.sim
