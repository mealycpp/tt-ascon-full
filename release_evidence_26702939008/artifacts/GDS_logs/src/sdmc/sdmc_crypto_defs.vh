`ifndef SDMC_CRYPTO_DEFS_VH
`define SDMC_CRYPTO_DEFS_VH

// Proven constants from existing passing controllers.
`define SDMC_HASH256_IV 64'h0000_0801_00CC_0002
// Official ASCON-C asconhash256 initialized state words.
`define SDMC_HASH256_IV0 64'h9b1e5494e934d681
`define SDMC_HASH256_IV1 64'h4bc3a01e333751d2
`define SDMC_HASH256_IV2 64'hae65396c6b34b81a
`define SDMC_HASH256_IV3 64'h3c7fd4a4d56a4db3
`define SDMC_HASH256_IV4 64'h1a5c464906c5976d
`define SDMC_XOF128_IV  64'h0000_0800_00CC_0003
`define SDMC_CXOF128_IV 64'h0000_0800_00CC_0004
`define SDMC_AEAD128_IV 64'h0000_1000_808C_0001

`define SDMC_ASCON_P12 4'd12
`define SDMC_ASCON_P8  4'd8

`endif
