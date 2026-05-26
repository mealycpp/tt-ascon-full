`default_nettype none

module sdmc_micro_smoke (
    input  wire clk,
    input  wire rst_n,

    input  wire start,
    output reg  busy,
    output reg  done,

    output reg         issue_valid,
    output reg  [2:0]  issue_op,
    output reg  [2:0]  issue_lane,
    output reg  [63:0] issue_wdata,
    input  wire        issue_ready,

    input  wire [63:0] read_data,
    input  wire        read_valid,
    input  wire        perm_done,

    output reg  [63:0] result_x0
);

    localparam OP_NOP    = 3'd0;
    localparam OP_CLEAR  = 3'd1;
    localparam OP_LOAD   = 3'd2;
    localparam OP_XOR    = 3'd3;
    localparam OP_READ   = 3'd4;
    localparam OP_PERM12 = 3'd5;

    localparam [63:0] CXOF128_IV = 64'h0000_0800_00CC_0004;

    localparam S_IDLE      = 4'd0;
    localparam S_CLEAR     = 4'd1;
    localparam S_LOAD_X0   = 4'd2;
    localparam S_PERM12    = 4'd3;
    localparam S_WAIT_PERM = 4'd4;
    localparam S_READ_X0   = 4'd5;
    localparam S_WAIT_READ = 4'd6;
    localparam S_DONE      = 4'd7;

    reg [3:0] state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            busy         <= 1'b0;
            done         <= 1'b0;
            issue_valid  <= 1'b0;
            issue_op     <= OP_NOP;
            issue_lane   <= 3'd0;
            issue_wdata  <= 64'd0;
            result_x0    <= 64'd0;
        end else begin
            done        <= 1'b0;
            issue_valid <= 1'b0;
            issue_op    <= OP_NOP;
            issue_lane  <= 3'd0;
            issue_wdata <= 64'd0;

            case (state)
                S_IDLE: begin
                    busy <= 1'b0;
                    if (start) begin
                        busy  <= 1'b1;
                        state <= S_CLEAR;
                    end
                end

                S_CLEAR: begin
                    if (issue_ready) begin
                        issue_valid <= 1'b1;
                        issue_op    <= OP_CLEAR;
                        state       <= S_LOAD_X0;
                    end
                end

                S_LOAD_X0: begin
                    if (issue_ready) begin
                        issue_valid <= 1'b1;
                        issue_op    <= OP_LOAD;
                        issue_lane  <= 3'd0;
                        issue_wdata <= CXOF128_IV;
                        state       <= S_PERM12;
                    end
                end

                S_PERM12: begin
                    if (issue_ready) begin
                        issue_valid <= 1'b1;
                        issue_op    <= OP_PERM12;
                        state       <= S_WAIT_PERM;
                    end
                end

                S_WAIT_PERM: begin
                    if (perm_done) begin
                        state <= S_READ_X0;
                    end
                end

                S_READ_X0: begin
                    if (issue_ready) begin
                        issue_valid <= 1'b1;
                        issue_op    <= OP_READ;
                        issue_lane  <= 3'd0;
                        state       <= S_WAIT_READ;
                    end
                end

                S_WAIT_READ: begin
                    if (read_valid) begin
                        result_x0 <= read_data;
                        state     <= S_DONE;
                    end
                end

                S_DONE: begin
                    busy <= 1'b0;
                    done <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state <= S_IDLE;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
