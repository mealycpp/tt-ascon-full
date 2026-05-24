"""Protocol parser tests: 14-byte fixed control frame decoder.

Frame layout (locked):
  B0  SOF = 0xA5
  B1  MODE (1..7 valid; 0 and 8..0xFF rejected)
  B2  FLAGS (bit0=chain_enable, bit1=chain_debug, bit2=is_decrypt)
  B3-4   AD_LEN (LE)
  B5-6   DATA_LEN (LE)
  B7-8   OUT_LEN (LE)
  B9-10  CHAIN_CNT (LE)
  B11-12 CS_BITS (LE)
  B13 EOF = 0x5A
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

def build_frame(mode, flags=0, ad=0, data=0, out=0, chain_cnt=0, cs_bits=0,
                sof=0xA5, eof=0x5A):
    return bytes([
        sof,
        mode,
        flags,
        ad & 0xFF, (ad >> 8) & 0xFF,
        data & 0xFF, (data >> 8) & 0xFF,
        out & 0xFF, (out >> 8) & 0xFF,
        chain_cnt & 0xFF, (chain_cnt >> 8) & 0xFF,
        cs_bits & 0xFF, (cs_bits >> 8) & 0xFF,
        eof
    ])

async def reset(dut):
    dut.rst_n.value = 0
    dut.in_byte.value = 0
    dut.in_byte_valid.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def send_byte(dut, b):
    """Send 1 byte respecting parser's in_byte_ready handshake."""
    while True:
        await RisingEdge(dut.clk)
        if int(dut.in_byte_ready.value) == 1:
            break
    dut.in_byte.value = b
    dut.in_byte_valid.value = 1
    await RisingEdge(dut.clk)
    dut.in_byte_valid.value = 0

async def send_frame(dut, frame_bytes):
    for b in frame_bytes:
        await send_byte(dut, b)

async def wait_for_pulse(dut, signal, timeout_cycles=200):
    """Return True if signal pulses high within timeout; sample each cycle."""
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if int(signal.value) == 1:
            return True
    return False


@cocotb.test()
async def test_valid_hash256(dut):
    """Mode=1, minimal frame."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = build_frame(mode=1)
    cocotb.start_soon(send_frame(dut, frame))
    assert await wait_for_pulse(dut, dut.frame_valid), "frame_valid never pulsed"
    # On next cycle, start should pulse and outputs should hold
    assert int(dut.mode_sel.value) == 1
    assert int(dut.is_decrypt.value) == 0
    assert int(dut.chain_enable.value) == 0
    assert int(dut.ad_total_bytes.value) == 0
    assert int(dut.data_total_bytes.value) == 0
    assert await wait_for_pulse(dut, dut.start), "start never pulsed"
    assert int(dut.frame_error.value) == 0
    dut._log.info("PASS valid_hash256")


@cocotb.test()
async def test_valid_aead_encrypt(dut):
    """Mode=5 (AEAD_ENC), AD=16, DATA=32, flags=0 (encrypt)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = build_frame(mode=5, flags=0, ad=16, data=32)
    cocotb.start_soon(send_frame(dut, frame))
    assert await wait_for_pulse(dut, dut.frame_valid)
    assert int(dut.mode_sel.value) == 5
    assert int(dut.is_decrypt.value) == 0
    assert int(dut.ad_total_bytes.value) == 16
    assert int(dut.data_total_bytes.value) == 32
    assert await wait_for_pulse(dut, dut.start)
    dut._log.info("PASS valid_aead_encrypt")


@cocotb.test()
async def test_valid_aead_decrypt(dut):
    """Mode=6 (AEAD_DEC), is_decrypt flag set."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = build_frame(mode=6, flags=0b00000100, ad=8, data=24)  # bit2=is_decrypt
    cocotb.start_soon(send_frame(dut, frame))
    assert await wait_for_pulse(dut, dut.frame_valid)
    assert int(dut.mode_sel.value) == 6
    assert int(dut.is_decrypt.value) == 1
    assert int(dut.ad_total_bytes.value) == 8
    assert int(dut.data_total_bytes.value) == 24
    assert await wait_for_pulse(dut, dut.start)
    dut._log.info("PASS valid_aead_decrypt")


@cocotb.test()
async def test_valid_cxof_chain(dut):
    """Mode=4 (CXOF_CHAIN), chain_enable + chain_count + cs_bits."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    frame = build_frame(mode=4, flags=0b00000001, data=5, out=32,
                        chain_cnt=2, cs_bits=24)
    cocotb.start_soon(send_frame(dut, frame))
    assert await wait_for_pulse(dut, dut.frame_valid)
    assert int(dut.mode_sel.value) == 4
    assert int(dut.chain_enable.value) == 1
    assert int(dut.chain_count.value) == 2
    assert int(dut.cs_total_bits.value) == 24
    assert int(dut.out_length.value) == 32
    assert int(dut.data_total_bytes.value) == 5
    assert await wait_for_pulse(dut, dut.start)
    dut._log.info("PASS valid_cxof_chain")


