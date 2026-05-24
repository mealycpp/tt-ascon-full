`default_nettype none
`timescale 1ns/1ps
module tb_uart_bridge ();
  initial begin
    $dumpfile("tb_uart_bridge.fst");
    $dumpvars(0, tb_uart_bridge);
  end
  reg clk;
  reg rst_n;
  reg [15:0] baud_div;
  reg uart0_rx, uart1_rx, uart2_rx;
  wire uart0_tx, uart1_tx, uart2_tx;
  reg [1:0] phase_sel;
  reg [2:0] flush;
  wire [2:0] flush_ready;
  wire [63:0] sdmc_in_word;
  wire [3:0]  sdmc_in_word_bytes;
  wire        sdmc_in_word_valid;
  reg         sdmc_in_word_ready;
  reg [1:0]   tx_sel;
  reg [63:0]  sdmc_out_block;
  reg [3:0]   sdmc_out_byte_count;
  reg         sdmc_out_valid;
  wire        sdmc_out_ready;
  wire [2:0]  rx_fifo_empty, rx_fifo_full;
  wire [2:0]  tx_fifo_empty, tx_fifo_full;

  uart_bridge #(.FIFO_DEPTH(16), .FIFO_AW(4)) dut (
    .clk(clk), .rst_n(rst_n),
    .baud_div(baud_div),
    .uart0_rx(uart0_rx), .uart1_rx(uart1_rx), .uart2_rx(uart2_rx),
    .uart0_tx(uart0_tx), .uart1_tx(uart1_tx), .uart2_tx(uart2_tx),
    .phase_sel(phase_sel),
    .flush(flush), .flush_ready(flush_ready),
    .sdmc_in_word(sdmc_in_word), .sdmc_in_word_bytes(sdmc_in_word_bytes),
    .sdmc_in_word_valid(sdmc_in_word_valid),
    .sdmc_in_word_ready(sdmc_in_word_ready),
    .tx_sel(tx_sel),
    .sdmc_out_block(sdmc_out_block),
    .sdmc_out_byte_count(sdmc_out_byte_count),
    .sdmc_out_valid(sdmc_out_valid),
    .sdmc_out_ready(sdmc_out_ready),
    .rx_fifo_empty(rx_fifo_empty), .rx_fifo_full(rx_fifo_full),
    .tx_fifo_empty(tx_fifo_empty), .tx_fifo_full(tx_fifo_full)
  );
endmodule
