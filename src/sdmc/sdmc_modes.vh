`ifndef SDMC_MODES_VH
`define SDMC_MODES_VH

// Small internal CISC program families.
// Do not duplicate datapaths per external mode.
`define SDMC_PROG_PERM_SMOKE       4'd0
`define SDMC_PROG_ALU_SMOKE        4'd1
`define SDMC_PROG_HASH_FAMILY      4'd2
`define SDMC_PROG_XOF_CHAIN_FAMILY 4'd3
`define SDMC_PROG_AEAD_FAMILY      4'd4

// External host mode decode can map many modes to few internal programs.
`define SDMC_HOST_HASH             4'd0
`define SDMC_HOST_HASHA            4'd1
`define SDMC_HOST_XOF              4'd2
`define SDMC_HOST_CXOF             4'd3
`define SDMC_HOST_XOF_CHAIN        4'd4
`define SDMC_HOST_CXOF_CHAIN       4'd5
`define SDMC_HOST_AEAD_ENC         4'd6
`define SDMC_HOST_AEAD_DEC         4'd7

`endif
