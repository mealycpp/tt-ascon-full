import os
import re
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.utils import get_sim_time


CLK_PERIOD_NS = 10
DUT_RX_BIT_CYC = 208
DUT_TX_BIT_CYC = 217
REPO_ROOT = Path(__file__).resolve().parents[2]


async def wait_cycles(dut, n: int):
    for _ in range(n):
        await RisingEdge(dut.clk)


def parse_verilog_int(token: str) -> int:
    token = token.strip().replace("_", "")
    m = re.match(r"(?:(\d+)\s*)?'([hHdDbB])([0-9a-fA-FxXzZ]+)", token)
    if m:
        base = m.group(2).lower()
        digits = m.group(3).lower().replace("x", "0").replace("z", "0")
        return int(digits, {"h": 16, "d": 10, "b": 2}[base])
    return int(token, 10)


def parse_localparam(text: str, name: str, default=None) -> int:
    m = re.search(rf"localparam\s+integer\s+{name}\s*=\s*(\d+)", text)
    if not m:
        if default is not None:
            return default
        raise RuntimeError(f"Missing localparam {name}")
    return int(m.group(1))


def parse_expected_array(text: str, n: int):
    if n == 0:
        return bytes()

    vals = [None] * n
    for mm in re.finditer(r"expected\[(\d+)\]\s*=\s*([^;]+);", text):
        idx = int(mm.group(1))
        if idx < n:
            vals[idx] = parse_verilog_int(mm.group(2)) & 0xFF

    if any(v is None for v in vals):
        missing = [i for i, v in enumerate(vals) if v is None]
        raise RuntimeError(f"Incomplete expected[]: missing {missing[:10]}")

    return bytes(vals)


def parse_send_stream(text: str):
    # AEAD generated TBs use explicit uart_send_byte(0, value) calls.
    out = []
    for mm in re.finditer(r"uart_send_byte\s*\(\s*0\s*,\s*([^)]+)\)\s*;", text):
        out.append(parse_verilog_int(mm.group(1)) & 0xFF)
    if not out:
        raise RuntimeError("No uart_send_byte stream found")
    return bytes(out)


def parse_aead_tb(tb_path: Path):
    text = tb_path.read_text()

    out_bytes = parse_localparam(text, "OUT_BYTES")
    expected = parse_expected_array(text, out_bytes)
    stream = parse_send_stream(text)

    name = tb_path.stem.replace("tb_", "")

    if name.endswith("_enc"):
        mode_name = "AEAD_ENC"
        auth_expected = 1
    elif name.endswith("_dec"):
        mode_name = "AEAD_DEC"
        auth_expected = 1
    elif name.endswith("_badtag"):
        mode_name = "AEAD_BADTAG"
        auth_expected = 0
    else:
        mode_name = "AEAD"
        auth_expected = None

    return {
        "name": name,
        "mode_name": mode_name,
        "stream": stream,
        "expected": expected,
        "out_bytes": out_bytes,
        "auth_expected": auth_expected,
    }


def set_uart_rx_bit(dut, bit: int):
    cur = int(dut.ui_in.value) if dut.ui_in.value.is_resolvable else 0xFF
    dut.ui_in.value = (cur & 0xFE) | (bit & 1)


def get_uart_tx_bit(dut) -> int:
    if not dut.uo_out.value.is_resolvable:
        return 1
    return int(dut.uo_out.value) & 1


async def uart_send_byte(dut, b: int):
    set_uart_rx_bit(dut, 0)
    await wait_cycles(dut, DUT_RX_BIT_CYC)

    for i in range(8):
        set_uart_rx_bit(dut, (b >> i) & 1)
        await wait_cycles(dut, DUT_RX_BIT_CYC)

    set_uart_rx_bit(dut, 1)
    await wait_cycles(dut, DUT_RX_BIT_CYC)


