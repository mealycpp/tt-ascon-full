`default_nettype none
`timescale 1ns/1ps

module tb_dispatcher ();
  initial begin
    $dumpfile("tb_dispatcher.fst");
    $dumpvars(0, tb_dispatcher);
  end

  reg clk;
  reg rst_n;
  reg [2:0] mode_sel;
  reg start;
  reg reset_engine;
  reg [15:0] cs_total_bits;
  reg [15:0] msg_total_bytes;
  reg [15:0] out_length;
  reg        chain_enable;
  reg [15:0] chain_count;
  reg        chain_debug;

  reg  [63:0] in_word;
  reg  [3:0]  in_word_bytes;
  reg         in_word_last;
  reg         in_word_is_cs;
  reg         in_word_valid;
  wire        in_word_ready;

  wire [63:0] out_block;
  wire        out_valid;
  wire        out_last;
  wire [3:0]  out_byte_count;
  wire        busy, done;

  mode_controller dut (
    .clk(clk), .rst_n(rst_n),
    .mode_sel(mode_sel), .start(start), .reset_engine(reset_engine),
    .cs_total_bits(cs_total_bits),
    .msg_total_bytes(msg_total_bytes),
    .out_length(out_length),
    .chain_enable(chain_enable), .chain_count(chain_count),
    .chain_debug(chain_debug),
    .in_word(in_word), .in_word_bytes(in_word_bytes),
    .in_word_last(in_word_last), .in_word_is_cs(in_word_is_cs),
    .in_word_valid(in_word_valid), .in_word_ready(in_word_ready),
    .out_block(out_block), .out_valid(out_valid),
    .out_last(out_last), .out_byte_count(out_byte_count),
    .busy(busy), .done(done)
  );
endmodule
