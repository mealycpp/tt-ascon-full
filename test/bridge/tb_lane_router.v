`default_nettype none
`timescale 1ns/1ps
module tb_lane_router ();
  initial begin
    $dumpfile("tb_lane_router.fst");
    $dumpvars(0, tb_lane_router);
  end
  reg clk; reg rst_n;
  reg [2:0]  mode;
  reg        is_decrypt;
  reg [15:0] ad_total_bytes;
  reg [15:0] data_total_bytes;
  reg [15:0] cs_total_bits;
  reg        start_pulse;
  reg        sdmc_done;
  reg        sdmc_in_word_ready;
  // Three packed streams
  reg [63:0] pack_word_0, pack_word_1, pack_word_2;
  reg [3:0]  pack_bytes_0, pack_bytes_1, pack_bytes_2;
  reg        pack_valid_0, pack_valid_1, pack_valid_2;
  // Outputs
  wire [1:0]  phase_sel;
  wire [63:0] sdmc_in_word;
  wire [3:0]  sdmc_in_word_bytes;
  wire        sdmc_in_word_valid;
  wire        router_busy;

  lane_router dut (
    .clk(clk), .rst_n(rst_n),
    .mode(mode), .is_decrypt(is_decrypt),
    .ad_total_bytes(ad_total_bytes),
    .data_total_bytes(data_total_bytes),
    .cs_total_bits(cs_total_bits),
    .start_pulse(start_pulse),
    .sdmc_done(sdmc_done),
    .sdmc_in_word_ready(sdmc_in_word_ready),
    .pack_word_0(pack_word_0), .pack_bytes_0(pack_bytes_0), .pack_valid_0(pack_valid_0),
    .pack_word_1(pack_word_1), .pack_bytes_1(pack_bytes_1), .pack_valid_1(pack_valid_1),
    .pack_word_2(pack_word_2), .pack_bytes_2(pack_bytes_2), .pack_valid_2(pack_valid_2),
    .phase_sel(phase_sel),
    .sdmc_in_word(sdmc_in_word), .sdmc_in_word_bytes(sdmc_in_word_bytes),
    .sdmc_in_word_valid(sdmc_in_word_valid),
    .router_busy(router_busy)
  );
endmodule
