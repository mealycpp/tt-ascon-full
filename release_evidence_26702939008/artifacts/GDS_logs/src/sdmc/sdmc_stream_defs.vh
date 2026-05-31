`ifndef SDMC_STREAM_DEFS_VH
`define SDMC_STREAM_DEFS_VH

// SDMC typed stream token format:
//   token[72]    = last
//   token[71:68] = kind
//   token[67:64] = byte count, 0..8
//   token[63:0]  = data word, byte 0 in data[7:0]
`define SDMC_TOKEN_W          73
`define SDMC_TOKEN_LAST_BIT   72
`define SDMC_TOKEN_KIND_MSB   71
`define SDMC_TOKEN_KIND_LSB   68
`define SDMC_TOKEN_BYTES_MSB  67
`define SDMC_TOKEN_BYTES_LSB  64
`define SDMC_TOKEN_DATA_MSB   63
`define SDMC_TOKEN_DATA_LSB   0

// Token kinds.
// Keep the token namespace small and typed. Do not create one datapath per mode.
`define SDMC_TOK_CFG          4'd0
`define SDMC_TOK_MSG          4'd1
`define SDMC_TOK_CS           4'd2
`define SDMC_TOK_AD           4'd3
`define SDMC_TOK_KEY          4'd4
`define SDMC_TOK_NONCE        4'd5
`define SDMC_TOK_TAG          4'd6
`define SDMC_TOK_OUT          4'd7
`define SDMC_TOK_STATUS       4'd8

`define SDMC_PACK_TOKEN(last, kind, bytes, data) {last, kind, bytes, data}

`endif
