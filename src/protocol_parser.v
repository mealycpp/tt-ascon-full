/*
 * protocol_parser.v  — Phase 3a: 14-byte UART0 control frame decoder.
 *
 * Fixed frame, no options:
 *   B0   SOF       = 0xA5
 *   B1   MODE_CMD  (1=Hash256, 2=XOF128, 3=CXOF128, 4=CXOF_CHAIN,
 *                   5=AEAD_ENC, 6=AEAD_DEC, 7=XOF_CHAIN)
 *   B2   FLAGS     bit0=chain_enable, bit1=chain_debug, bit2=is_decrypt
 *                  (bits[7:3] reserved, must be 0; reserved bits NOT
 *                  enforced — host responsibility)
 *   B3   AD_LEN_LO       (UART1 byte count, little-endian)
 *   B4   AD_LEN_HI
 *   B5   DATA_LEN_LO     (UART2 byte count, little-endian)
 *   B6   DATA_LEN_HI
 *   B7   OUT_LEN_LO      (XOF/CXOF output length in bytes)
 *   B8   OUT_LEN_HI
 *   B9   CHAIN_CNT_LO    (XOF_CHAIN / CXOF_CHAIN iteration count)
 *   B10  CHAIN_CNT_HI
 *   B11  CS_BITS_LO      (CXOF customization-string length in bits)
 *   B12  CS_BITS_HI
 *   B13  EOF       = 0x5A
 *
 * Behavior:
 *   - SOF mismatch in IDLE: byte discarded, stay IDLE (resync).
 *   - EOF mismatch: frame_error pulsed, all latched data discarded,
 *     return to IDLE.
 *   - On valid frame: latch all scalar outputs, pulse start for 1 cycle
 *     AFTER pulsing frame_valid for 1 cycle, return to IDLE.
 *   - Parser does NOT track byte consumption, does NOT switch phase_sel,
 *     does NOT manage flush. Pure frame decoder.
 *
 * Input handshake: parser pulls one byte per cycle from the UART0 byte
 *   FIFO via standard ready/valid:
 *     in_byte_valid && in_byte_ready  -> byte accepted
 *
 *   Parser asserts in_byte_ready whenever it can accept the next byte
 *   of the frame (essentially always while parsing, deasserts only
 *   during the 1-cycle frame_valid/start emission).
 */
