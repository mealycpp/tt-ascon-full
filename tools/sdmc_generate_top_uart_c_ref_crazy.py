#!/usr/bin/env python3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "test/sdmc_top_uart_c_ref_crazy"
OUT.mkdir(parents=True, exist_ok=True)

CASES = [
    ("cref_ad0_pt0", 0, 0),
    ("cref_ad0_pt64", 0, 64),
    ("cref_ad1_pt255", 1, 255),
    ("cref_ad7_pt257", 7, 257),
    ("cref_ad8_pt256", 8, 256),
    ("cref_ad9_pt257", 9, 257),
    ("cref_ad15_pt255", 15, 255),
    ("cref_ad16_pt256", 16, 256),
    ("cref_ad17_pt257", 17, 257),
    ("cref_ad31_pt511", 31, 511),
    ("cref_ad32_pt512", 32, 512),
    ("cref_ad33_pt513", 33, 513),
    ("cref_ad127_pt255", 127, 255),
    ("cref_ad129_pt257", 129, 257),
]
def write_case(name, ad_len, pt_len):
    enc_out_len = pt_len + 16
    tb = OUT / f"tb_{name}.v"

    tb.write_text(f"""`timescale 1ns/1ps
`default_nettype none

module tb_{name};

    localparam integer RX_BIT_CYC = 208;
    localparam integer TX_BIT_CYC = 217;
    localparam integer AD_LEN = {ad_len};
    localparam integer PT_LEN = {pt_len};
    localparam integer ENC_OUT_LEN = {enc_out_len};

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

    reg [7:0] key   [0:15];
    reg [7:0] nonce [0:15];
    reg [7:0] ad    [0:AD_LEN+1];
    reg [7:0] pt    [0:PT_LEN+1];
    reg [7:0] enc   [0:ENC_OUT_LEN+1];
    reg [7:0] dec   [0:PT_LEN+1];

    integer i;
    integer enc_rx_count;
    integer dec_rx_count;

    task automatic wait_cycles;
        input integer n;
        integer j;
        begin
            for (j = 0; j < n; j = j + 1) @(posedge clk);
        end
    endtask

    task automatic uart_send_byte;
        input integer line;
        input [7:0] data;
        integer j;
        begin
            ui_in[line] = 1'b0;
            wait_cycles(RX_BIT_CYC);
            for (j = 0; j < 8; j = j + 1) begin
                ui_in[line] = data[j];
                wait_cycles(RX_BIT_CYC);
            end
            ui_in[line] = 1'b1;
            wait_cycles(RX_BIT_CYC);
            wait_cycles(RX_BIT_CYC);
        end
    endtask

    task automatic uart_recv_byte;
        output [7:0] data;
        integer j;
        begin
            // Wait for idle high, then synchronize to the next true start edge.
            // Do not simply wait for line==0; that can lock onto a data bit.
            wait (uo_out[2] == 1'b1);
            @(negedge uo_out[2]);

            // Move to the center of data bit 0.
            wait_cycles(TX_BIT_CYC + (TX_BIT_CYC/2));

            for (j = 0; j < 8; j = j + 1) begin
                data[j] = uo_out[2];
                wait_cycles(TX_BIT_CYC);
            end

            // We are now around the stop-bit center. Do not wait another full bit:
            // back-to-back UART bytes may begin immediately after the stop bit.
        end
    endtask

    task automatic send_cmd;
        input [7:0] mode;
        input [15:0] ad_n;
        input [15:0] data_n;
        begin
            uart_send_byte(0, 8'hA5);
            uart_send_byte(0, mode);
            uart_send_byte(0, (mode == 8'd6) ? 8'h04 : 8'h00);
            uart_send_byte(0, ad_n[7:0]);
            uart_send_byte(0, ad_n[15:8]);
            uart_send_byte(0, data_n[7:0]);
            uart_send_byte(0, data_n[15:8]);
            uart_send_byte(0, 8'h00);
            uart_send_byte(0, 8'h00);
            uart_send_byte(0, 8'h01);
            uart_send_byte(0, 8'h00);
            uart_send_byte(0, 8'h00);
            uart_send_byte(0, 8'h00);
            uart_send_byte(0, 8'h5A);
        end
    endtask

    task automatic send_key_nonce_ad;
        integer j;
        begin
            for (j = 0; j < 16; j = j + 1) uart_send_byte(1, key[j]);
            for (j = 0; j < 16; j = j + 1) uart_send_byte(1, nonce[j]);
            for (j = 0; j < AD_LEN; j = j + 1) uart_send_byte(1, ad[j]);
        end
    endtask

    initial begin
        for (i = 0; i < 16; i = i + 1) begin
            key[i] = i & 8'hff;
            nonce[i] = (i + 16) & 8'hff;
        end
        for (i = 0; i < AD_LEN; i = i + 1) begin
            ad[i] = (8'h80 + i) & 8'hff;
        end
        for (i = 0; i < PT_LEN; i = i + 1) begin
            pt[i] = (8'h20 + i) & 8'hff;
        end
    end

    initial begin
        // VCD intentionally disabled for long UART tests.

        enc_rx_count = 0;
        dec_rx_count = 0;

        ui_in = 8'h07;
        rst_n = 1'b0;
        wait_cycles(50);
        rst_n = 1'b1;
        wait_cycles(100);

        $display("DBG stage=enc_start AD=%0d PT=%0d expected_out=%0d t=%0t",
            AD_LEN, PT_LEN, ENC_OUT_LEN, $time);

        fork
            begin : enc_sender
                integer si;
                send_cmd(8'd5, AD_LEN[15:0], PT_LEN[15:0]);
                send_key_nonce_ad();
                for (si = 0; si < PT_LEN; si = si + 1) begin
                    uart_send_byte(2, pt[si]);
                end
                $display("DBG stage=enc_input_done t=%0t", $time);
            end

            begin : enc_receiver
                integer ri;
                for (ri = 0; ri < ENC_OUT_LEN; ri = ri + 1) begin
                    uart_recv_byte(enc[ri]);
                    enc_rx_count = enc_rx_count + 1;
                    if ((ri % 8) == 0 || ri == ENC_OUT_LEN-1) begin
                        $display("DBG enc_rx[%0d]=%02x busy=%b err=%b auth=%b phase=%0d t=%0t",
                            ri, enc[ri], uo_out[3], uo_out[5], uo_out[6], uio_out[3:0], $time);
                    end
                end
                $display("DBG stage=enc_output_done enc_rx=%0d/%0d t=%0t",
                    enc_rx_count, ENC_OUT_LEN, $time);
            end
        join

        $display("DBG stage=enc_done enc_rx=%0d/%0d t=%0t", enc_rx_count, ENC_OUT_LEN, $time);

        wait_cycles(1000);

        rst_n = 1'b0;
        ui_in = 8'h07;
        wait_cycles(50);
        rst_n = 1'b1;
        wait_cycles(100);

        $display("DBG stage=dec_start AD=%0d PT=%0d expected_out=%0d t=%0t",
            AD_LEN, PT_LEN, PT_LEN, $time);

        fork
            begin : dec_sender
                integer si;
                send_cmd(8'd6, AD_LEN[15:0], PT_LEN[15:0]);
                send_key_nonce_ad();
                for (si = 0; si < ENC_OUT_LEN; si = si + 1) begin
                    uart_send_byte(2, enc[si]);
                end
                $display("DBG stage=dec_input_done t=%0t", $time);
            end

            begin : dec_receiver
                integer ri;
                for (ri = 0; ri < PT_LEN; ri = ri + 1) begin
                    uart_recv_byte(dec[ri]);
                    dec_rx_count = dec_rx_count + 1;
                    if ((ri % 8) == 0 || ri == PT_LEN-1) begin
                        $display("DBG dec_rx[%0d]=%02x busy=%b err=%b auth=%b phase=%0d t=%0t",
                            ri, dec[ri], uo_out[3], uo_out[5], uo_out[6], uio_out[3:0], $time);
                    end
                end
                $display("DBG stage=dec_output_done dec_rx=%0d/%0d t=%0t",
                    dec_rx_count, PT_LEN, $time);
            end
        join

        for (i = 0; i < PT_LEN; i = i + 1) begin
            if (dec[i] !== pt[i]) begin
                $display("FAIL roundtrip mismatch idx=%0d got=%02x exp=%02x AD=%0d PT=%0d",
                    i, dec[i], pt[i], AD_LEN, PT_LEN);
                $finish;
            end
        end

        if (uo_out[5]) begin
            $display("FAIL error_sticky asserted AD=%0d PT=%0d", AD_LEN, PT_LEN);
            $finish;
        end

        $display("PASS {name} AD=%0d PT=%0d enc_rx=%0d/%0d dec_rx=%0d/%0d",
            AD_LEN, PT_LEN, enc_rx_count, ENC_OUT_LEN, dec_rx_count, PT_LEN);
        $finish;
    end

    initial begin
        wait_cycles(30000000);
        $display("FAIL timeout AD=%0d PT=%0d enc_rx=%0d/%0d dec_rx=%0d/%0d busy=%b err=%b auth=%b phase=%0d",
            AD_LEN, PT_LEN, enc_rx_count, ENC_OUT_LEN, dec_rx_count, PT_LEN,
            uo_out[3], uo_out[5], uo_out[6], uio_out[3:0]);
        $finish;
    end

endmodule

`default_nettype wire
""")

manifest = []
for name, ad_len, pt_len in CASES:
    write_case(name, ad_len, pt_len)
    manifest.append(name)

(OUT / "manifest.txt").write_text("\n".join(manifest) + "\n")
print(f"Generated {len(manifest)} long top UART roundtrip tests")
print(f"Manifest: {OUT / 'manifest.txt'}")
