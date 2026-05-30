#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(".")
OUTDIR = ROOT / "test" / "sdmc_top_uart_xof_cxof_kat_massive"
OUTDIR.mkdir(parents=True, exist_ok=True)

KATS = [
    {
        "family": "xof",
        "mode": 2,
        "path": ROOT / "kat/official/ascon-c/asconxof128_LWC_XOF_KAT_128_512.txt",
    },
    {
        "family": "cxof",
        "mode": 3,
        "path": ROOT / "kat/official/ascon-c/asconcxof128_LWC_CXOF_KAT_128_512.txt",
    },
]

def parse_blocks(path):
    text = path.read_text(errors="replace")
    chunks = re.split(r"\n\s*\n", text.strip())
    blocks = []
    for ch in chunks:
        d = {}
        for line in ch.splitlines():
            line = line.strip()
            if "=" not in line:
                continue
            k, v = line.split("=", 1)
            d[k.strip()] = v.strip().replace(" ", "")
        if "Count" in d and "Msg" in d and "MD" in d:
            blocks.append(d)
    return blocks

def hex_to_bytes(h):
    h = h.strip()
    if h == "":
        return []
    return list(bytes.fromhex(h))

def find_cs_bytes(block):
    # Official CXOF KAT naming varies by generator. Accept common field names.
    for key in ["Z", "Cust", "Custom", "CustomString", "Customization", "S", "N"]:
        if key in block:
            return hex_to_bytes(block[key])
    return []

def verilog_array_init(name, data):
    if not data:
        return ""
    return "\n".join(f"        {name}[{i}] = 8'h{b:02x};" for i, b in enumerate(data))

def gen_tb(family, mode, count, msg, cs, md):
    out_len = len(md)
    tb_base = f"{family}_c{count:04d}_m{len(msg)}_cs{len(cs)}_out{out_len}"
    tb_name = "tb_" + tb_base
    msg_decl = max(1, len(msg))
    cs_decl = max(1, len(cs))

    exp_init = "\n".join(f"        exp_md[{i}] = 8'h{b:02x};" for i, b in enumerate(md))

    return tb_base, f"""`timescale 1ns/1ps
`default_nettype none

module {tb_name};

    localparam integer CLK_HALF = 5;
    localparam integer BAUD_DIV = 217;
    localparam integer BIT_CYCLES = BAUD_DIV;

    localparam integer MODE = {mode};
    localparam integer MSG_LEN = {len(msg)};
    localparam integer CS_LEN = {len(cs)};
    localparam integer OUT_LEN = {out_len};
    localparam integer CHAIN_COUNT = 1;

    reg clk;
    reg rst_n;
    reg ena;
    reg [7:0] ui_in;
    wire [7:0] uo_out;
    reg [7:0] uio_in;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

    reg [7:0] msg [0:{msg_decl-1}];
    reg [7:0] cs  [0:{cs_decl-1}];
    reg [7:0] exp_md [0:{out_len-1}];
    reg [7:0] got_md [0:{out_len-1}];

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
                if (capture_md && md_rx_count < OUT_LEN) begin
                    got_md[md_rx_count] = b;
                    md_rx_count = md_rx_count + 1;
                end
            end
        end
    endtask

    task automatic send_cmd;
        begin
            uart_send_byte(8'hA5);
            uart_send_byte(MODE[7:0]);
            uart_send_byte(8'h00);
            uart_send_byte(8'h00);
            uart_send_byte(8'h00);
            uart_send_byte(MSG_LEN[7:0]);
            uart_send_byte(MSG_LEN[15:8]);
            uart_send_byte(OUT_LEN[7:0]);
            uart_send_byte(OUT_LEN[15:8]);
            uart_send_byte(CHAIN_COUNT[7:0]);
            uart_send_byte(CHAIN_COUNT[15:8]);
            uart_send_byte(CS_LEN[7:0]);
            uart_send_byte(CS_LEN[15:8]);
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

{verilog_array_init("msg", msg)}
{verilog_array_init("cs", cs)}
{exp_init}

        wait_cycles(20);
        rst_n = 1'b1;
        wait_cycles(100);

        fork
            uart_rx_monitor();
        join_none

        capture_md = 1'b1;

        $display("DBG {family.upper()}_TOP start name={tb_base} mode=%0d msg=%0d cs=%0d out=%0d",
                 MODE, MSG_LEN, CS_LEN, OUT_LEN);

        send_cmd();

        for (i = 0; i < CS_LEN; i = i + 1) begin
            uart_send_byte(cs[i]);
        end

        for (i = 0; i < MSG_LEN; i = i + 1) begin
            uart_send_byte(msg[i]);
        end

        while (md_rx_count < OUT_LEN && timeout_count < 8000000) begin
            timeout_count = timeout_count + 1;
            @(posedge clk);
        end

        capture_md = 1'b0;

        if (md_rx_count != OUT_LEN) begin
            $display("FAIL {family.upper()}_TOP_TIMEOUT name={tb_base} rx=%0d expected=%0d",
                     md_rx_count, OUT_LEN);
            errors = errors + 1;
        end

        for (i = 0; i < OUT_LEN; i = i + 1) begin
            if (got_md[i] !== exp_md[i]) begin
                if (errors == 0) begin
                    $display("FAIL {family.upper()}_TOP_FIRST_MISMATCH name={tb_base} idx=%0d got=%02x exp=%02x",
                             i, got_md[i], exp_md[i]);
                end
                errors = errors + 1;
            end
        end

        $write("GOT_{family.upper()}_TOP name={tb_base} got=");
        for (i = 0; i < OUT_LEN; i = i + 1) $write("%02x", got_md[i]);
        $display("");

        $write("EXP_{family.upper()}_TOP name={tb_base} exp=");
        for (i = 0; i < OUT_LEN; i = i + 1) $write("%02x", exp_md[i]);
        $display("");

        if (errors == 0)
            $display("PASS {family.upper()}_TOP name={tb_base} mode=%0d msg=%0d cs=%0d out=%0d",
                     MODE, MSG_LEN, CS_LEN, OUT_LEN);
        else
            $display("FAIL {family.upper()}_TOP name={tb_base} errors=%0d", errors);

        $finish;
    end

endmodule

`default_nettype wire
"""

manifest = []
for item in KATS:
    blocks = parse_blocks(item["path"])
    for b in blocks:
        count = int(b["Count"])
        msg = hex_to_bytes(b["Msg"])
        md = hex_to_bytes(b["MD"])
        cs = find_cs_bytes(b) if item["family"] == "cxof" else []
        name, tb = gen_tb(item["family"], item["mode"], count, msg, cs, md)
        (OUTDIR / f"tb_{name}.v").write_text(tb)
        manifest.append(name)

(OUTDIR / "manifest.txt").write_text("\n".join(manifest) + "\n")
print(f"Generated {len(manifest)} official XOF/CXOF top-UART KAT tests")
print(f"Manifest: {OUTDIR/'manifest.txt'}")
