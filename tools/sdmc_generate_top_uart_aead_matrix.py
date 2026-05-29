#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
KAT = ROOT / "kat/official/ascon-c/asconaead128_LWC_AEAD_KAT_128_128.txt"
OUT_ROOT = ROOT / "test/sdmc_top_uart_aead_matrix"

TARGET_PAIRS = [
    (0, 0),
    (1, 0), (7, 0), (8, 0), (9, 0), (15, 0), (16, 0), (17, 0), (31, 0), (32, 0),
    (0, 1), (0, 7), (0, 8), (0, 9), (0, 15), (0, 16), (0, 17), (0, 31), (0, 32),
    (1, 1), (7, 8), (8, 7), (8, 8), (15, 16), (16, 15), (16, 16), (17, 17),
    (31, 32), (32, 31),
]

def parse_cases(path):
    cases = []
    cur = {}
    for raw in path.read_text().splitlines():
        line = raw.strip()
        if not line:
            if cur:
                cases.append(cur)
                cur = {}
            continue
        if "=" in line:
            k, v = [x.strip() for x in line.split("=", 1)]
            cur[k] = v
    if cur:
        cases.append(cur)
    return cases

def v_uart_send_seq(line, hexstr):
    return "\n".join(f"        uart_send_byte({line}, 8'h{x:02x});" for x in bytes.fromhex(hexstr))

def expected_array_lines(hexstr):
    b = bytes.fromhex(hexstr)
    if not b:
        return "        // no expected output bytes"
    return "\n".join(f"        expected[{i}] = 8'h{x:02x};" for i, x in enumerate(b))