@cocotb.test()
async def test_bad_sof_then_valid(dut):
    """Garbage 0xFF before valid frame: parser should resync on next 0xA5."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # Send junk bytes, then a valid frame
    junk = bytes([0xFF, 0x12, 0x34])
    frame = build_frame(mode=2, ad=4, data=8)
    cocotb.start_soon(send_frame(dut, junk + frame))
    assert await wait_for_pulse(dut, dut.frame_valid, timeout_cycles=500)
    assert int(dut.mode_sel.value) == 2
    assert int(dut.ad_total_bytes.value) == 4
    assert int(dut.data_total_bytes.value) == 8
    assert int(dut.frame_error.value) == 0
    dut._log.info("PASS bad_sof_then_valid (resync ok)")


@cocotb.test()
async def test_bad_eof(dut):
    """Frame with bad EOF: parser asserts frame_error, no start."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    bad_frame = build_frame(mode=1, eof=0xFF)
    cocotb.start_soon(send_frame(dut, bad_frame))
    assert await wait_for_pulse(dut, dut.frame_error), "frame_error never pulsed"
    # Verify start did NOT pulse (give it a few cycles to be sure)
    for _ in range(20):
        await RisingEdge(dut.clk)
        assert int(dut.start.value) == 0, "start pulsed on bad EOF"
    dut._log.info("PASS bad_eof")


@cocotb.test()
async def test_invalid_mode_0(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    bad_frame = build_frame(mode=0)
    cocotb.start_soon(send_frame(dut, bad_frame))
    assert await wait_for_pulse(dut, dut.frame_error)
    for _ in range(20):
        await RisingEdge(dut.clk)
        assert int(dut.start.value) == 0
    dut._log.info("PASS invalid_mode_0")


@cocotb.test()
async def test_invalid_mode_8(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    bad_frame = build_frame(mode=8)
    cocotb.start_soon(send_frame(dut, bad_frame))
    assert await wait_for_pulse(dut, dut.frame_error)
    for _ in range(20):
        await RisingEdge(dut.clk)
        assert int(dut.start.value) == 0
    dut._log.info("PASS invalid_mode_8")


@cocotb.test()
async def test_invalid_mode_ff(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    bad_frame = build_frame(mode=0xFF)
    cocotb.start_soon(send_frame(dut, bad_frame))
    assert await wait_for_pulse(dut, dut.frame_error)
    for _ in range(20):
        await RisingEdge(dut.clk)
        assert int(dut.start.value) == 0
    dut._log.info("PASS invalid_mode_ff")


@cocotb.test()
async def test_garbage_prefix_resync(dut):
    """Multiple garbage bytes then valid frame."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    junk = bytes([0xFF, 0xFF, 0xAA, 0x5A, 0xA4, 0xA6])  # neither SOF
    frame = build_frame(mode=3, ad=12, data=16)
    cocotb.start_soon(send_frame(dut, junk + frame))
    assert await wait_for_pulse(dut, dut.frame_valid, timeout_cycles=1000)
    assert int(dut.mode_sel.value) == 3
    assert int(dut.ad_total_bytes.value) == 12
    assert int(dut.data_total_bytes.value) == 16
    dut._log.info("PASS garbage_prefix_resync")


@cocotb.test()
async def test_two_consecutive_frames(dut):
    """Parser must idle cleanly and re-arm for the next frame."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    f1 = build_frame(mode=1, data=16)
    f2 = build_frame(mode=5, flags=0, ad=4, data=8)
    cocotb.start_soon(send_frame(dut, f1 + f2))
    # Wait for first frame's start
    assert await wait_for_pulse(dut, dut.frame_valid)
    assert int(dut.mode_sel.value) == 1
    assert int(dut.data_total_bytes.value) == 16
    assert await wait_for_pulse(dut, dut.start)
    # Wait for second frame's start
    assert await wait_for_pulse(dut, dut.frame_valid, timeout_cycles=500)
    assert int(dut.mode_sel.value) == 5
    assert int(dut.ad_total_bytes.value) == 4
    assert int(dut.data_total_bytes.value) == 8
    assert await wait_for_pulse(dut, dut.start)
    dut._log.info("PASS two_consecutive_frames")
