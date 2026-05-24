`default_nettype none
`timescale 1ns/1ps
module tb_byte_fifo ();
  initial begin
    $dumpfile("tb_byte_fifo.fst");
    $dumpvars(0, tb_byte_fifo);
  end
  reg clk; reg rst_n;
  reg wr_en; reg [7:0] wr_data; wire full;
  reg rd_en; wire [7:0] rd_data; wire empty;
  wire [4:0] count;
  byte_fifo #(.DEPTH(16), .AW(4)) dut (
    .clk(clk), .rst_n(rst_n),
    .wr_en(wr_en), .wr_data(wr_data), .full(full),
    .rd_en(rd_en), .rd_data(rd_data), .empty(empty),
    .count(count)
  );
endmodule
