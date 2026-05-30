`default_nettype none

`include "src/sdmc/sdmc_stream_defs.vh"

module sdmc_aead_uart_frontend (
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire                     clear,

    // UART0 command bytes
    input  wire [7:0]               rx0_byte,
    input  wire                     rx0_valid,

    // UART1 key/nonce/AD bytes
    input  wire [7:0]               rx1_byte,
    input  wire                     rx1_valid,

    // UART2 msg/tag bytes
    input  wire [7:0]               rx2_byte,
    input  wire                     rx2_valid,

    // AEAD core config/start
    output reg                      aead_start,
    output reg                      aead_is_decrypt,
    output reg  [15:0]              aead_ad_len,
    output reg  [15:0]              aead_data_len,
    output reg  [3:0]               host_mode,
    output reg  [15:0]              xof_out_len,
    output reg  [15:0]              xof_chain_count,
    output reg  [15:0]              xof_cs_len,

    // AEAD/HASH input token interface
    output reg  [`SDMC_TOKEN_W-1:0] aead_in_token,
    output wire                     aead_in_empty,
    input  wire                     aead_in_pop,

    // status
    output reg                      busy,
    output reg                      error,
    output reg  [3:0]               phase_dbg
);

    localparam [7:0] SOF_BYTE = 8'hA5;
    localparam [7:0] EOF_BYTE = 8'h5A;

    localparam PH_IDLE  = 4'd0;
    localparam PH_KEY   = 4'd1;
    localparam PH_NONCE = 4'd2;
    localparam PH_AD    = 4'd3;
    localparam PH_MSG   = 4'd4;
    localparam PH_TAG   = 4'd5;
    localparam PH_DONE  = 4'd6;
    localparam PH_ERR   = 4'd7;

    localparam C_IDLE = 4'd0;
    localparam C_B1   = 4'd1;
    localparam C_B2   = 4'd2;
    localparam C_B3   = 4'd3;
    localparam C_B4   = 4'd4;
    localparam C_B5   = 4'd5;
    localparam C_B6   = 4'd6;
    localparam C_B7   = 4'd7;
    localparam C_B8   = 4'd8;
    localparam C_B9   = 4'd9;
    localparam C_B10  = 4'd10;
    localparam C_B11  = 4'd11;
    localparam C_B12  = 4'd12;
    localparam C_B13  = 4'd13;

    reg [3:0] cmd_state;
    reg [3:0] mode_q;
    reg [15:0] ad_len_q;
    reg [15:0] data_len_q;
    reg [15:0] out_len_q;
    reg [15:0] chain_count_q;
    reg [15:0] cs_len_q;

    reg [3:0] phase;
    reg [15:0] phase_left;

    reg [63:0] pack_q;
    reg [3:0]  pack_count_q;
    reg [3:0]  pack_kind_q;
    reg        token_full_q;

    assign aead_in_empty = !token_full_q;

    wire token_fire = token_full_q && aead_in_pop;

    task clear_pack;
        begin
            pack_q       <= 64'd0;
            pack_count_q <= 4'd0;
            pack_kind_q  <= 4'd0;
        end
    endtask

    function [63:0] put_byte;
        input [63:0] word;
        input [3:0]  idx;
        input [7:0]  b;
        begin
            put_byte = word;
            case (idx[2:0])
                3'd0: put_byte[7:0]   = b;
                3'd1: put_byte[15:8]  = b;
                3'd2: put_byte[23:16] = b;
                3'd3: put_byte[31:24] = b;
                3'd4: put_byte[39:32] = b;
                3'd5: put_byte[47:40] = b;
                3'd6: put_byte[55:48] = b;
                3'd7: put_byte[63:56] = b;
                default: put_byte = word;
            endcase
        end
    endfunction

    function [3:0] phase_kind;
        input [3:0] ph;
        begin
            case (ph)
                PH_KEY:   phase_kind = `SDMC_TOK_KEY;
                PH_NONCE: phase_kind = `SDMC_TOK_NONCE;
                PH_AD:    phase_kind = ((mode_q == 4'd3) || (mode_q == 4'd7)) ? `SDMC_TOK_CS : `SDMC_TOK_AD;
                PH_MSG:   phase_kind = `SDMC_TOK_MSG;
                PH_TAG:   phase_kind = `SDMC_TOK_TAG;
                default:  phase_kind = `SDMC_TOK_MSG;
            endcase
        end
    endfunction

    function phase_uses_uart2;
        input [3:0] ph;
        begin
            phase_uses_uart2 = (ph == PH_MSG) || (ph == PH_TAG);
        end
    endfunction

    wire [7:0] phase_byte  = phase_uses_uart2(phase) ? rx2_byte  : rx1_byte;
    wire       phase_valid = phase_uses_uart2(phase) ? rx2_valid : rx1_valid;

    wire [63:0] pack_next = put_byte(pack_q, pack_count_q, phase_byte);
    wire [3:0]  count_next = pack_count_q + 4'd1;
    wire        last_byte_of_phase = (phase_left == 16'd1);
    wire        flush_word = phase_valid && !token_full_q &&
                             ((pack_count_q == 4'd7) || last_byte_of_phase);

    function [3:0] next_phase;
        input [3:0] ph;
        begin
            case (ph)
                PH_KEY:   next_phase = PH_NONCE;
                PH_NONCE: next_phase = (ad_len_q != 16'd0) ? PH_AD :
                                       (data_len_q != 16'd0) ? PH_MSG :
                                       (aead_is_decrypt ? PH_TAG : PH_DONE);
                PH_AD: begin
                    if ((mode_q == 4'd3) || (mode_q == 4'd7))
                        next_phase = (data_len_q != 16'd0) ? PH_MSG : PH_DONE;
                    else
                        next_phase = (data_len_q != 16'd0) ? PH_MSG :
                                     (aead_is_decrypt ? PH_TAG : PH_DONE);
                end
                PH_MSG: begin
                    if ((mode_q == 4'd5) || (mode_q == 4'd6))
                        next_phase = aead_is_decrypt ? PH_TAG : PH_DONE;
                    else
                        next_phase = PH_DONE;
                end
                PH_TAG:   next_phase = PH_DONE;
                default:  next_phase = PH_DONE;
            endcase
        end
    endfunction

    function [15:0] phase_len;
        input [3:0] ph;
        begin
            case (ph)
                PH_KEY:   phase_len = 16'd16;
                PH_NONCE: phase_len = 16'd16;
                PH_AD:    phase_len = ((mode_q == 4'd3) || (mode_q == 4'd7)) ? cs_len_q : ad_len_q;
                PH_MSG:   phase_len = data_len_q;
                PH_TAG:   phase_len = 16'd16;
                default:  phase_len = 16'd0;
            endcase
        end
    endfunction

    task advance_phase;
        reg [3:0] np;
        begin
            np = next_phase(phase);
            phase <= np;
            phase_dbg <= np;
            phase_left <= phase_len(np);
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cmd_state <= C_IDLE;
            mode_q <= 4'd0;
            ad_len_q <= 16'd0;
            data_len_q <= 16'd0;
            out_len_q <= 16'd0;
            chain_count_q <= 16'd1;
            cs_len_q <= 16'd0;

            phase <= PH_IDLE;
            phase_dbg <= PH_IDLE;
            phase_left <= 16'd0;

            aead_start <= 1'b0;
            aead_is_decrypt <= 1'b0;
            host_mode <= 4'd0;
            aead_ad_len <= 16'd0;
            aead_data_len <= 16'd0;
            xof_out_len <= 16'd32;
            xof_chain_count <= 16'd1;
            xof_cs_len <= 16'd0;

            aead_in_token <= {`SDMC_TOKEN_W{1'b0}};
            token_full_q <= 1'b0;

            busy <= 1'b0;
            error <= 1'b0;
            clear_pack();
        end else if (clear) begin
            cmd_state <= C_IDLE;
            phase <= PH_IDLE;
            phase_dbg <= PH_IDLE;
            phase_left <= 16'd0;
            aead_start <= 1'b0;
            host_mode <= 4'd0;
            xof_out_len <= 16'd32;
            xof_chain_count <= 16'd1;
            xof_cs_len <= 16'd0;
            token_full_q <= 1'b0;
            busy <= 1'b0;
            error <= 1'b0;
            clear_pack();
        end else begin
            aead_start <= 1'b0;

            if (token_fire) begin
                token_full_q <= 1'b0;
            end

            // Frontend is done once all expected input bytes have been packed
            // and the final staged token has been accepted by the AEAD core.
            if (busy && phase == PH_DONE && !token_full_q) begin
                busy <= 1'b0;
            end

            // UART0 command parser: A5 mode flags ad_lo ad_hi data_lo data_hi out_lo out_hi cc_lo cc_hi cs_lo cs_hi 5A
            if (!busy && rx0_valid) begin
                case (cmd_state)
                    C_IDLE: begin
                        if (rx0_byte == SOF_BYTE) cmd_state <= C_B1;
                    end
                    C_B1: begin
                        mode_q <= rx0_byte[3:0];
                        host_mode <= rx0_byte[3:0];
                        cmd_state <= C_B2;
                    end
                    C_B2: begin
                        aead_is_decrypt <= rx0_byte[2] || (mode_q == 4'd6);
                        cmd_state <= C_B3;
                    end
                    C_B3: begin
                        ad_len_q[7:0] <= rx0_byte;
                        cmd_state <= C_B4;
                    end
                    C_B4: begin
                        ad_len_q[15:8] <= rx0_byte;
                        cmd_state <= C_B5;
                    end
                    C_B5: begin
                        data_len_q[7:0] <= rx0_byte;
                        cmd_state <= C_B6;
                    end
                    C_B6: begin
                        data_len_q[15:8] <= rx0_byte;
                        cmd_state <= C_B7;
                    end
                    C_B7: begin
                        out_len_q[7:0] <= rx0_byte;
                        cmd_state <= C_B8;
                    end
                    C_B8: begin
                        out_len_q[15:8] <= rx0_byte;
                        cmd_state <= C_B9;
                    end
                    C_B9: begin
                        chain_count_q[7:0] <= rx0_byte;
                        cmd_state <= C_B10;
                    end
                    C_B10: begin
                        chain_count_q[15:8] <= rx0_byte;
                        cmd_state <= C_B11;
                    end
                    C_B11: begin
                        cs_len_q[7:0] <= rx0_byte;
                        cmd_state <= C_B12;
                    end
                    C_B12: begin
                        cs_len_q[15:8] <= rx0_byte;
                        cmd_state <= C_B13;
                    end
                    C_B13: begin
                        if (rx0_byte == EOF_BYTE &&
                            (mode_q == 4'd1 || mode_q == 4'd2 || mode_q == 4'd3 ||
                             mode_q == 4'd4 || mode_q == 4'd5 || mode_q == 4'd6 ||
                             mode_q == 4'd7)) begin
                            aead_ad_len <= ad_len_q;
                            aead_data_len <= data_len_q;
                            xof_out_len <= (out_len_q == 16'd0) ? 16'd32 : out_len_q;
                            xof_chain_count <= (chain_count_q == 16'd0) ? 16'd1 : chain_count_q;
                            xof_cs_len <= cs_len_q;
                            aead_start <= 1'b1;
                            busy <= 1'b1;
                            error <= 1'b0;
                            clear_pack();

                            if (mode_q == 4'd1 || mode_q == 4'd2 || mode_q == 4'd4) begin
                                phase <= (data_len_q != 16'd0) ? PH_MSG : PH_DONE;
                                phase_dbg <= (data_len_q != 16'd0) ? PH_MSG : PH_DONE;
                                phase_left <= data_len_q;
                            end else if (mode_q == 4'd3 || mode_q == 4'd7) begin
                                if (cs_len_q != 16'd0) begin
                                    phase <= PH_AD;
                                    phase_dbg <= PH_AD;
                                    phase_left <= cs_len_q;
                                end else if (data_len_q != 16'd0) begin
                                    phase <= PH_MSG;
                                    phase_dbg <= PH_MSG;
                                    phase_left <= data_len_q;
                                end else begin
                                    phase <= PH_DONE;
                                    phase_dbg <= PH_DONE;
                                    phase_left <= 16'd0;
                                end
                            end else begin
                                phase <= PH_KEY;
                                phase_dbg <= PH_KEY;
                                phase_left <= 16'd16;
                            end
                        end else begin
                            error <= 1'b1;
                            phase <= PH_ERR;
                            phase_dbg <= PH_ERR;
                        end
                        cmd_state <= C_IDLE;
                    end
                    default: cmd_state <= C_IDLE;
                endcase
            end

            // Phase byte packer: one-token staging only.
            if (busy && !token_full_q && phase_valid &&
                (phase == PH_KEY || phase == PH_NONCE || phase == PH_AD || phase == PH_MSG || phase == PH_TAG)) begin

                if (pack_count_q == 4'd0) begin
                    pack_kind_q <= phase_kind(phase);
                end

                if (flush_word) begin
                    aead_in_token <= {
                        last_byte_of_phase,
                        (pack_count_q == 4'd0) ? phase_kind(phase) : pack_kind_q,
                        count_next,
                        pack_next
                    };
                    token_full_q <= 1'b1;
                    clear_pack();

                    if (last_byte_of_phase) begin
                        advance_phase();
                    end else begin
                        phase_left <= phase_left - 16'd1;
                    end
                end else begin
                    pack_q <= pack_next;
                    pack_count_q <= count_next;
                    phase_left <= phase_left - 16'd1;
                end
            end
        end
    end

endmodule

`default_nettype wire
