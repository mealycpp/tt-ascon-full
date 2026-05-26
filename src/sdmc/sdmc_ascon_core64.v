`default_nettype none

module sdmc_ascon_core64 (
    input  wire        clk,
    input  wire        rst_n,

    input  wire        issue_valid,
    input  wire [2:0]  issue_op,
    input  wire [2:0]  issue_lane,
    input  wire [63:0] issue_wdata,

    output reg         issue_ready,

    output reg  [63:0] read_data,
    output reg         read_valid,

    output reg         perm_busy,
    output reg         perm_done,

    output wire [63:0] dbg_x0,
    output wire [63:0] dbg_x1,
    output wire [63:0] dbg_x2,
    output wire [63:0] dbg_x3,
    output wire [63:0] dbg_x4
);

    localparam OP_NOP    = 3'd0;
    localparam OP_CLEAR  = 3'd1;
    localparam OP_LOAD   = 3'd2;
    localparam OP_XOR    = 3'd3;
    localparam OP_READ   = 3'd4;
    localparam OP_PERM12 = 3'd5;

    reg [63:0] x0;
    reg [63:0] x1;
    reg [63:0] x2;
    reg [63:0] x3;
    reg [63:0] x4;

    reg [3:0] round_idx;

    assign dbg_x0 = x0;
    assign dbg_x1 = x1;
    assign dbg_x2 = x2;
    assign dbg_x3 = x3;
    assign dbg_x4 = x4;

    function [7:0] round_constant;
        input [3:0] r;
        begin
            case (r)
                4'd0:  round_constant = 8'hf0;
                4'd1:  round_constant = 8'he1;
                4'd2:  round_constant = 8'hd2;
                4'd3:  round_constant = 8'hc3;
                4'd4:  round_constant = 8'hb4;
                4'd5:  round_constant = 8'ha5;
                4'd6:  round_constant = 8'h96;
                4'd7:  round_constant = 8'h87;
                4'd8:  round_constant = 8'h78;
                4'd9:  round_constant = 8'h69;
                4'd10: round_constant = 8'h5a;
                4'd11: round_constant = 8'h4b;
                default: round_constant = 8'h00;
            endcase
        end
    endfunction

    wire [319:0] round_state_in  = {x4, x3, x2, x1, x0};
    wire [319:0] round_state_out;

    ascon_round u_round (
        .state_in    (round_state_in),
        .round_const (round_constant(round_idx)),
        .state_out   (round_state_out)
    );

    wire [63:0] next_x0 = round_state_out[63:0];
    wire [63:0] next_x1 = round_state_out[127:64];
    wire [63:0] next_x2 = round_state_out[191:128];
    wire [63:0] next_x3 = round_state_out[255:192];
    wire [63:0] next_x4 = round_state_out[319:256];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            x0          <= 64'd0;
            x1          <= 64'd0;
            x2          <= 64'd0;
            x3          <= 64'd0;
            x4          <= 64'd0;
            round_idx   <= 4'd0;
            read_data   <= 64'd0;
            read_valid  <= 1'b0;
            perm_busy   <= 1'b0;
            perm_done   <= 1'b0;
            issue_ready <= 1'b1;
        end else begin
            read_valid  <= 1'b0;
            perm_done   <= 1'b0;
            issue_ready <= !perm_busy;

            if (perm_busy) begin
                x0 <= next_x0;
                x1 <= next_x1;
                x2 <= next_x2;
                x3 <= next_x3;
                x4 <= next_x4;

                if (round_idx == 4'd11) begin
                    round_idx <= 4'd0;
                    perm_busy <= 1'b0;
                    perm_done <= 1'b1;
                end else begin
                    round_idx <= round_idx + 4'd1;
                end
            end else if (issue_valid) begin
                case (issue_op)
                    OP_NOP: begin
                    end

                    OP_CLEAR: begin
                        x0 <= 64'd0;
                        x1 <= 64'd0;
                        x2 <= 64'd0;
                        x3 <= 64'd0;
                        x4 <= 64'd0;
                    end

                    OP_LOAD: begin
                        case (issue_lane)
                            3'd0: x0 <= issue_wdata;
                            3'd1: x1 <= issue_wdata;
                            3'd2: x2 <= issue_wdata;
                            3'd3: x3 <= issue_wdata;
                            3'd4: x4 <= issue_wdata;
                            default: ;
                        endcase
                    end

                    OP_XOR: begin
                        case (issue_lane)
                            3'd0: x0 <= x0 ^ issue_wdata;
                            3'd1: x1 <= x1 ^ issue_wdata;
                            3'd2: x2 <= x2 ^ issue_wdata;
                            3'd3: x3 <= x3 ^ issue_wdata;
                            3'd4: x4 <= x4 ^ issue_wdata;
                            default: ;
                        endcase
                    end

                    OP_READ: begin
                        case (issue_lane)
                            3'd0: read_data <= x0;
                            3'd1: read_data <= x1;
                            3'd2: read_data <= x2;
                            3'd3: read_data <= x3;
                            3'd4: read_data <= x4;
                            default: read_data <= 64'd0;
                        endcase
                        read_valid <= 1'b1;
                    end

                    OP_PERM12: begin
                        round_idx <= 4'd0;
                        perm_busy <= 1'b1;
                    end

                    default: begin
                    end
                endcase
            end
        end
    end

endmodule

`default_nettype wire