`default_nettype none

module protocol_parser (
    input  wire        clk,
    input  wire        rst_n,

    // Byte input from UART0 byte FIFO
    input  wire [7:0]  in_byte,
    input  wire        in_byte_valid,
    output reg         in_byte_ready,

    // Scalar metadata outputs (registered, held stable after frame_valid)
    output reg  [2:0]  mode_sel,
    output reg         is_decrypt,
    output reg         chain_enable,
    output reg         chain_debug,
    output reg  [15:0] ad_total_bytes,
    output reg  [15:0] data_total_bytes,
    output reg  [15:0] out_length,
    output reg  [15:0] chain_count,
    output reg  [15:0] cs_total_bits,

    // Pulses (each 1 cycle wide)
    output reg         frame_valid,    // valid frame parsed
    output reg         frame_error,    // EOF mismatch or stream error
    output reg         start           // pulse to start mode_controller
);

    localparam [7:0] SOF_BYTE = 8'hA5;
    localparam [7:0] EOF_BYTE = 8'h5A;

    // FSM states: one state per byte slot, plus terminal states
    localparam S_IDLE      = 5'd0;   // waiting for SOF
    localparam S_B1_MODE   = 5'd1;
    localparam S_B2_FLAGS  = 5'd2;
    localparam S_B3_ADLO   = 5'd3;
    localparam S_B4_ADHI   = 5'd4;
    localparam S_B5_DLO    = 5'd5;
    localparam S_B6_DHI    = 5'd6;
    localparam S_B7_OLO    = 5'd7;
    localparam S_B8_OHI    = 5'd8;
    localparam S_B9_CCLO   = 5'd9;
    localparam S_B10_CCHI  = 5'd10;
    localparam S_B11_CSLO  = 5'd11;
    localparam S_B12_CSHI  = 5'd12;
    localparam S_B13_EOF   = 5'd13;
    localparam S_VALID     = 5'd14;  // pulse frame_valid
    localparam S_START     = 5'd15;  // pulse start
    localparam S_ERROR     = 5'd16;  // pulse frame_error

    reg [4:0] state;

    // Staging registers (latched per byte, transferred to outputs in S_VALID)
    reg [2:0]  mode_stage;
    reg [7:0]  flags_stage;
    reg [15:0] ad_stage;
    reg [15:0] data_stage;
    reg [15:0] out_stage;
    reg [15:0] cc_stage;
    reg [15:0] cs_stage;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state            <= S_IDLE;
            in_byte_ready    <= 1'b0;
            mode_sel         <= 3'd0;
            is_decrypt       <= 1'b0;
            chain_enable     <= 1'b0;
            chain_debug      <= 1'b0;
            ad_total_bytes   <= 16'd0;
            data_total_bytes <= 16'd0;
            out_length       <= 16'd0;
            chain_count      <= 16'd0;
            cs_total_bits    <= 16'd0;
            frame_valid      <= 1'b0;
            frame_error      <= 1'b0;
            start            <= 1'b0;
            mode_stage       <= 3'd0;
            flags_stage      <= 8'd0;
            ad_stage         <= 16'd0;
            data_stage       <= 16'd0;
            out_stage        <= 16'd0;
            cc_stage         <= 16'd0;
            cs_stage         <= 16'd0;
        end else begin
            // Default deassertions (1-cycle pulses)
            frame_valid   <= 1'b0;
            frame_error   <= 1'b0;
            start         <= 1'b0;
            in_byte_ready <= 1'b1;  // ready in all parsing states

            case (state)
                S_IDLE: begin
                    if (in_byte_valid && in_byte_ready) begin
                        if (in_byte == SOF_BYTE) begin
                            state <= S_B1_MODE;
                        end
                        // Else: discard byte, stay IDLE (resync)
                    end
                end

                S_B1_MODE: begin
                    if (in_byte_valid && in_byte_ready) begin
                        // Valid modes are 1..7 only. 0 and 8..255 -> frame_error.
                        if (in_byte == 8'd0 || in_byte > 8'd7) begin
                            in_byte_ready <= 1'b0;
                            state         <= S_ERROR;
                        end else begin
                            mode_stage <= in_byte[2:0];
                            state      <= S_B2_FLAGS;
                        end
                    end
                end

                S_B2_FLAGS: begin
                    if (in_byte_valid && in_byte_ready) begin
                        flags_stage <= in_byte;
                        state       <= S_B3_ADLO;
                    end
                end

                S_B3_ADLO: begin
                    if (in_byte_valid && in_byte_ready) begin
                        ad_stage[7:0] <= in_byte;
                        state         <= S_B4_ADHI;
                    end
                end

                S_B4_ADHI: begin
                    if (in_byte_valid && in_byte_ready) begin
                        ad_stage[15:8] <= in_byte;
                        state          <= S_B5_DLO;
                    end
                end

                S_B5_DLO: begin
                    if (in_byte_valid && in_byte_ready) begin
                        data_stage[7:0] <= in_byte;
                        state           <= S_B6_DHI;
                    end
                end

                S_B6_DHI: begin
                    if (in_byte_valid && in_byte_ready) begin
                        data_stage[15:8] <= in_byte;
                        state            <= S_B7_OLO;
                    end
                end

                S_B7_OLO: begin
                    if (in_byte_valid && in_byte_ready) begin
                        out_stage[7:0] <= in_byte;
                        state          <= S_B8_OHI;
                    end
                end

                S_B8_OHI: begin
                    if (in_byte_valid && in_byte_ready) begin
                        out_stage[15:8] <= in_byte;
                        state           <= S_B9_CCLO;
                    end
                end

                S_B9_CCLO: begin
                    if (in_byte_valid && in_byte_ready) begin
                        cc_stage[7:0] <= in_byte;
                        state         <= S_B10_CCHI;
                    end
                end

                S_B10_CCHI: begin
                    if (in_byte_valid && in_byte_ready) begin
                        cc_stage[15:8] <= in_byte;
                        state          <= S_B11_CSLO;
                    end
                end

                S_B11_CSLO: begin
                    if (in_byte_valid && in_byte_ready) begin
                        cs_stage[7:0] <= in_byte;
                        state         <= S_B12_CSHI;
                    end
                end

                S_B12_CSHI: begin
                    if (in_byte_valid && in_byte_ready) begin
                        cs_stage[15:8] <= in_byte;
                        state          <= S_B13_EOF;
                    end
                end

                S_B13_EOF: begin
                    if (in_byte_valid && in_byte_ready) begin
                        if (in_byte == EOF_BYTE) begin
                            // Commit all staged values to outputs
                            mode_sel         <= mode_stage;
                            is_decrypt       <= flags_stage[2];
                            chain_enable     <= flags_stage[0];
                            chain_debug      <= flags_stage[1];
                            ad_total_bytes   <= ad_stage;
                            data_total_bytes <= data_stage;
                            out_length       <= out_stage;
                            chain_count      <= cc_stage;
                            cs_total_bits    <= cs_stage;
                            in_byte_ready    <= 1'b0;  // stop pulling
                            state            <= S_VALID;
                        end else begin
                            in_byte_ready <= 1'b0;
                            state         <= S_ERROR;
                        end
                    end
                end

                S_VALID: begin
                    frame_valid   <= 1'b1;
                    in_byte_ready <= 1'b0;
                    state         <= S_START;
                end

                S_START: begin
                    start         <= 1'b1;
                    in_byte_ready <= 1'b0;
                    state         <= S_IDLE;
                end

                S_ERROR: begin
                    frame_error   <= 1'b1;
                    in_byte_ready <= 1'b0;
                    state         <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
