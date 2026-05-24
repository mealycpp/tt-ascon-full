`default_nettype none
`timescale 1ns/1ps
module tb_protocol_parser ();
  initial begin
    $dumpfile("tb_protocol_parser.fst");
    $dumpvars(0, tb_protocol_parser);
  end
  reg clk; reg rst_n;
  reg [7:0] in_byte;
  reg       in_byte_valid;
  wire      in_byte_ready;
  wire [2:0]  mode_sel;
  wire        is_decrypt;
  wire        chain_enable;
  wire        chain_debug;
  wire [15:0] ad_total_bytes;
  wire [15:0] data_total_bytes;
  wire [15:0] out_length;
  wire [15:0] chain_count;
  wire [15:0] cs_total_bits;
  wire        frame_valid;
  wire        frame_error;
  wire        start;
  protocol_parser dut (
    .clk(clk), .rst_n(rst_n),
    .in_byte(in_byte), .in_byte_valid(in_byte_valid), .in_byte_ready(in_byte_ready),
    .mode_sel(mode_sel), .is_decrypt(is_decrypt),
    .chain_enable(chain_enable), .chain_debug(chain_debug),
    .ad_total_bytes(ad_total_bytes), .data_total_bytes(data_total_bytes),
    .out_length(out_length), .chain_count(chain_count),
    .cs_total_bits(cs_total_bits),
    .frame_valid(frame_valid), .frame_error(frame_error), .start(start)
  );
endmodule
