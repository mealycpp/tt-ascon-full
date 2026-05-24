`default_nettype none
`timescale 1ns/1ps
module tb_unpacker ();
  initial begin
    $dumpfile("tb_unpacker.fst");
    $dumpvars(0, tb_unpacker);
  end
  reg clk; reg rst_n;
  reg [63:0] in_word;
  reg [3:0]  in_word_bytes;
  reg        in_word_valid;
  wire       in_word_ready;
  wire [7:0] out_byte;
  wire       out_byte_valid;
  reg        out_byte_ready;
  word_to_byte_unpacker dut (
    .clk(clk), .rst_n(rst_n),
    .in_word(in_word), .in_word_bytes(in_word_bytes),
    .in_word_valid(in_word_valid), .in_word_ready(in_word_ready),
    .out_byte(out_byte), .out_byte_valid(out_byte_valid),
    .out_byte_ready(out_byte_ready)
  );
endmodule
