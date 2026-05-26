`default_nettype none

module sdmc_uop_exec64 (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        clear,

    input  wire        host_wr_en,
    input  wire [3:0]  host_wr_addr,
    input  wire [63:0] host_wr_data,
    output wire        host_ready,

    input  wire        cmd_valid,
    output wire        cmd_ready,
    input  wire [3:0]  cmd_op,
    input  wire [3:0]  cmd_dst,
    input  wire [3:0]  cmd_src_a,
    input  wire [3:0]  cmd_src_b,
    input  wire [3:0]  cmd_n,
    input  wire        cmd_writeback,

    output reg         busy,
    output reg         done,
    output reg  [63:0] result,

    output wire [63:0] r0,
    output wire [63:0] r1,
    output wire [63:0] r2,
    output wire [63:0] r3,
    output wire [63:0] r4
);

    localparam S_IDLE      = 3'd0;
    localparam S_READ      = 3'd1;
    localparam S_WAIT_READ = 3'd2;
    localparam S_ALU_FIRE  = 3'd3;
    localparam S_ALU_WAIT  = 3'd4;
    localparam S_WRITE     = 3'd5;
    localparam S_DONE      = 3'd6;

    reg [2:0] state;

    reg [3:0]  op_r;
    reg [3:0]  dst_r;
    reg [3:0]  src_a_r;
    reg [3:0]  src_b_r;
    reg [3:0]  n_r;
    reg        writeback_r;

    reg [63:0] alu_a_r;
    reg [63:0] alu_b_r;

    wire rf_rd_en = (state == S_READ);

    wire rf_wr_en = host_wr_en || (state == S_WRITE);
    wire [3:0]  rf_wr_addr = host_wr_en ? host_wr_addr : dst_r;
    wire [63:0] rf_wr_data = host_wr_en ? host_wr_data : result;

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

    assign cmd_ready  = (state == S_IDLE);
    assign host_ready = (state == S_IDLE);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state       <= S_IDLE;
            op_r        <= 4'd0;
            dst_r       <= 4'd0;
            src_a_r     <= 4'd0;
            src_b_r     <= 4'd0;
            n_r         <= 4'd0;
            writeback_r <= 1'b0;
            alu_a_r     <= 64'd0;
            alu_b_r     <= 64'd0;
            result      <= 64'd0;
            busy        <= 1'b0;
            done        <= 1'b0;
        end else if (clear) begin
            state       <= S_IDLE;
            op_r        <= 4'd0;
            dst_r       <= 4'd0;
            src_a_r     <= 4'd0;
            src_b_r     <= 4'd0;
            n_r         <= 4'd0;
            writeback_r <= 1'b0;
            alu_a_r     <= 64'd0;
            alu_b_r     <= 64'd0;
            result      <= 64'd0;
            busy        <= 1'b0;
            done        <= 1'b0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (cmd_valid) begin
                        op_r        <= cmd_op;
                        dst_r       <= cmd_dst;
                        src_a_r     <= cmd_src_a;
                        src_b_r     <= cmd_src_b;
                        n_r         <= cmd_n;
                        writeback_r <= cmd_writeback;
                        busy        <= 1'b1;
                        state       <= S_READ;
                    end
                end

                S_READ: begin
                    state <= S_WAIT_READ;
                end

                S_WAIT_READ: begin
                    if (rf_rd_valid) begin
                        alu_a_r <= rf_rd_a;
                        alu_b_r <= rf_rd_b;
                        state   <= S_ALU_FIRE;
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
