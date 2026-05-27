`default_nettype none

`include "sdmc_modes.vh"
`include "sdmc_stream_defs.vh"

module sdmc_uart_token_bridge (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        frame_valid,
    input  wire [2:0]  mode_sel,
    input  wire        is_decrypt,
    input  wire [15:0] ad_total_bytes,
    input  wire [15:0] data_total_bytes,
    input  wire [15:0] out_length,
    input  wire [15:0] chain_count,
    input  wire [15:0] cs_total_bits,

    output reg         cfg_wr_en,
    output reg  [3:0]  cfg_wr_addr,
    output reg  [63:0] cfg_wr_data,
    output reg         sdmc_start,

    input  wire [7:0]  uart1_byte,
    input  wire        uart1_empty,
    output reg         uart1_rd_en,

    input  wire [7:0]  uart2_byte,
    input  wire        uart2_empty,
    output reg         uart2_rd_en,

    output reg  [7:0]  in_byte,
    output reg  [3:0]  in_kind,
    output reg         in_last,
    output reg         in_valid,
    input  wire        in_ready,

    input  wire        sdmc_done,
    input  wire        sdmc_error,

    output reg         bridge_busy,
    output reg         bridge_error
);

    localparam S_IDLE    = 4'd0;
    localparam S_CFG0    = 4'd1;
    localparam S_CFG1    = 4'd2;
    localparam S_CFG2    = 4'd3;
    localparam S_START   = 4'd4;
    localparam S_ADVANCE = 4'd5;
    localparam S_FEED    = 4'd6;
    localparam S_WAIT    = 4'd7;
    localparam S_DONE    = 4'd8;
    localparam S_ERR     = 4'd9;

    localparam PH_NONE  = 4'd0;
    localparam PH_KEY   = 4'd1;
    localparam PH_NONCE = 4'd2;
    localparam PH_AD    = 4'd3;
    localparam PH_CS    = 4'd4;
    localparam PH_MSG   = 4'd5;
    localparam PH_TAG   = 4'd6;

    reg [3:0]  state;
    reg [3:0]  phase;

    reg [3:0]  host_mode_q;
    reg        dec_q;
    reg [15:0] ad_len_q;
    reg [15:0] data_len_q;
    reg [15:0] out_len_q;
    reg [15:0] chain_count_q;
    reg [15:0] cs_bytes_q;

    reg [15:0] phase_len_q;
    reg [15:0] phase_count_q;
    reg [3:0]  phase_kind_q;
    reg        phase_src_uart2_q;

    wire [15:0] cs_bytes_w = {3'd0, cs_total_bits[15:3]} +
                              ((cs_total_bits[2:0] != 3'd0) ? 16'd1 : 16'd0);

    function [3:0] map_host_mode;
        input [2:0] m;
        begin
            case (m)
                3'd1: map_host_mode = `SDMC_HOST_HASH;
                3'd2: map_host_mode = `SDMC_HOST_XOF;
                3'd3: map_host_mode = `SDMC_HOST_CXOF;
                3'd4: map_host_mode = `SDMC_HOST_CXOF_CHAIN;
                3'd5: map_host_mode = `SDMC_HOST_AEAD_ENC;
                3'd6: map_host_mode = `SDMC_HOST_AEAD_DEC;
                3'd7: map_host_mode = `SDMC_HOST_XOF_CHAIN;
                default: map_host_mode = `SDMC_HOST_HASH;
            endcase
        end
    endfunction

    wire host_is_aead =
        (host_mode_q == `SDMC_HOST_AEAD_ENC) ||
        (host_mode_q == `SDMC_HOST_AEAD_DEC);

    wire host_is_cxof =
        (host_mode_q == `SDMC_HOST_CXOF) ||
        (host_mode_q == `SDMC_HOST_CXOF_CHAIN);

    wire [3:0] next_phase_w =
        (phase == PH_NONE)  ? (host_is_aead ? PH_KEY :
                              ((host_is_cxof && (cs_bytes_q != 16'd0)) ? PH_CS :
                              ((data_len_q != 16'd0) ? PH_MSG : PH_NONE))) :
        (phase == PH_KEY)   ? PH_NONCE :
        (phase == PH_NONCE) ? ((ad_len_q != 16'd0) ? PH_AD :
                              ((data_len_q != 16'd0) ? PH_MSG :
                              (dec_q ? PH_TAG : PH_NONE))) :
        (phase == PH_AD)    ? ((data_len_q != 16'd0) ? PH_MSG :
                              (dec_q ? PH_TAG : PH_NONE)) :
        (phase == PH_CS)    ? ((data_len_q != 16'd0) ? PH_MSG : PH_NONE) :
        (phase == PH_MSG)   ? (dec_q ? PH_TAG : PH_NONE) :
        PH_NONE;

    task load_phase;
        input [3:0] ph;
        begin
            phase <= ph;
            phase_count_q <= 16'd0;

            case (ph)
                PH_KEY: begin
                    phase_len_q <= 16'd16;
                    phase_kind_q <= `SDMC_TOK_KEY;
                    phase_src_uart2_q <= 1'b0;
                end

                PH_NONCE: begin
                    phase_len_q <= 16'd16;
                    phase_kind_q <= `SDMC_TOK_NONCE;
                    phase_src_uart2_q <= 1'b0;
                end

                PH_AD: begin
                    phase_len_q <= ad_len_q;
                    phase_kind_q <= `SDMC_TOK_AD;
                    phase_src_uart2_q <= 1'b0;
                end

                PH_CS: begin
                    phase_len_q <= cs_bytes_q;
                    phase_kind_q <= `SDMC_TOK_CS;
                    phase_src_uart2_q <= 1'b0;
                end

                PH_MSG: begin
                    phase_len_q <= data_len_q;
                    phase_kind_q <= `SDMC_TOK_MSG;
                    phase_src_uart2_q <= 1'b1;
                end

                PH_TAG: begin
                    phase_len_q <= 16'd16;
                    phase_kind_q <= `SDMC_TOK_TAG;
                    phase_src_uart2_q <= 1'b1;
                end

                default: begin
                    phase_len_q <= 16'd0;
                    phase_kind_q <= `SDMC_TOK_MSG;
                    phase_src_uart2_q <= 1'b1;
                end
            endcase
        end
    endtask

    wire src_empty = phase_src_uart2_q ? uart2_empty : uart1_empty;
    wire [7:0] src_byte = phase_src_uart2_q ? uart2_byte : uart1_byte;
    wire phase_last_byte = (phase_count_q + 16'd1 == phase_len_q);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            phase <= PH_NONE;

            host_mode_q <= `SDMC_HOST_HASH;
            dec_q <= 1'b0;
            ad_len_q <= 16'd0;
            data_len_q <= 16'd0;
            out_len_q <= 16'd32;
            chain_count_q <= 16'd1;
            cs_bytes_q <= 16'd0;

            phase_len_q <= 16'd0;
            phase_count_q <= 16'd0;
            phase_kind_q <= `SDMC_TOK_MSG;
            phase_src_uart2_q <= 1'b1;

            cfg_wr_en <= 1'b0;
            cfg_wr_addr <= 4'd0;
            cfg_wr_data <= 64'd0;
            sdmc_start <= 1'b0;

            uart1_rd_en <= 1'b0;
            uart2_rd_en <= 1'b0;

            in_byte <= 8'd0;
            in_kind <= `SDMC_TOK_MSG;
            in_last <= 1'b0;
            in_valid <= 1'b0;

            bridge_busy <= 1'b0;
            bridge_error <= 1'b0;
        end else if (clear) begin
            state <= S_IDLE;
            phase <= PH_NONE;
            cfg_wr_en <= 1'b0;
            sdmc_start <= 1'b0;
            uart1_rd_en <= 1'b0;
            uart2_rd_en <= 1'b0;
            in_valid <= 1'b0;
            bridge_busy <= 1'b0;
            bridge_error <= 1'b0;
        end else begin
            cfg_wr_en <= 1'b0;
            sdmc_start <= 1'b0;
            uart1_rd_en <= 1'b0;
            uart2_rd_en <= 1'b0;
            in_valid <= 1'b0;
            in_last <= 1'b0;

            case (state)
                S_IDLE: begin
                    bridge_busy <= 1'b0;
                    if (frame_valid) begin
                        host_mode_q <= map_host_mode(mode_sel);
                        dec_q <= is_decrypt || (map_host_mode(mode_sel) == `SDMC_HOST_AEAD_DEC);
                        ad_len_q <= ad_total_bytes;
                        data_len_q <= data_total_bytes;
                        out_len_q <= (out_length == 16'd0) ? 16'd32 : out_length;
                        chain_count_q <= (chain_count == 16'd0) ? 16'd1 : chain_count;
                        cs_bytes_q <= cs_bytes_w;
                        phase <= PH_NONE;
                        bridge_busy <= 1'b1;
                        bridge_error <= 1'b0;
                        state <= S_CFG0;
                    end
                end

                S_CFG0: begin
                    cfg_wr_en <= 1'b1;
                    cfg_wr_addr <= 4'd0;
                    cfg_wr_data <= {60'd0, host_mode_q};
                    state <= S_CFG1;
                end

                S_CFG1: begin
                    cfg_wr_en <= 1'b1;
                    cfg_wr_addr <= 4'd1;
                    cfg_wr_data <= {out_len_q, ad_len_q, cs_bytes_q, data_len_q};
                    state <= S_CFG2;
                end

                S_CFG2: begin
                    cfg_wr_en <= 1'b1;
                    cfg_wr_addr <= 4'd2;
                    cfg_wr_data <= {48'd0, chain_count_q};
                    state <= S_START;
                end

                S_START: begin
                    sdmc_start <= 1'b1;
                    state <= S_ADVANCE;
                end

                S_ADVANCE: begin
                    load_phase(next_phase_w);
                    if (next_phase_w == PH_NONE) begin
                        state <= S_WAIT;
                    end else begin
                        state <= S_FEED;
                    end
                end

                S_FEED: begin
                    if (phase_len_q == 16'd0) begin
                        state <= S_ADVANCE;
                    end else if (!src_empty && in_ready) begin
                        in_byte <= src_byte;
                        in_kind <= phase_kind_q;
                        in_last <= phase_last_byte;
                        in_valid <= 1'b1;

                        if (phase_src_uart2_q) uart2_rd_en <= 1'b1;
                        else uart1_rd_en <= 1'b1;

                        if (phase_last_byte) begin
                            state <= S_ADVANCE;
                        end
                        phase_count_q <= phase_count_q + 16'd1;
                    end
                end

                S_WAIT: begin
                    if (sdmc_error) begin
                        bridge_error <= 1'b1;
                        state <= S_ERR;
                    end else if (sdmc_done) begin
                        state <= S_DONE;
                    end
                end

                S_DONE: begin
                    bridge_busy <= 1'b0;
                    state <= S_IDLE;
                end

                S_ERR: begin
                    bridge_busy <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    bridge_error <= 1'b1;
                    bridge_busy <= 1'b0;
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
