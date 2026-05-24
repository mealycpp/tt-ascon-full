`default_nettype none
`timescale 1ns/1ps
module tb_packer ();
  initial begin
    $dumpfile("tb_packer.fst");
    $dumpvars(0, tb_packer);
  end
  reg clk; reg rst_n;
  reg [7:0] in_byte;
  reg in_byte_valid;
  wire in_byte_ready;
  reg flush;
  wire flush_ready;
  wire [63:0] out_word;
  wire [3:0]  out_word_bytes;
  wire        out_word_valid;
  reg         out_word_ready;
  byte_to_word_packer dut (
    .clk(clk), .rst_n(rst_n),
    .in_byte(in_byte), .in_byte_valid(in_byte_valid),
    .in_byte_ready(in_byte_ready), .flush(flush), .flush_ready(flush_ready),
    .out_word(out_word), .out_word_bytes(out_word_bytes),
    .out_word_valid(out_word_valid), .out_word_ready(out_word_ready)
  );
endmodule
