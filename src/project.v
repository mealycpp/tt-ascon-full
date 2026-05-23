/*
 * tt-ascon-full — Reconfigurable ASCON Integrated Crypto Processor
 * Dr. Mohamed El-Hadedy — RSCL@CPP
 * Tiny Tapeout TTGF26a — GF180 PDK
 *
 * PHASE 1 STUB: placeholder top module to verify GF180 toolchain.
 * Real RTL will be ported from tt-ascon-cxof-chain after CI goes green.
 */
`default_nettype none

module tt_um_mealycpp_ascon_full (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // Stub: adder, gated by reset. Replaced in Phase 2.
  assign uo_out  = rst_n ? (ui_in + uio_in) : 8'b0;
  assign uio_out = 8'b0;
  assign uio_oe  = 8'b0;

  // Prevent unused warnings
  wire _unused = &{ena, clk, 1'b0};

endmodule
