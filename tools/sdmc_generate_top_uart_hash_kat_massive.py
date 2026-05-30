#!/usr/bin/env python3
from pathlib import Path
import re

KAT = Path("kat/official/ascon-c/asconhash256_LWC_HASH_KAT_128_256.txt")
OUT = Path("test/sdmc_top_uart_hash_kat_massive")

def parse_kat(path: Path):
    text = path.read_text()
    blocks = re.split(r"\n\s*\n", text.strip())
    cases = []
    for b in blocks:
        d = {}
        for line in b.splitlines():
            if "=" in line:
                k, v = line.split("=", 1)
                d[k.strip()] = v.strip()
        if "Count" in d and "Msg" in d and "MD" in d:
            cases.append((int(d["Count"]), bytes.fromhex(d["Msg"]), bytes.fromhex(d["MD"])))
    return cases

def init_array(name, data):
    return "\n".join(f"        {name}[{i}] = 8'h{b:02x};" for i, b in enumerate(data))

def write_tb(count, msg, md):
    name = f"hash_c{count:04d}_m{len(msg)}"
    tb = OUT / f"tb_{name}.v"
    msg_hi = max(len(msg) - 1, 0)
    md_hi = len(md) - 1

    tb.write_text(f"""`timescale 1ns/1ps
`default_nettype none

module tb_{name};

    localparam integer CLK_HALF = 5;
    localparam integer BAUD_DIV = 217;
    localparam integer BIT_CYCLES = BAUD_DIV;
    localparam integer MSG_LEN = {len(msg)};
    localparam integer MD_LEN = 32;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [7:0] msg [0:{msg_hi}];
    reg [7:0] exp_md [0:{md_hi}];
    reg [7:0] got_md [0:{md_hi}];

    integer i;
    integer errors;
    integer md_rx_count;
    integer timeout_count;
    reg capture_md;

    tt_um_mealycpp_ascon_sdmc_uart dut (
        .ui_in(ui_in),
        .uo_out(uo_out),
        .uio_in(uio_in),
        .uio_out(uio_out),
        .uio_oe(uio_oe),
        .ena(ena),
        .clk(clk),
        .rst_n(rst_n)
    );

    initial begin
        clk = 1'b0;
        forever #CLK_HALF clk = ~clk;
    end

    task automatic wait_cycles;
        input integer n;
        integer k;
        begin
            for (k = 0; k < n; k = k + 1) @(posedge clk);
        end
    endtask

    task automatic uart_send_byte;
        input [7:0] b;
        integer bi;
        begin
            ui_in[0] = 1'b0;
            wait_cycles(BIT_CYCLES);
            for (bi = 0; bi < 8; bi = bi + 1) begin
                ui_in[0] = b[bi];
                wait_cycles(BIT_CYCLES);
            end
            ui_in[0] = 1'b1;
            wait_cycles(BIT_CYCLES);
        end
    endtask

    task automatic uart_recv_byte;
        output [7:0] b;
        integer bi;
        begin
            while (uo_out[0] !== 1'b0) @(posedge clk);
            wait_cycles(BIT_CYCLES + (BIT_CYCLES/2));
            for (bi = 0; bi < 8; bi = bi + 1) begin
                b[bi] = uo_out[0];
                wait_cycles(BIT_CYCLES);
            end
            wait_cycles(BIT_CYCLES/2);
        end
    endtask

    task automatic uart_rx_monitor;
        reg [7:0] b;
        begin
            forever begin
                uart_recv_byte(b);
                if (capture_md && md_rx_count < MD_LEN) begin
                    got_md[md_rx_count] = b;
                    md_rx_count = md_rx_count + 1;
                end
            end
        end
    endtask

    task automatic send_hash_cmd;
        begin
            uart_send_byte(8'hA5);
            uart_send_byte(8'd1);              // HASH256 mode
            uart_send_byte(8'h00);             // flags
            uart_send_byte(8'h00);             // ad/custom len lo
            uart_send_byte(8'h00);             // ad/custom len hi
            uart_send_byte(MSG_LEN[7:0]);      // msg len lo
            uart_send_byte(MSG_LEN[15:8]);     // msg len hi
            uart_send_byte(8'd32);             // out len lo
            uart_send_byte(8'h00);             // out len hi
            uart_send_byte(8'h01);             // chain count lo, ignored
            uart_send_byte(8'h00);             // chain count hi
            uart_send_byte(8'h00);             // reserved
            uart_send_byte(8'h00);             // reserved
            uart_send_byte(8'h5A);
        end
    endtask

    initial begin
        errors = 0;
        md_rx_count = 0;
        timeout_count = 0;
        capture_md = 1'b0;
        ui_in = 8'hff;
        uio_in = 8'h00;
        ena = 1'b1;
        rst_n = 1'b0;

{init_array("msg", msg) if len(msg) else "        // empty message"}
{init_array("exp_md", md)}

        wait_cycles(20);
        rst_n = 1'b1;
        wait_cycles(100);

        fork
            uart_rx_monitor();
        join_none

        capture_md = 1'b1;

        $display("DBG HASH start name=hash_c{count:04d}_m{len(msg)} Count={count} MSG_LEN=%0d t=%0t", MSG_LEN, $time);

        send_hash_cmd();

        for (i = 0; i < MSG_LEN; i = i + 1) begin
            uart_send_byte(msg[i]);
        end

        while (md_rx_count < MD_LEN && timeout_count < 2000000) begin
            timeout_count = timeout_count + 1;
            @(posedge clk);
        end

        capture_md = 1'b0;

        if (md_rx_count != MD_LEN) begin
            $display("FAIL HASH_TIMEOUT name=hash_c{count:04d}_m{len(msg)} Count={count} MSG_LEN=%0d md_rx_count=%0d",
                     MSG_LEN, md_rx_count);
            errors = errors + 1;
        end

        for (i = 0; i < MD_LEN; i = i + 1) begin
            if (got_md[i] !== exp_md[i]) begin
                if (errors == 0) begin
                    $display("FAIL HASH_FIRST_MISMATCH name=hash_c{count:04d}_m{len(msg)} Count={count} MSG_LEN=%0d idx=%0d got_byte=%02x exp_byte=%02x",
                             MSG_LEN, i, got_md[i], exp_md[i]);
                end
                errors = errors + 1;
            end
        end

        $write("GOT_MD name=hash_c{count:04d}_m{len(msg)} Count={count} MSG_LEN=%0d got=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", got_md[i]);
        $display("");

        $write("EXP_MD name=hash_c{count:04d}_m{len(msg)} Count={count} MSG_LEN=%0d exp=", MSG_LEN);
        for (i = 0; i < MD_LEN; i = i + 1) $write("%02x", exp_md[i]);
        $display("");

        if (errors == 0)
            $display("PASS HASH_KAT name=hash_c{count:04d}_m{len(msg)} Count={count} MSG_LEN=%0d MD_LEN=32", MSG_LEN);
        else
            $display("FAIL HASH_KAT name=hash_c{count:04d}_m{len(msg)} Count={count} MSG_LEN=%0d errors=%0d", MSG_LEN, errors);

        $finish;
    end

endmodule

`default_nettype wire
""")
    return name

def main():
    OUT.mkdir(parents=True, exist_ok=True)
    cases = parse_kat(KAT)
    manifest = [write_tb(count, msg, md) for count, msg, md in cases]
    (OUT / "manifest.txt").write_text("\n".join(manifest) + "\n")
    print(f"Generated {len(manifest)} HASH KAT top-UART tests")
    print(f"Manifest: {OUT / 'manifest.txt'}")

if __name__ == "__main__":
    main()