def write_tb(name, case, mode):
    key = case["Key"]
    nonce = case["Nonce"]
    ad = case.get("AD", "")
    pt = case.get("PT", "")
    ct_tag = case["CT"]
    ct = ct_tag[:-32]
    tag = ct_tag[-32:]

    ad_len = len(bytes.fromhex(ad))
    pt_len = len(bytes.fromhex(pt))
    ct_len = len(bytes.fromhex(ct))

    is_dec = mode in ("dec_good", "dec_bad")
    is_bad = mode == "dec_bad"

    if is_dec:
        msg_hex = ct
        tag_bytes = bytearray.fromhex(tag)
        if is_bad:
            tag_bytes[-1] ^= 0x01
        tag_hex = tag_bytes.hex()
        expected_hex = pt
        out_bytes = pt_len
        data_len = ct_len
        mode_byte = 6
        auth_expected = 0 if is_bad else 1
    else:
        msg_hex = pt
        tag_hex = ""
        expected_hex = ct_tag
        out_bytes = len(bytes.fromhex(ct_tag))
        data_len = pt_len
        mode_byte = 5
        auth_expected = 1

    d = OUT_ROOT / name
    d.mkdir(parents=True, exist_ok=True)
    tb = d / f"tb_{name}.v"

    tb.write_text(f"""`timescale 1ns/1ps
`default_nettype none

module tb_{name};

    // DUT UART RX effectively samples 217 >> 4 = 13, 13*16 = 208 cycles.
    localparam integer DUT_RX_BIT_CYC = 208;
    localparam integer DUT_TX_BIT_CYC = 217;
    localparam integer OUT_BYTES = {out_bytes};

    reg clk = 1'b0;
    reg rst_n = 1'b0;
    reg ena = 1'b1;

    reg [7:0] ui_in = 8'h07;
    reg [7:0] uio_in = 8'd0;
    wire [7:0] uo_out;
    wire [7:0] uio_out;
    wire [7:0] uio_oe;

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

    always #5 clk = ~clk;

    reg [7:0] expected [0:(OUT_BYTES > 0 ? OUT_BYTES-1 : 0)];
    reg [7:0] got      [0:(OUT_BYTES > 0 ? OUT_BYTES-1 : 0)];
    integer rx_count;
    integer k;

    initial begin
{expected_array_lines(expected_hex)}
    end

    task automatic wait_cycles;
        input integer n;
        integer i;
        begin
            for (i = 0; i < n; i = i + 1) @(posedge clk);
        end
    endtask

    task automatic uart_send_byte;
        input integer line;
        input [7:0] data;
        integer i;
        begin
            ui_in[line] = 1'b0;
            wait_cycles(DUT_RX_BIT_CYC);

            for (i = 0; i < 8; i = i + 1) begin
                ui_in[line] = data[i];
                wait_cycles(DUT_RX_BIT_CYC);
            end

            ui_in[line] = 1'b1;
            wait_cycles(DUT_RX_BIT_CYC);
            wait_cycles(DUT_RX_BIT_CYC);
        end
    endtask

    // Internal byte monitor: real serial UART inputs, direct byte handoff to uart_tx output.
    // This validates UART RX + frontend + AEAD + output serializer without serial TX sampling drift.
    always @(posedge clk) begin
        if (!rst_n) begin
            rx_count <= 0;
        end else if (dut.tx_send) begin
            if (rx_count < OUT_BYTES) begin
                got[rx_count] <= dut.tx_byte;
                rx_count <= rx_count + 1;
            end
        end
    end

    integer guard;

    initial begin
        // VCD disabled for matrix speed.
        // $dumpfile("tb_{name}.vcd");
        // $dumpvars(0, tb_{name});

        ui_in = 8'h07;
        rst_n = 1'b0;
        wait_cycles(50);
        rst_n = 1'b1;
        wait_cycles(100);

        // UART0 command frame.
        uart_send_byte(0, 8'hA5);
        uart_send_byte(0, 8'd{mode_byte});
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h{ad_len & 0xff:02x});
        uart_send_byte(0, 8'h{(ad_len >> 8) & 0xff:02x});
        uart_send_byte(0, 8'h{data_len & 0xff:02x});
        uart_send_byte(0, 8'h{(data_len >> 8) & 0xff:02x});
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h01);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h00);
        uart_send_byte(0, 8'h5A);

        // UART1: key, nonce, AD.
{v_uart_send_seq(1, key)}
{v_uart_send_seq(1, nonce)}
{v_uart_send_seq(1, ad)}

        // UART2 input: plaintext/ciphertext, then tag for decrypt.
{v_uart_send_seq(2, msg_hex)}
{v_uart_send_seq(2, tag_hex)}

        guard = 0;
        while (rx_count < OUT_BYTES && guard < 3000000) begin
            wait_cycles(1);
            guard = guard + 1;
        end

        wait_cycles(2000);

        if (dut.uo_out[5]) begin
            $display("FAIL error_sticky Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}");
            $finish;
        end

        if (rx_count !== OUT_BYTES) begin
            $display("FAIL output bytes=%0d expected=%0d Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len} auth=%b busy=%b",
                rx_count, OUT_BYTES, uo_out[6], uo_out[3]);
            $finish;
        end

        for (k = 0; k < OUT_BYTES; k = k + 1) begin
            if (got[k] !== expected[k]) begin
                $display("FAIL byte mismatch idx=%0d got=%02x exp=%02x Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}",
                    k, got[k], expected[k]);
                $finish;
            end
        end

        if (uo_out[6] !== 1'b{auth_expected}) begin
            $display("FAIL auth_ok=%b expected={auth_expected} Count={case['Count']} mode={mode} AD={ad_len} PT={pt_len}",
                uo_out[6]);
            $finish;
        end

        $display("PASS {name}");
        $finish;
    end

endmodule

`default_nettype wire
""")

def main():
    OUT_ROOT.mkdir(parents=True, exist_ok=True)
    cases = parse_cases(KAT)

    selected = []
    for ad_len, pt_len in TARGET_PAIRS:
        match = None
        for c in cases:
            ad = c.get("AD", "")
            pt = c.get("PT", "")
            if len(bytes.fromhex(ad)) == ad_len and len(bytes.fromhex(pt)) == pt_len:
                match = c
                break
        if match is None:
            raise SystemExit(f"missing case AD={ad_len} PT={pt_len}")
        selected.append(match)

    names = []
    for c in selected:
        ad_len = len(bytes.fromhex(c.get("AD", "")))
        pt_len = len(bytes.fromhex(c.get("PT", "")))
        base = f"sdmc_top_uart_kat_c{int(c['Count']):03d}_ad{ad_len}_pt{pt_len}"
        for suffix, mode in [("enc", "enc"), ("dec", "dec_good"), ("badtag", "dec_bad")]:
            name = f"{base}_{suffix}"
            write_tb(name, c, mode)
            names.append(name)

    (OUT_ROOT / "manifest.txt").write_text("\n".join(names) + "\n")
    print(f"Generated {len(names)} top UART AEAD matrix tests")
    print(f"Manifest: {OUT_ROOT / 'manifest.txt'}")

if __name__ == "__main__":
    main()
