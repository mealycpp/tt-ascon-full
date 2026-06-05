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


async def send_hash_cmd(dut, msg_len: int, out_len: int = 32):
    cmd = [
        0xA5,
        0x01,                  # HASH256 mode
        0x00,                  # flags
        0x00, 0x00,            # ad/custom len
        msg_len & 0xFF,
        (msg_len >> 8) & 0xFF,
        out_len & 0xFF,
        (out_len >> 8) & 0xFF,
        0x01, 0x00,            # chain count, ignored for HASH
        0x00, 0x00,            # reserved
        0x5A,
    ]
    for b in cmd:
        await uart_send_byte(dut, b)


def parse_verilog_int(token: str) -> int:
    token = token.strip().replace("_", "")
    m = re.match(r"(?:(\d+)\s*)?'([hHdDbB])([0-9a-fA-FxXzZ]+)", token)
    if m:
        base = m.group(2).lower()
        digits = m.group(3).lower().replace("x", "0").replace("z", "0")
        if base == "h":
            return int(digits, 16)
        if base == "d":
            return int(digits, 10)
        if base == "b":
            return int(digits, 2)
    return int(token, 10)


def parse_hash_uart_tb(tb_path: Path):
    text = tb_path.read_text()

    m = re.search(r"localparam\s+integer\s+MSG_LEN\s*=\s*(\d+)", text)
    if not m:
        raise RuntimeError(f"Cannot find MSG_LEN in {tb_path}")
    msg_len = int(m.group(1))

    msg = [None] * msg_len
    for mm in re.finditer(r"msg\[(\d+)\]\s*=\s*([^;]+);", text):
        idx = int(mm.group(1))
        if idx < msg_len:
            msg[idx] = parse_verilog_int(mm.group(2)) & 0xFF

    if msg_len == 0:
        msg = []
    elif any(x is None for x in msg):
        missing = [i for i, x in enumerate(msg) if x is None]
        raise RuntimeError(f"Incomplete msg bytes in {tb_path}: missing {missing[:10]}")

    exp = [None] * 32
    for em in re.finditer(r"exp_md\[(\d+)\]\s*=\s*([^;]+);", text):
        idx = int(em.group(1))
        if idx < 32:
            exp[idx] = parse_verilog_int(em.group(2)) & 0xFF

    if any(x is None for x in exp):
        raise RuntimeError(f"Incomplete exp_md bytes in {tb_path}")

    return {
        "name": tb_path.stem.replace("tb_", ""),
        "msg": bytes(msg),
        "expected": bytes(exp),
    }


@cocotb.test()
async def test_hash256_one_generated_top_uart_vector(dut):
    """Top-level UART HASH256: one generated Verilog KAT vector per simulation."""

    cocotb.start_soon(Clock(dut.clk, CLK_PERIOD_NS, unit="ns").start())

    tb_rel = os.environ.get(
        "HASH_TB",
        "test/sdmc_top_uart_hash_kat_massive/tb_hash_c0001_m0.v",
    )
    tb_path = REPO_ROOT / tb_rel
    vec = parse_hash_uart_tb(tb_path)

    await reset_dut(dut)

    rx_bytes = []
    capture = {"on": False}

    cocotb.start_soon(uart_rx_monitor(dut, rx_bytes, capture))
    capture["on"] = True

    msg = vec["msg"]
    expected = vec["expected"]

    start_ns = get_sim_time("ns")

    await send_hash_cmd(dut, msg_len=len(msg), out_len=32)
    for b in msg:
        await uart_send_byte(dut, b)

    timeout = 2_000_000
    while len(rx_bytes) < 32 and timeout > 0:
        timeout -= 1
        await RisingEdge(dut.clk)

    capture["on"] = False

    if len(rx_bytes) < 32:
        raise TimeoutError(f"HASH timeout name={vec['name']} got_bytes={len(rx_bytes)}")

    got = bytes(rx_bytes[:32])

    end_ns = get_sim_time("ns")
    cycles = int((end_ns - start_ns) // CLK_PERIOD_NS)

    got_hex = got.hex()
    exp_hex = expected.hex()

    dut._log.info("VECTOR HASH_TB=%s", tb_rel)
    dut._log.info("MSG_HEX name=%s msg_bytes=%d msg=%s", vec["name"], len(msg), msg.hex())
    dut._log.info("GOT_MD name=%s msg_bytes=%d got=%s", vec["name"], len(msg), got_hex)
    dut._log.info("EXP_MD name=%s msg_bytes=%d exp=%s", vec["name"], len(msg), exp_hex)

    assert got == expected, (
        f"HASH256 mismatch name={vec['name']} got={got_hex} exp={exp_hex}"
    )

    dut._log.info(
        "METRIC mode=HASH256 name=%s msg_bytes=%d cs_bytes=0 ad_bytes=0 "
        "out_bytes=32 chain_count=1 cycles=%d pass=1",
        vec["name"],
        len(msg),
        cycles,
    )
    dut._log.info("PASS HASH256_TOP_UART name=%s msg_bytes=%d", vec["name"], len(msg))
