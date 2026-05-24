`default_nettype none
`timescale 1ns/1ps

module tb_perm ();
  initial begin
    $dumpfile("tb_perm.fst");
    $dumpvars(0, tb_perm);
  end

  reg clk;
  reg rst_n;
  reg start;
  reg  [3:0]   num_rounds;
  reg  [319:0] state_in;
  wire [319:0] state_out;
  wire busy;
  wire done;

  ascon_permutation dut (
    .clk(clk), .rst_n(rst_n), .start(start),
    .num_rounds(num_rounds),
    .state_in(state_in), .state_out(state_out),
    .busy(busy), .done(done)
  );
endmodule
