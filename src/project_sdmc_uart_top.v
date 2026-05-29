`default_nettype none

`include "src/sdmc/sdmc_stream_defs.vh"

module tt_um_mealycpp_ascon_sdmc_uart (
    input  wire [7:0] ui_in,
    output wire [7:0] uo_out,
    input  wire [7:0] uio_in,
    output wire [7:0] uio_out,
    output wire [7:0] uio_oe,
    input  wire       ena,
    input  wire       clk,
    input  wire       rst_n
);

    wire uart0_rx = ui_in[0];  // single RX stream: command + key + nonce + AD + msg/tag
    wire clear = !ena;

    wire [15:0] baud_div = 16'd217;

    wire [7:0] rx0_byte;
    wire rx0_valid;
    wire rx0_active;

    // Single-UART rescue: feed the same RX byte stream into all frontend phases.
    wire [7:0] rx1_byte  = rx0_byte;
    wire [7:0] rx2_byte  = rx0_byte;
    wire       rx1_valid = rx0_valid;
    wire       rx2_valid = rx0_valid;
    wire       rx1_active = 1'b0;
    wire       rx2_active = 1'b0;

    uart_rx u_rx0 (
        .clk(clk), .rst_n(rst_n), .baud_div(baud_div),
        .rx(uart0_rx), .byte_out(rx0_byte),
        .byte_valid(rx0_valid), .rx_active(rx0_active)
    );



    wire                     aead_start;
    wire                     aead_is_decrypt;
    wire [15:0]              aead_ad_len;
    wire [15:0]              aead_data_len;
    wire [`SDMC_TOKEN_W-1:0] aead_in_token;
    wire                     aead_in_empty;
    wire                     aead_in_pop;
    wire                     front_busy;
    wire                     front_error;
    wire [3:0]               front_phase;

    sdmc_aead_uart_frontend u_front (
        .clk             (clk),
        .rst_n           (rst_n),
        .clear           (clear),

        .rx0_byte        (rx0_byte),
        .rx0_valid       (rx0_valid),
        .rx1_byte        (rx1_byte),
        .rx1_valid       (rx1_valid),
        .rx2_byte        (rx2_byte),
        .rx2_valid       (rx2_valid),

        .aead_start      (aead_start),
        .aead_is_decrypt (aead_is_decrypt),
        .aead_ad_len     (aead_ad_len),
        .aead_data_len   (aead_data_len),

        .aead_in_token   (aead_in_token),
        .aead_in_empty   (aead_in_empty),
        .aead_in_pop     (aead_in_pop),

        .busy            (front_busy),
        .error           (front_error),
        .phase_dbg       (front_phase)
    );

    wire [`SDMC_TOKEN_W-1:0] aead_out_token;
    wire                     aead_out_push;
    wire                     aead_out_full;
    wire                     aead_busy;
    wire                     aead_done;
    wire                     aead_error;
    wire                     aead_auth_ok;

    sdmc_aead128_core u_aead (
        .clk        (clk),
        .rst_n      (rst_n),
        .clear      (clear),

        .start      (aead_start),
        .is_decrypt (aead_is_decrypt),
        .ad_len     (aead_ad_len),
        .data_len   (aead_data_len),

        .in_token   (aead_in_token),
        .in_empty   (aead_in_empty),
        .in_pop     (aead_in_pop),

        .out_token  (aead_out_token),
        .out_push   (aead_out_push),
        .out_full   (aead_out_full),

        .busy       (aead_busy),
        .done       (aead_done),
        .error      (aead_error),
        .auth_ok    (aead_auth_ok)
    );

    // Tiny output serializer: AEAD output tokens -> UART2 bytes.
    // Uses one active serializer register plus a small circular token queue.
    // This avoids the old pend0..pend4 shift-overwrite bug when AEAD output
    // and UART serializer promotion happen near the same cycle.
    localparam integer OUTQ_DEPTH = 8;
    localparam [3:0] OUTQ_DEPTH_COUNT = 4'd8;

    reg [63:0] ser_data_q;
    reg [3:0]  ser_count_q;
    reg [3:0]  ser_idx_q;
    reg [3:0]  ser_kind_q;
    reg        ser_valid_q;

    reg [63:0] outq_data_q  [0:OUTQ_DEPTH-1];
    reg [3:0]  outq_countb_q[0:OUTQ_DEPTH-1];
    reg [3:0]  outq_kind_q  [0:OUTQ_DEPTH-1];
    reg [2:0]  outq_wr_ptr_q;
    reg [2:0]  outq_rd_ptr_q;
    reg [3:0]  outq_count_q;

    wire outq_full  = (outq_count_q == OUTQ_DEPTH_COUNT);
    wire outq_empty = (outq_count_q == 4'd0);

    wire [3:0] out_kind = ser_kind_q;

    wire tx_ready;
    wire tx_send = ser_valid_q && tx_ready;

    // Conservative one-cycle backpressure while the active token completes.
    // This prevents accepting a new AEAD token while the active register is
    // being replaced by a queued token.
    wire ser_last_byte = tx_send && (ser_idx_q + 4'd1 >= ser_count_q);

    assign aead_out_full = ser_last_byte || (ser_valid_q && outq_full);

    reg [7:0] tx_byte;

    always @* begin
        case (ser_idx_q[2:0])
            3'd0: tx_byte = ser_data_q[7:0];
            3'd1: tx_byte = ser_data_q[15:8];
            3'd2: tx_byte = ser_data_q[23:16];
            3'd3: tx_byte = ser_data_q[31:24];
            3'd4: tx_byte = ser_data_q[39:32];
            3'd5: tx_byte = ser_data_q[47:40];
            3'd6: tx_byte = ser_data_q[55:48];
            3'd7: tx_byte = ser_data_q[63:56];
            default: tx_byte = 8'd0;
        endcase
    end

    integer outq_i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            ser_data_q      <= 64'd0;
            ser_count_q     <= 4'd0;
            ser_idx_q       <= 4'd0;
            ser_kind_q      <= 4'd0;
            ser_valid_q     <= 1'b0;

            outq_wr_ptr_q   <= 3'd0;
            outq_rd_ptr_q   <= 3'd0;
            outq_count_q    <= 4'd0;

            for (outq_i = 0; outq_i < OUTQ_DEPTH; outq_i = outq_i + 1) begin
                outq_data_q[outq_i]   <= 64'd0;
                outq_countb_q[outq_i] <= 4'd0;
                outq_kind_q[outq_i]   <= 4'd0;
            end
        end else if (clear) begin
            ser_data_q      <= 64'd0;
            ser_count_q     <= 4'd0;
            ser_idx_q       <= 4'd0;
            ser_kind_q      <= 4'd0;
            ser_valid_q     <= 1'b0;

            outq_wr_ptr_q   <= 3'd0;
            outq_rd_ptr_q   <= 3'd0;
            outq_count_q    <= 4'd0;

            for (outq_i = 0; outq_i < OUTQ_DEPTH; outq_i = outq_i + 1) begin
                outq_data_q[outq_i]   <= 64'd0;
                outq_countb_q[outq_i] <= 4'd0;
                outq_kind_q[outq_i]   <= 4'd0;
            end
        end else begin
            // Accept a new AEAD token into active if idle, otherwise enqueue.
            if (aead_out_push && !aead_out_full) begin
                if (!ser_valid_q) begin
                    ser_data_q  <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    ser_count_q <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    ser_idx_q   <= 4'd0;
                    ser_kind_q  <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    ser_valid_q <= 1'b1;
                end else begin
                    outq_data_q[outq_wr_ptr_q]   <= aead_out_token[`SDMC_TOKEN_DATA_MSB:`SDMC_TOKEN_DATA_LSB];
                    outq_countb_q[outq_wr_ptr_q] <= aead_out_token[`SDMC_TOKEN_BYTES_MSB:`SDMC_TOKEN_BYTES_LSB];
                    outq_kind_q[outq_wr_ptr_q]   <= aead_out_token[`SDMC_TOKEN_KIND_MSB:`SDMC_TOKEN_KIND_LSB];
                    outq_wr_ptr_q                <= outq_wr_ptr_q + 3'd1;
                    outq_count_q                 <= outq_count_q + 4'd1;
                end
            end

            // Serialize active token. When active token completes, promote
            // exactly one queued token if available.
            if (tx_send) begin
                if (ser_idx_q + 4'd1 >= ser_count_q) begin
                    if (!outq_empty) begin
                        ser_data_q    <= outq_data_q[outq_rd_ptr_q];
                        ser_count_q   <= outq_countb_q[outq_rd_ptr_q];
                        ser_kind_q    <= outq_kind_q[outq_rd_ptr_q];
                        ser_idx_q     <= 4'd0;
                        ser_valid_q   <= 1'b1;
                        outq_rd_ptr_q <= outq_rd_ptr_q + 3'd1;
                        outq_count_q  <= outq_count_q - 4'd1;
                    end else begin
                        ser_valid_q <= 1'b0;
                        ser_idx_q   <= 4'd0;
                    end
                end else begin
                    ser_idx_q <= ser_idx_q + 4'd1;
                end
            end
        end
    end

    wire uart2_tx;

    uart_tx u_tx2 (
        .clk      (clk),
        .rst_n    (rst_n),
        .baud_div (baud_div),
        .byte_in  (tx_byte),
        .send     (tx_send),
        .ready    (tx_ready),
        .tx       (uart2_tx)
    );

    reg error_sticky;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) error_sticky <= 1'b0;
        else if (clear) error_sticky <= 1'b0;
        else if (front_error || aead_error) error_sticky <= 1'b1;
        else if (aead_start) error_sticky <= 1'b0;
    end

    reg [23:0] hb_cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) hb_cnt <= 24'd0;
        else hb_cnt <= hb_cnt + 24'd1;
    end

    assign uo_out[0] = uart2_tx;  // single TX stream mirror
    assign uo_out[1] = 1'b1;
    assign uo_out[2] = uart2_tx;  // kept for existing tests/compatibility
    assign uo_out[3] = front_busy | aead_busy;
    assign uo_out[4] = aead_done;
    assign uo_out[5] = error_sticky;
    assign uo_out[6] = aead_auth_ok;
    assign uo_out[7] = hb_cnt[23];

    // Debug: high nibble = output token kind, low nibble = frontend phase.
    assign uio_out = {out_kind, front_phase};
    assign uio_oe  = 8'h00;

    wire _unused = &{
        uio_in,
        rx0_active, rx1_active, rx2_active,
        aead_done,
        1'b0
    };

endmodule

`default_nettype wire
