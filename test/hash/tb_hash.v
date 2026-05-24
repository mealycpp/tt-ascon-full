`default_nettype none
`timescale 1ns/1ps

module tb_hash ();
  initial begin
    $dumpfile("tb_hash.fst");
    $dumpvars(0, tb_hash);
  end

  reg clk;
  reg rst_n;
  reg start;
  reg reset_engine;
  reg [15:0] msg_total_bytes;

  reg  [63:0] in_word;
  reg  [3:0]  in_word_bytes;
  reg         in_word_last;
  reg         in_word_valid;
  wire        in_word_ready;

  wire [63:0] out_block;
  wire        out_valid;
  wire        out_last;
  wire [3:0]  out_byte_count;
  wire        busy, done;

  wire        perm_start;
  wire [3:0]  perm_rounds;
  wire [319:0] perm_state_in;
  wire [319:0] perm_state_out;
  wire perm_busy, perm_done;

  hash_controller dut (
    .clk(clk), .rst_n(rst_n),
    .start(start), .reset_engine(reset_engine),
    .msg_total_bytes(msg_total_bytes),
    .in_word(in_word), .in_word_bytes(in_word_bytes),
    .in_word_last(in_word_last), .in_word_valid(in_word_valid),
    .in_word_ready(in_word_ready),
    .out_block(out_block), .out_valid(out_valid),
    .out_last(out_last), .out_byte_count(out_byte_count),
    .busy(busy), .done(done),
    .perm_start(perm_start), .perm_rounds(perm_rounds),
    .perm_state_in(perm_state_in),
    .perm_state_out(perm_state_out),
    .perm_busy(perm_busy), .perm_done(perm_done)
  );

  ascon_permutation u_perm (
    .clk(clk), .rst_n(rst_n),
    .start(perm_start), .num_rounds(perm_rounds),
    .state_in(perm_state_in), .state_out(perm_state_out),
    .busy(perm_busy), .done(perm_done)
  );
endmodule
