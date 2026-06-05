import os
import re
from pathlib import Path

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge
from cocotb.utils import get_sim_time


CLK_PERIOD_NS = 10
BIT_CYCLES = 217
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


def parse_localparam(text: str, name: str) -> int:
    m = re.search(rf"localparam\s+integer\s+{name}\s*=\s*(\d+)", text)
    if not m:
        raise RuntimeError(f"Missing localparam {name}")
    return int(m.group(1))


def parse_array(text: str, arr_name: str, n: int):
    if n == 0:
        return bytes()

    vals = [None] * n
    for mm in re.finditer(rf"{arr_name}\[(\d+)\]\s*=\s*([^;]+);", text):
        idx = int(mm.group(1))
        if idx < n:
            vals[idx] = parse_verilog_int(mm.group(2)) & 0xFF

    if any(v is None for v in vals):
        missing = [i for i, v in enumerate(vals) if v is None]
        raise RuntimeError(f"Incomplete {arr_name}: missing {missing[:10]}")

    return bytes(vals)


def parse_chain_tb(tb_path: Path):
    text = tb_path.read_text()

    mode = parse_localparam(text, "MODE")
    msg_len = parse_localparam(text, "MSG_LEN")
    cs_len = parse_localparam(text, "CS_LEN")
    out_len = parse_localparam(text, "OUT_LEN")
    chain_count = parse_localparam(text, "CHAIN_COUNT")

    if mode == 2:
        mode_name = "XOF_CHAIN"
    elif mode == 3:
        mode_name = "CXOF_CHAIN"
    else:
        raise RuntimeError(f"Unexpected mode {mode} in {tb_path}")

    return {
        "name": tb_path.stem.replace("tb_", ""),
        "mode": mode,
        "mode_name": mode_name,
        "msg": parse_array(text, "msg", msg_len),
        "cs": parse_array(text, "cs", cs_len),
        "out_len": out_len,
        "chain_count": chain_count,
        "expected": parse_array(text, "exp_md", out_len),
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
    await wait_cycles(dut, BIT_CYCLES)

    for i in range(8):
        set_uart_rx_bit(dut, (b >> i) & 1)
        await wait_cycles(dut, BIT_CYCLES)

    set_uart_rx_bit(dut, 1)
    await wait_cycles(dut, BIT_CYCLES)


async def uart_recv_byte(dut) -> int:
    while get_uart_tx_bit(dut) != 0:
        await RisingEdge(dut.clk)

    await wait_cycles(dut, BIT_CYCLES + (BIT_CYCLES // 2))

    value = 0
    for i in range(8):
        value |= (get_uart_tx_bit(dut) << i)
        await wait_cycles(dut, BIT_CYCLES)

    await wait_cycles(dut, BIT_CYCLES // 2)
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


async def send_chain_cmd(dut, vec):
    msg_len = len(vec["msg"])
    cs_len = len(vec["cs"])
    out_len = vec["out_len"]
    chain_count = vec["chain_count"]

    cmd = [
        0xA5,
        vec["mode"] & 0xFF,
        0x00,
        0x00, 0x00,
        msg_len & 0xFF,
        (msg_len >> 8) & 0xFF,
        out_len & 0xFF,
        (out_len >> 8) & 0xFF,
        chain_count & 0xFF,
        (chain_count >> 8) & 0xFF,
        cs_len & 0xFF,
        (cs_len >> 8) & 0xFF,
        0x5A,
    ]

    for b in cmd:
        await uart_send_byte(dut, b)


@cocotb.test()
async def test_chain_one_generated_top_uart_vector(dut):
    """Top-level UART XOF-chain/CXOF-chain generated KAT vector."""

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    tb_rel = os.environ.get(
        "CHAIN_TB",
        "test/sdmc_top_uart_chain_boundary/sdmc_xof_chain_empty_c1_out32/tb_sdmc_xof_chain_empty_c1_out32.v",
    )
    tb_path = REPO_ROOT / tb_rel
    vec = parse_chain_tb(tb_path)

    await reset_dut(dut)

    rx_bytes = []
    capture = {"on": False}
    cocotb.start_soon(uart_rx_monitor(dut, rx_bytes, capture))
    capture["on"] = True

    start_ns = get_sim_time("ns")

    await send_chain_cmd(dut, vec)

    # Generated chain TB sends customization string first, then message.
    for b in vec["cs"]:
        await uart_send_byte(dut, b)
    for b in vec["msg"]:
        await uart_send_byte(dut, b)

    timeout = 8_000_000
    while len(rx_bytes) < vec["out_len"] and timeout > 0:
        timeout -= 1
        await RisingEdge(dut.clk)

    capture["on"] = False

    if len(rx_bytes) < vec["out_len"]:
        raise TimeoutError(
            f"CHAIN timeout name={vec['name']} got_bytes={len(rx_bytes)} expected={vec['out_len']}"
        )

    got = bytes(rx_bytes[:vec["out_len"]])
    expected = vec["expected"]

    end_ns = get_sim_time("ns")
    cycles = int((end_ns - start_ns) // CLK_PERIOD_NS)

    dut._log.info("VECTOR CHAIN_TB=%s", tb_rel)
    dut._log.info(
        "INPUT_HEX mode=%s name=%s msg_bytes=%d cs_bytes=%d chain_count=%d msg=%s cs=%s",
        vec["mode_name"], vec["name"], len(vec["msg"]), len(vec["cs"]),
        vec["chain_count"], vec["msg"].hex(), vec["cs"].hex()
    )
    dut._log.info("GOT_CHAIN_TOP name=%s got=%s", vec["name"], got.hex())
    dut._log.info("EXP_CHAIN_TOP name=%s exp=%s", vec["name"], expected.hex())

    assert got == expected, (
        f"CHAIN mismatch name={vec['name']} got={got.hex()} exp={expected.hex()}"
    )

    dut._log.info(
        "METRIC mode=%s name=%s msg_bytes=%d cs_bytes=%d ad_bytes=0 "
        "out_bytes=%d chain_count=%d cycles=%d pass=1",
        vec["mode_name"], vec["name"], len(vec["msg"]), len(vec["cs"]),
        vec["out_len"], vec["chain_count"], cycles,
    )
    dut._log.info(
        "PASS CHAIN_TOP_UART name=%s mode=%s msg_bytes=%d cs_bytes=%d out_bytes=%d chain_count=%d",
        vec["name"], vec["mode_name"], len(vec["msg"]), len(vec["cs"]),
        vec["out_len"], vec["chain_count"]
    )