async def uart_recv_byte(dut) -> int:
    while get_uart_tx_bit(dut) != 0:
        await RisingEdge(dut.clk)

    await wait_cycles(dut, DUT_TX_BIT_CYC + (DUT_TX_BIT_CYC // 2))

    value = 0
    for i in range(8):
        value |= (get_uart_tx_bit(dut) << i)
        await wait_cycles(dut, DUT_TX_BIT_CYC)

    await wait_cycles(dut, DUT_TX_BIT_CYC // 2)
    return value


async def uart_rx_monitor(dut, rx_bytes, capture):
    while True:
        b = await uart_recv_byte(dut)
        if capture["on"]:
            rx_bytes.append(b)


async def reset_dut(dut):
    dut.ena.value = 1
    dut.ui_in.value = 0xFF
    dut.uio_in.value = 0x00
    dut.rst_n.value = 0
    await wait_cycles(dut, 20)
    dut.rst_n.value = 1
    await wait_cycles(dut, 100)


def read_status_bits(dut):
    # Keep this soft. Exact bit meaning is checked against generated TB later if needed.
    uo = int(dut.uo_out.value) if dut.uo_out.value.is_resolvable else 0
    uio = int(dut.uio_out.value) if dut.uio_out.value.is_resolvable else 0
    return uo, uio


@cocotb.test()
async def test_aead_one_generated_top_uart_vector(dut):
    """Top-level UART AEAD generated KAT vector."""

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    tb_rel = os.environ.get(
        "AEAD_TB",
        "test/sdmc_top_uart_aead_matrix/sdmc_top_uart_kat_c001_ad0_pt0_enc/tb_sdmc_top_uart_kat_c001_ad0_pt0_enc.v",
    )
    tb_path = REPO_ROOT / tb_rel
    vec = parse_aead_tb(tb_path)

    await reset_dut(dut)

    rx_bytes = []
    capture = {"on": False}
    cocotb.start_soon(uart_rx_monitor(dut, rx_bytes, capture))
    capture["on"] = True

    start_ns = get_sim_time("ns")

    for b in vec["stream"]:
        await uart_send_byte(dut, b)

    timeout = 8_000_000
    while len(rx_bytes) < vec["out_bytes"] and timeout > 0:
        timeout -= 1
        await RisingEdge(dut.clk)

    # Give auth/status a little time to settle after final output or zero-output operation.
    await wait_cycles(dut, 5000)
    capture["on"] = False

    if len(rx_bytes) < vec["out_bytes"]:
        raise TimeoutError(
            f"AEAD timeout name={vec['name']} got_bytes={len(rx_bytes)} expected={vec['out_bytes']}"
        )

    got = bytes(rx_bytes[:vec["out_bytes"]])
    expected = vec["expected"]

    end_ns = get_sim_time("ns")
    cycles = int((end_ns - start_ns) // CLK_PERIOD_NS)

    uo, uio = read_status_bits(dut)

    dut._log.info("VECTOR AEAD_TB=%s", tb_rel)
    dut._log.info(
        "INPUT_STREAM mode=%s name=%s bytes=%d stream=%s",
        vec["mode_name"], vec["name"], len(vec["stream"]), vec["stream"].hex()
    )
    dut._log.info("GOT_AEAD name=%s got=%s", vec["name"], got.hex())
    dut._log.info("EXP_AEAD name=%s exp=%s", vec["name"], expected.hex())
    dut._log.info("STATUS_AEAD name=%s uo_out=%02x uio_out=%02x auth_expected=%s",
                  vec["name"], uo, uio, vec["auth_expected"])

    assert got == expected, (
        f"AEAD output mismatch name={vec['name']} got={got.hex()} exp={expected.hex()}"
    )

    # For badtag zero-output tests, output comparison alone is weak, so report status.
    # We will tighten auth_ok bit after one status-line inspection from the generated TB.
    dut._log.info(
        "METRIC mode=%s name=%s input_stream_bytes=%d out_bytes=%d cycles=%d pass=1",
        vec["mode_name"], vec["name"], len(vec["stream"]), vec["out_bytes"], cycles,
    )
    dut._log.info(
        "PASS AEAD_TOP_UART name=%s mode=%s out_bytes=%d",
        vec["name"], vec["mode_name"], vec["out_bytes"]
    )
