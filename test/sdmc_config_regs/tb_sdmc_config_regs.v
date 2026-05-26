`timescale 1ns/1ps
`default_nettype none

`include "sdmc_modes.vh"

module tb_sdmc_config_regs;

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg clear = 1'b0;
    always #5 clk = ~clk;

    reg        cfg_wr_en = 1'b0;
    reg [3:0]  cfg_wr_addr = 4'd0;
    reg [63:0] cfg_wr_data = 64'd0;

    wire [3:0]  host_mode;
    wire [3:0]  program_id;
    wire        use_cxof;
    wire        is_decrypt;
    wire [15:0] chain_count;
    wire [15:0] msg_len;
    wire [15:0] cs_len;
    wire [15:0] ad_len;
    wire [15:0] out_len;

    sdmc_config_regs dut (
        .clk(clk),
        .rst_n(rst_n),
        .clear(clear),
        .cfg_wr_en(cfg_wr_en),
        .cfg_wr_addr(cfg_wr_addr),
        .cfg_wr_data(cfg_wr_data),
        .host_mode(host_mode),
        .program_id(program_id),
        .use_cxof(use_cxof),
        .is_decrypt(is_decrypt),
        .chain_count(chain_count),
        .msg_len(msg_len),
        .cs_len(cs_len),
        .ad_len(ad_len),
        .out_len(out_len)
    );

    task tick;
        begin
            @(negedge clk);
        end
    endtask

    task cfg_write;
        input [3:0] addr;
        input [63:0] data;
        begin
            cfg_wr_addr = addr;
            cfg_wr_data = data;
            cfg_wr_en   = 1'b1;
            tick();
            cfg_wr_en   = 1'b0;
            cfg_wr_addr = 4'd0;
            cfg_wr_data = 64'd0;
            tick();
        end
    endtask

    task check_fail;
        input cond;
        input [255:0] msg;
        begin
            if (cond) begin
                $display("FAIL %0s", msg);
                $finish;
            end
        end
    endtask

    initial begin
        $dumpfile("tb_sdmc_config_regs.vcd");
        $dumpvars(0, tb_sdmc_config_regs);

        repeat (5) tick();
        rst_n = 1'b1;
        repeat (2) tick();

        check_fail(program_id !== `SDMC_PROG_HASH_FAMILY, "reset program");
        check_fail(chain_count !== 16'd1, "reset chain");
        check_fail(out_len !== 16'd32, "reset out_len");

        cfg_write(4'd0, {60'd0, `SDMC_HOST_XOF});
        check_fail(program_id !== `SDMC_PROG_XOF_CHAIN_FAMILY, "xof program");
        check_fail(use_cxof !== 1'b0, "xof cxof flag");
        check_fail(chain_count !== 16'd1, "xof chain count");

        cfg_write(4'd0, {60'd0, `SDMC_HOST_CXOF});
        check_fail(program_id !== `SDMC_PROG_XOF_CHAIN_FAMILY, "cxof program");
        check_fail(use_cxof !== 1'b1, "cxof flag");
        check_fail(chain_count !== 16'd1, "cxof chain count");

        cfg_write(4'd2, 64'd5);
        cfg_write(4'd0, {60'd0, `SDMC_HOST_XOF_CHAIN});
        check_fail(program_id !== `SDMC_PROG_XOF_CHAIN_FAMILY, "xof chain program");
        check_fail(use_cxof !== 1'b0, "xof chain cxof flag");
        check_fail(chain_count !== 16'd5, "xof chain count keep");

        cfg_write(4'd2, 64'd0);
        check_fail(chain_count !== 16'd1, "chain zero clamp");

        cfg_write(4'd2, 64'd7);
        cfg_write(4'd0, {60'd0, `SDMC_HOST_CXOF_CHAIN});
        check_fail(program_id !== `SDMC_PROG_XOF_CHAIN_FAMILY, "cxof chain program");
        check_fail(use_cxof !== 1'b1, "cxof chain flag");
        check_fail(chain_count !== 16'd7, "cxof chain count keep");

        cfg_write(4'd0, {60'd0, `SDMC_HOST_AEAD_ENC});
        check_fail(program_id !== `SDMC_PROG_AEAD_FAMILY, "aead enc program");
        check_fail(is_decrypt !== 1'b0, "aead enc decrypt flag");

        cfg_write(4'd0, {60'd0, `SDMC_HOST_AEAD_DEC});
        check_fail(program_id !== `SDMC_PROG_AEAD_FAMILY, "aead dec program");
        check_fail(is_decrypt !== 1'b1, "aead dec decrypt flag");

        cfg_write(4'd1, {16'd64, 16'd9, 16'd5, 16'd3});
        check_fail(msg_len !== 16'd3, "msg len");
        check_fail(cs_len  !== 16'd5, "cs len");
        check_fail(ad_len  !== 16'd9, "ad len");
        check_fail(out_len !== 16'd64, "out len");

        clear = 1'b1;
        tick();
        clear = 1'b0;
        tick();

        check_fail(program_id !== `SDMC_PROG_HASH_FAMILY, "clear program");
        check_fail(chain_count !== 16'd1, "clear chain");
        check_fail(is_decrypt !== 1'b0, "clear decrypt");

        $display("PASS sdmc_config_regs");
        $finish;
    end

endmodule

`default_nettype wire
