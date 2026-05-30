#!/usr/bin/env python3
from pathlib import Path
import re

ROOT = Path(".")
SRC_MANIFEST = ROOT / "test/sdmc_chain_vector_matrix/manifest.txt"
SRC_DIR = ROOT / "test/sdmc_chain_vector_matrix"
OUTDIR = ROOT / "test/sdmc_top_uart_chain_boundary"
OUTDIR.mkdir(parents=True, exist_ok=True)

MSG_SET = {"empty", "m1", "m8", "m16", "m17", "m32"}
CHAIN_SET = {"1", "2", "5", "16"}
OUT_SET = {"32"}

def wanted(name):
    mx = re.fullmatch(r"sdmc_xof_chain_(empty|m\d+)_c(\d+)_out(\d+)", name)
    if mx:
        return mx.group(1) in MSG_SET and mx.group(2) in CHAIN_SET and mx.group(3) in OUT_SET

    mc = re.fullmatch(r"sdmc_cxof_chain_z0_(empty|m\d+)_c(\d+)_out(\d+)", name)
    if mc:
        return mc.group(1) in MSG_SET and mc.group(2) in CHAIN_SET and mc.group(3) in OUT_SET

    return False

def parse_int_param(text, name):
    m = re.search(rf"\.{name}\s*\(\s*16'd(\d+)\s*\)", text)
    if not m:
        raise ValueError(f"missing {name}")
    return int(m.group(1))

def parse_bool_param(text, name):
    m = re.search(rf"\.{name}\s*\(\s*1'b([01])\s*\)", text)
    if not m:
        raise ValueError(f"missing {name}")
    return int(m.group(1)) == 1

def parse_expected(text):
    m = re.search(r"got\s*!==\s*256'h([0-9a-fA-F]+)", text)
    if not m:
        raise ValueError("missing expected 256'h digest")
    return m.group(1).lower()

def word_to_bytes_le(hexword, count):
    x = int(hexword, 16)
    return [(x >> (8*i)) & 0xff for i in range(count)]

def parse_tokens(text):
    msg = []
    cs = []
    pat = re.compile(
        r"token_mem\[\d+\]\s*=\s*\{\s*[^,]+,\s*`(SDMC_TOK_MSG|SDMC_TOK_CS)\s*,\s*4'd(\d+)\s*,\s*64'h([0-9a-fA-F]+)\s*\}\s*;"
    )
    for kind, count_s, word in pat.findall(text):
        data = word_to_bytes_le(word, int(count_s))
        if kind == "SDMC_TOK_MSG":
            msg.extend(data)
        elif kind == "SDMC_TOK_CS":
            cs.extend(data)
    return msg, cs

def verilog_array_init(arr_name, data):
    if not data:
        return ""
    return "\n".join(f"        {arr_name}[{i}] = 8'h{b:02x};" for i, b in enumerate(data))

def verilog_exp_init(exp_hex):
    # Core vector compares little-endian byte lanes packed into 256'h.
    # UART receives byte stream in lane order, so reverse printed hex bytes.
    bs = bytes.fromhex(exp_hex)[::-1]
    return "\n".join(f"        exp_md[{i}] = 8'h{b:02x};" for i, b in enumerate(bs))

def gen_tb(case):
    src = SRC_DIR / case / f"tb_{case}.v"
    text = src.read_text()

    use_cxof = parse_bool_param(text, "use_cxof")
    chain_count = parse_int_param(text, "chain_count")
    msg_len = parse_int_param(text, "msg_len")
    cs_len = parse_int_param(text, "cs_len")
    out_len = parse_int_param(text, "out_len")
    exp_hex = parse_expected(text)
    msg, cs = parse_tokens(text)

    if len(msg) != msg_len:
        raise ValueError(f"{case}: msg parsed={len(msg)} expected={msg_len}")
    if len(cs) != cs_len:
        raise ValueError(f"{case}: cs parsed={len(cs)} expected={cs_len}")
    if out_len != 32:
        raise ValueError(f"{case}: expected out_len=32, got {out_len}")

    if use_cxof:
        mode = 7 if chain_count > 1 else 3
    else:
        mode = 4 if chain_count > 1 else 2

    tb_name = "tb_top_uart_" + case
    msg_decl = max(1, len(msg))
    cs_decl = max(1, len(cs))

    return f"""`timescale 1ns/1ps
`default_nettype none

module {tb_name};

    localparam integer CLK_HALF = 5;
    localparam integer BAUD_DIV = 217;
    localparam integer BIT_CYCLES = BAUD_DIV;

    localparam integer MODE = {mode};
    localparam integer MSG_LEN = {len(msg)};
    localparam integer CS_LEN = {len(cs)};
    localparam integer OUT_LEN = 32;
    localparam integer CHAIN_COUNT = {chain_count};

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
    reg [7:0] exp_md [0:31];
    reg [7:0] got_md [0:31];

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
{verilog_exp_init(exp_hex)}

        wait_cycles(20);
        rst_n = 1'b1;
        wait_cycles(100);

        fork
            uart_rx_monitor();
        join_none

        capture_md = 1'b1;

        $display("DBG CHAIN_TOP start name={case} mode=%0d msg=%0d cs=%0d chain=%0d out=%0d",
                 MODE, MSG_LEN, CS_LEN, CHAIN_COUNT, OUT_LEN);

        send_cmd();

        for (i = 0; i < CS_LEN; i = i + 1) uart_send_byte(cs[i]);
        for (i = 0; i < MSG_LEN; i = i + 1) uart_send_byte(msg[i]);

        while (md_rx_count < OUT_LEN && timeout_count < 6000000) begin
            timeout_count = timeout_count + 1;
            @(posedge clk);
        end

        capture_md = 1'b0;

        if (md_rx_count != OUT_LEN) begin
            $display("FAIL CHAIN_TOP_TIMEOUT name={case} rx=%0d expected=%0d", md_rx_count, OUT_LEN);
            errors = errors + 1;
        end

        for (i = 0; i < OUT_LEN; i = i + 1) begin
            if (got_md[i] !== exp_md[i]) begin
                if (errors == 0) begin
                    $display("FAIL CHAIN_TOP_FIRST_MISMATCH name={case} idx=%0d got=%02x exp=%02x",
                             i, got_md[i], exp_md[i]);
                end
                errors = errors + 1;
            end
        end

        $write("GOT_CHAIN_TOP name={case} got=");
        for (i = 0; i < OUT_LEN; i = i + 1) $write("%02x", got_md[i]);
        $display("");

        $write("EXP_CHAIN_TOP name={case} exp=");
        for (i = 0; i < OUT_LEN; i = i + 1) $write("%02x", exp_md[i]);
        $display("");

        if (errors == 0)
            $display("PASS CHAIN_TOP name={case} mode=%0d msg=%0d cs=%0d chain=%0d out=%0d",
                     MODE, MSG_LEN, CS_LEN, CHAIN_COUNT, OUT_LEN);
        else
            $display("FAIL CHAIN_TOP name={case} errors=%0d", errors);

        $finish;
    end

endmodule

`default_nettype wire
"""

cases = [x.strip() for x in SRC_MANIFEST.read_text().splitlines() if x.strip()]
selected = [c for c in cases if wanted(c)]

manifest = []
for case in selected:
    tb = gen_tb(case)
    name = "top_uart_" + case
    (OUTDIR / f"tb_{name}.v").write_text(tb)
    manifest.append(name)

(OUTDIR / "manifest.txt").write_text("\n".join(manifest) + "\n")
print(f"Generated {len(manifest)} derived chain top-UART boundary tests")
print(f"Manifest: {OUTDIR/'manifest.txt'}")
