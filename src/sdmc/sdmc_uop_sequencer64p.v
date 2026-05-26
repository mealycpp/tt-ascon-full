`default_nettype none

`include "sdmc_modes.vh"

module sdmc_uop_sequencer64p (
    input  wire       clk,
    input  wire       rst_n,
    input  wire       clear,

    input  wire       start,
    input  wire [3:0] program_id,

    output reg        cmd_valid,
    input  wire       cmd_ready,
    output reg [1:0]  cmd_type,
    output reg [3:0]  cmd_op,
    output reg [3:0]  cmd_dst,
    output reg [3:0]  cmd_src_a,
    output reg [3:0]  cmd_src_b,
    output reg [3:0]  cmd_n,
    output reg        cmd_writeback,
    output reg [2:0]  cmd_perm_lane,
    output reg [3:0]  cmd_rounds,

    input  wire       exec_done,

    output reg        busy,
    output reg        done
);

    localparam CMD_ALU      = 4'd0;
    localparam CMD_PERM_WR  = 4'd1;
    localparam CMD_PERM_RUN = 2'd2;
    localparam CMD_PERM_RD  = 2'd3;

    localparam OP_ZERO = 4'd0;
    localparam OP_XOR  = 4'd2;

    localparam S_IDLE  = 3'd0;
    localparam S_LOAD  = 3'd1;
    localparam S_ISSUE = 3'd2;
    localparam S_WAIT  = 3'd3;
    localparam S_DONE  = 3'd4;

    reg [2:0] state;
    reg [3:0] program_id_r;
    reg [4:0] pc;
    reg       instr_last;

    task set_nop;
        begin
            cmd_type      = CMD_ALU;
            cmd_op        = OP_ZERO;
            cmd_dst       = 4'd0;
            cmd_src_a     = 4'd0;
            cmd_src_b     = 4'd0;
            cmd_n         = 4'd0;
            cmd_writeback = 1'b0;
            cmd_perm_lane = 3'd0;
            cmd_rounds    = 4'd12;
            instr_last    = 1'b1;
        end
    endtask

    task load_instr;
        input [3:0] pid;
        input [4:0] addr;
        begin
            set_nop();

            case (pid)
                // Program 0: register state -> permutation -> register state
                4'd0: begin
                    case (addr)
                        5'd0: begin cmd_type=CMD_PERM_WR;  cmd_src_a=4'd0; cmd_perm_lane=3'd0; instr_last=1'b0; end
                        5'd1: begin cmd_type=CMD_PERM_WR;  cmd_src_a=4'd1; cmd_perm_lane=3'd1; instr_last=1'b0; end
                        5'd2: begin cmd_type=CMD_PERM_WR;  cmd_src_a=4'd2; cmd_perm_lane=3'd2; instr_last=1'b0; end
                        5'd3: begin cmd_type=CMD_PERM_WR;  cmd_src_a=4'd3; cmd_perm_lane=3'd3; instr_last=1'b0; end
                        5'd4: begin cmd_type=CMD_PERM_WR;  cmd_src_a=4'd4; cmd_perm_lane=3'd4; instr_last=1'b0; end
                        5'd5: begin cmd_type=CMD_PERM_RUN; cmd_rounds=4'd12; instr_last=1'b0; end
                        5'd6: begin cmd_type=CMD_PERM_RD;  cmd_dst=4'd0; cmd_perm_lane=3'd0; cmd_writeback=1'b1; instr_last=1'b0; end
                        5'd7: begin cmd_type=CMD_PERM_RD;  cmd_dst=4'd1; cmd_perm_lane=3'd1; cmd_writeback=1'b1; instr_last=1'b0; end
                        5'd8: begin cmd_type=CMD_PERM_RD;  cmd_dst=4'd2; cmd_perm_lane=3'd2; cmd_writeback=1'b1; instr_last=1'b0; end
                        5'd9: begin cmd_type=CMD_PERM_RD;  cmd_dst=4'd3; cmd_perm_lane=3'd3; cmd_writeback=1'b1; instr_last=1'b0; end
                        5'd10: begin cmd_type=CMD_PERM_RD; cmd_dst=4'd4; cmd_perm_lane=3'd4; cmd_writeback=1'b1; instr_last=1'b1; end
                        default: set_nop();
                    endcase
                end

                // Program 1: tiny ALU sanity program, R3 = R0 xor R1
                4'd1: begin
                    case (addr)
                        5'd0: begin
                            cmd_type      = CMD_ALU;
                            cmd_op        = OP_XOR;
                            cmd_dst       = 4'd3;
                            cmd_src_a     = 4'd0;
                            cmd_src_b     = 4'd1;
                            cmd_writeback = 1'b1;
                            instr_last    = 1'b1;
                        end
                        default: set_nop();
                    endcase
                end

                default: set_nop();
            endcase
        end
    endtask

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state        <= S_IDLE;
            program_id_r <= 4'd0;
            pc           <= 5'd0;
            cmd_valid    <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
            set_nop();
        end else if (clear) begin
            state        <= S_IDLE;
            program_id_r <= 4'd0;
            pc           <= 5'd0;
            cmd_valid    <= 1'b0;
            busy         <= 1'b0;
            done         <= 1'b0;
            set_nop();
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    cmd_valid <= 1'b0;
                    busy      <= 1'b0;
                    if (start) begin
                        program_id_r <= program_id;
                        pc           <= 5'd0;
                        busy         <= 1'b1;
                        state        <= S_LOAD;
                    end
                end

                S_LOAD: begin
                    load_instr(program_id_r, pc);
                    state <= S_ISSUE;
                end

                S_ISSUE: begin
                    cmd_valid <= 1'b1;
                    if (cmd_ready) begin
                        state <= S_WAIT;
                    end
                end

                S_WAIT: begin
                    cmd_valid <= 1'b0;
                    if (exec_done) begin
                        if (instr_last) begin
                            state <= S_DONE;
                        end else begin
                            pc    <= pc + 5'd1;
                            state <= S_LOAD;
                        end
                    end
                end

                S_DONE: begin
                    busy  <= 1'b0;
                    done  <= 1'b1;
                    state <= S_IDLE;
                end

                default: begin
                    state     <= S_IDLE;
                    cmd_valid <= 1'b0;
                    busy      <= 1'b0;
                end
            endcase
        end
    end

endmodule

`default_nettype wire
