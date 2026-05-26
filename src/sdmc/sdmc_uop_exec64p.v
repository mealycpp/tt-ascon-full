`default_nettype none

module sdmc_uop_exec64p (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        host_wr_en,
    input  wire [3:0]  host_wr_addr,
    input  wire [63:0] host_wr_data,
    output wire        host_ready,

    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [1:0]  cmd_type,
    input  wire [3:0]  cmd_op,
    input  wire [3:0]  cmd_dst,
    input  wire [3:0]  cmd_src_a,
    input  wire [3:0]  cmd_src_b,
    input  wire [3:0]  cmd_n,
    input  wire        cmd_writeback,
    input  wire [2:0]  cmd_perm_lane,
    input  wire [3:0]  cmd_rounds,

    output reg         busy,
    output reg         done,
    output reg  [63:0] result,

    output wire [63:0] r0,
    output wire [63:0] r1,
    output wire [63:0] r2,
    output wire [63:0] r3,
    output wire [63:0] r4,

    output wire [63:0] p0,
    output wire [63:0] p1,
    output wire [63:0] p2,
    output wire [63:0] p3,
    output wire [63:0] p4
);

    localparam CMD_ALU      = 2'd0;
    localparam CMD_PERM_WR  = 2'd1;
    localparam CMD_PERM_RUN = 2'd2;
    localparam CMD_PERM_RD  = 2'd3;

    localparam S_IDLE          = 4'd0;
    localparam S_READ          = 4'd1;
    localparam S_WAIT_READ     = 4'd2;
    localparam S_ALU_FIRE      = 4'd3;
    localparam S_ALU_WAIT      = 4'd4;
    localparam S_PERM_WR       = 4'd5;
    localparam S_PERM_RUN_FIRE = 4'd6;
    localparam S_PERM_RUN_WAIT = 4'd7;
    localparam S_PERM_RD_FIRE  = 4'd8;
    localparam S_PERM_RD_WAIT  = 4'd9;
    localparam S_WRITE         = 4'd10;
    localparam S_DONE          = 4'd11;

    reg [3:0] state;

    reg [1:0]  type_r;
    reg [3:0]  op_r;
    reg [3:0]  dst_r;
    reg [3:0]  src_a_r;
    reg [3:0]  src_b_r;
    reg [3:0]  n_r;
    reg        writeback_r;
    reg [2:0]  perm_lane_r;
    reg [3:0]  rounds_r;

    reg [63:0] alu_a_r;
    reg [63:0] alu_b_r;

    wire rf_rd_en = (state == S_READ);

    wire internal_wr_en = (state == S_WRITE);
    wire rf_wr_en = host_wr_en | internal_wr_en;

    // Local write-port select. Host writes happen only while idle/ready;
    // internal writes happen only in S_WRITE.
    wire [3:0]  rf_wr_addr = (host_wr_en ? host_wr_addr : 4'd0) |
                              (internal_wr_en ? dst_r : 4'd0);
    wire [63:0] rf_wr_data = (host_wr_en ? host_wr_data : 64'd0) |
                              (internal_wr_en ? result : 64'd0);

    wire [63:0] rf_rd_a;
    wire [63:0] rf_rd_b;
    wire        rf_rd_valid;

    sdmc_regfile64 u_rf (
        .clk       (clk),
        .rst_n     (rst_n),
        .clear     (clear),

        .wr_en     (rf_wr_en),
        .wr_addr   (rf_wr_addr),
        .wr_data   (rf_wr_data),

        .rd_en     (rf_rd_en),
        .rd_addr_a (src_a_r),
        .rd_addr_b (src_b_r),
        .rd_data_a (rf_rd_a),
        .rd_data_b (rf_rd_b),
        .rd_valid  (rf_rd_valid),

        .r0        (r0),
        .r1        (r1),
        .r2        (r2),
        .r3        (r3),
        .r4        (r4)
    );

    wire alu_start = (state == S_ALU_FIRE);
    wire [63:0] alu_y;
    wire        alu_valid;

    sdmc_word_alu64 u_alu (
        .clk   (clk),
        .rst_n (rst_n),
        .clear (clear),

        .start (alu_start),
        .op    (op_r),
        .a     (alu_a_r),
        .b     (alu_b_r),
        .n     (n_r),

        .y     (alu_y),
        .valid (alu_valid)
    );

    reg        perm_host_wr_en;
    reg [2:0]  perm_host_wr_lane;
    reg [63:0] perm_host_wr_data;

    reg        perm_host_rd_en;
    reg [2:0]  perm_host_rd_lane;
    wire [63:0] perm_host_rd_data;
    wire        perm_host_rd_valid;

    reg        perm_start;
    reg [3:0]  perm_rounds;

    wire       perm_host_ready;
    wire       perm_busy;
    wire       perm_done;

    sdmc_ascon_perm_unit64 u_perm (
        .clk           (clk),
        .rst_n         (rst_n),
        .clear         (clear),

        .host_wr_en    (perm_host_wr_en),
        .host_wr_lane  (perm_host_wr_lane),
        .host_wr_data  (perm_host_wr_data),

        .host_rd_en    (perm_host_rd_en),
        .host_rd_lane  (perm_host_rd_lane),
        .host_rd_data  (perm_host_rd_data),
        .host_rd_valid (perm_host_rd_valid),

        .start         (perm_start),
        .rounds        (perm_rounds),

        .host_ready    (perm_host_ready),
        .busy          (perm_busy),
        .done          (perm_done),

        .x0            (p0),
        .x1            (p1),
        .x2            (p2),
        .x3            (p3),
        .x4            (p4)
    );

    assign cmd_ready  = (state == S_IDLE);
    assign host_ready = (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state             <= S_IDLE;
            type_r            <= CMD_ALU;
            op_r              <= 4'd0;
            dst_r             <= 4'd0;
            src_a_r           <= 4'd0;
            src_b_r           <= 4'd0;
            n_r               <= 4'd0;
            writeback_r       <= 1'b0;
            perm_lane_r       <= 3'd0;
            rounds_r          <= 4'd12;
            alu_a_r           <= 64'd0;
            alu_b_r           <= 64'd0;
            result            <= 64'd0;
            busy              <= 1'b0;
            done              <= 1'b0;
            perm_host_wr_en   <= 1'b0;
            perm_host_wr_lane <= 3'd0;
            perm_host_wr_data <= 64'd0;
            perm_host_rd_en   <= 1'b0;
            perm_host_rd_lane <= 3'd0;
            perm_start        <= 1'b0;
            perm_rounds       <= 4'd12;
        end else if (clear) begin
            state             <= S_IDLE;
            type_r            <= CMD_ALU;
            op_r              <= 4'd0;
            dst_r             <= 4'd0;
            src_a_r           <= 4'd0;
            src_b_r           <= 4'd0;
            n_r               <= 4'd0;
            writeback_r       <= 1'b0;
            perm_lane_r       <= 3'd0;
            rounds_r          <= 4'd12;
            alu_a_r           <= 64'd0;
            alu_b_r           <= 64'd0;
            result            <= 64'd0;
            busy              <= 1'b0;
            done              <= 1'b0;
            perm_host_wr_en   <= 1'b0;
            perm_host_wr_lane <= 3'd0;
            perm_host_wr_data <= 64'd0;
            perm_host_rd_en   <= 1'b0;
            perm_host_rd_lane <= 3'd0;
            perm_start        <= 1'b0;
            perm_rounds       <= 4'd12;
        end else begin
            done            <= 1'b0;
            perm_host_wr_en <= 1'b0;
            perm_host_rd_en <= 1'b0;
            perm_start      <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (cmd_valid) begin
                        type_r      <= cmd_type;
                        op_r        <= cmd_op;
                        dst_r       <= cmd_dst;
                        src_a_r     <= cmd_src_a;
                        src_b_r     <= cmd_src_b;
                        n_r         <= cmd_n;
                        writeback_r <= cmd_writeback;
                        perm_lane_r <= cmd_perm_lane;
                        rounds_r    <= cmd_rounds;
                        busy        <= 1'b1;

                        case (cmd_type)
                            CMD_ALU:      state <= S_READ;
                            CMD_PERM_WR:  state <= S_READ;
                            CMD_PERM_RUN: state <= S_PERM_RUN_FIRE;
                            CMD_PERM_RD:  state <= S_PERM_RD_FIRE;
                            default:      state <= S_DONE;
                        endcase
                    end
                end

                S_READ: begin
                    state <= S_WAIT_READ;
                end

                S_WAIT_READ: begin
                    if (rf_rd_valid) begin
                        alu_a_r <= rf_rd_a;
                        alu_b_r <= rf_rd_b;
                        if (type_r == CMD_PERM_WR) begin
                            state <= S_PERM_WR;
                        end else begin
                            state <= S_ALU_FIRE;
                        end
                    end
                end

                S_ALU_FIRE: begin
                    state <= S_ALU_WAIT;
                end

                S_ALU_WAIT: begin
                    if (alu_valid) begin
                        result <= alu_y;
                        if (writeback_r) begin
                            state <= S_WRITE;
                        end else begin
                            state <= S_DONE;
                        end
                    end
                end

                S_PERM_WR: begin
                    if (perm_host_ready) begin
                        perm_host_wr_en   <= 1'b1;
                        perm_host_wr_lane <= perm_lane_r;
                        perm_host_wr_data <= alu_a_r;
                        state             <= S_DONE;
                    end
                end

                S_PERM_RUN_FIRE: begin
                    if (perm_host_ready) begin
                        perm_rounds <= (rounds_r == 4'd0) ? 4'd12 : rounds_r;
                        perm_start  <= 1'b1;
                        state       <= S_PERM_RUN_WAIT;
                    end
                end

                S_PERM_RUN_WAIT: begin
                    if (perm_done) begin
                        state <= S_DONE;
                    end
                end

                S_PERM_RD_FIRE: begin
                    if (perm_host_ready) begin
                        perm_host_rd_en   <= 1'b1;
                        perm_host_rd_lane <= perm_lane_r;
                        state             <= S_PERM_RD_WAIT;
                    end
                end

                S_PERM_RD_WAIT: begin
                    if (perm_host_rd_valid) begin
                        result <= perm_host_rd_data;
                        if (writeback_r) begin
                            state <= S_WRITE;
                        end else begin
                            state <= S_DONE;
                        end
                    end
                end

                S_WRITE: begin
                    state <= S_DONE;
                end

                S_DONE: begin
                    done  <= 1'b1;
                    busy  <= 1'b0;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                    busy  <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
