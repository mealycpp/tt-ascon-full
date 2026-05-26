`ifndef SDMC_CRYPTO_DEFS_VH
`define SDMC_CRYPTO_DEFS_VH

// Proven constants from existing passing controllers.
`define SDMC_HASH256_IV 64'h0000_0801_00CC_0002
`define SDMC_XOF128_IV  64'h0000_0800_00CC_0003
`define SDMC_CXOF128_IV 64'h0000_0800_00CC_0004

`define SDMC_ASCON_P12 4'd12
`define SDMC_ASCON_P8  4'd8

`endif
