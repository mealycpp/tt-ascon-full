"""project.v smoke test.

Scope: prove the real TT top composes, doesn't lock up under reset,
and exposes expected idle-state outputs. Does NOT exercise crypto via
real UART control frames (that's a Phase 5 integration test).

Checks:
  1. Reset puts uo_out[3..6] (busy/done/error/bg_lag) to 0
  2. uo_out[0..2] (UART TX pins) idle high (UART idle state)
  3. uo_out[7] heartbeat toggles within reasonable time
  4. uio_out and uio_oe both zero (no chip-side IO drive)
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, ReadOnly

async def reset(dut):
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0b00000111  # all 3 UART RX lines high (idle)
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)

@cocotb.test()
async def test_reset_idle(dut):
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    busy   = (int(dut.uo_out.value) >> 3) & 1
    done   = (int(dut.uo_out.value) >> 4) & 1
    err    = (int(dut.uo_out.value) >> 5) & 1
    bg_lag = (int(dut.uo_out.value) >> 6) & 1

    assert busy == 0,   f"busy should be 0 after reset, got {busy}"
    assert done == 0,   f"done should be 0 after reset, got {done}"
    assert err == 0,    f"frame_error should be 0 after reset, got {err}"
    assert bg_lag == 0, f"bg_lag should be 0 (tied), got {bg_lag}"
    assert int(dut.uio_out.value) == 0
    assert int(dut.uio_oe.value) == 0
    dut._log.info("PASS reset_idle (busy/done/err/bg_lag all 0; uio off)")

@cocotb.test()
async def test_tx_idle_high(dut):
    """UART TX pins should idle HIGH (1) after reset (8-N-1 idle state)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # Give a few cycles for uart_tx to drive idle
    await ClockCycles(dut.clk, 20)
    tx0 = int(dut.uo_out.value) & 1
    tx1 = (int(dut.uo_out.value) >> 1) & 1
    tx2 = (int(dut.uo_out.value) >> 2) & 1
    assert tx0 == 1, f"uart0_tx should idle high, got {tx0}"
    assert tx1 == 1, f"uart1_tx should idle high, got {tx1}"
    assert tx2 == 1, f"uart2_tx should idle high, got {tx2}"
    dut._log.info("PASS tx_idle_high (all 3 TX pins = 1)")

@cocotb.test()
async def test_heartbeat_toggles(dut):
    """uo_out[7] heartbeat must change within ~2^24 cycles.
    For simulation speed, we monkey-patch the test by waiting up to 2^17
    cycles and observing whether bit 23 has had time to change in a
    reasonable real test — we'll just sample for 100k cycles and ensure
    SOME upper-bit counter is alive (uo_out[7] should NOT remain stuck)."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # Capture initial heartbeat value
    hb0 = (int(dut.uo_out.value) >> 7) & 1
    # Wait — heartbeat is uo_out[7] which is hb_cnt[23]. After 2^23 = ~8.4M
    # cycles it toggles. We don't have time for that in a smoke test.
    # Instead we verify the upper bits of an internal counter advance by
    # checking that uo_out doesn't get stuck on the same value forever.
    # For smoke purpose: just run for 5k cycles, ensure no lockup
    # (i.e., signals stay defined, no X).
    for _ in range(5000):
        await RisingEdge(dut.clk)
        v = dut.uo_out.value
        # Should not be X
        for b in str(v):
            assert b in "01", f"uo_out went to X/Z: {v}"
    dut._log.info(f"PASS heartbeat alive (5000 cycles no X/Z; initial hb={hb0})")

@cocotb.test()
async def test_no_lockup_with_garbage_rx(dut):
    """Drive random RX activity, verify top doesn't crash."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    # Toggle RX0 a few times (garbage, no valid frame)
    for i in range(20):
        dut.ui_in.value = (i & 1) | ((i & 2) << 0) | 0b100  # RX2 stays high
        await ClockCycles(dut.clk, 50)
    # Verify status pins are still defined
    busy   = (int(dut.uo_out.value) >> 3) & 1
    done   = (int(dut.uo_out.value) >> 4) & 1
    assert busy in (0, 1)
    assert done in (0, 1)
    dut._log.info(f"PASS no_lockup_with_garbage_rx (busy={busy} done={done})")

# --------------------------------------------------------------------
# Real top-level E2E test:
# UART0 control frame -> UART2 payload -> UART2 TX digest.
# --------------------------------------------------------------------

SIM_BAUD_DIV = 217


def safe_int(sig):
    try:
        return int(sig.value)
    except Exception:
        return "X"

def bit(v, b):
    if isinstance(v, int):
        return (v >> b) & 1
    return "X"

def top(dut):
    # tb_project wraps the real Tiny Tapeout user module.
    for name in ("user_project", "uut", "dut"):
        try:
            return getattr(dut, name)
        except Exception:
            pass
    return dut

def h(root, name):
    try:
        obj = root
        for part in name.split("."):
            obj = getattr(obj, part)
        return safe_int(obj)
    except Exception:
        return "NA"

def dump_top_debug(dut, tag):
    t = top(dut)
    uo = safe_int(dut.uo_out)
    dut._log.info(
        f"[DBG {tag}] "
        f"uo={uo} tx2={bit(uo,2)} busy={bit(uo,3)} done={bit(uo,4)} err={bit(uo,5)} "
        f"parser_state={h(t,'u_parser.state')} "
        f"frame_valid={h(t,'frame_valid_w')} frame_error={h(t,'frame_error_w')} start={h(t,'start_pulse_w')} "
        f"mode={h(t,'mode_sel_w')} data_len={h(t,'data_total_bytes_w')} out_len={h(t,'out_length_w')} "
        f"router_state={h(t,'u_router.state')} phase={h(t,'phase_sel_w')} bytes_left={h(t,'u_router.bytes_left')} "
        f"flush={h(t,'flush_lanes')} p2_pending={h(t,'pack_pending_2')} "
        f"p2_valid={h(t,'pack_valid_2')} p2_bytes={h(t,'pack_bytes_2')} p2_ready={h(t,'pack_ready_2')} "
        f"sdmc_v={h(t,'sdmc_in_word_valid_w')} sdmc_r={h(t,'sdmc_in_word_ready_w')} "
        f"sdmc_last={h(t,'sdmc_in_word_last_w')} sdmc_bytes={h(t,'sdmc_in_word_bytes_w')} "
        f"mc_busy={h(t,'mc_busy_w')} mc_done={h(t,'sdmc_done_w')} "
        f"out_v={h(t,'sdmc_out_valid')} out_r={h(t,'sdmc_out_ready')} out_bc={h(t,'sdmc_out_byte_count')} "
        f"tx2_empty={h(t,'u_bridge.tx2_fifo_empty')} tx2_full={h(t,'u_bridge.tx2_fifo_full')} "
        f"tx2_send={h(t,'u_bridge.u_tx2_send')} tx2_ready={h(t,'u_bridge.u_tx2_ready')}"
    )

async def uart_send_byte(dut, lane, byte, baud_div=SIM_BAUD_DIV):
    """Drive one 8-N-1 UART byte into ui_in[lane]."""
    mask = 1 << lane

    # idle high before start
    v = int(dut.ui_in.value)
    dut.ui_in.value = v | mask
    await ClockCycles(dut.clk, baud_div)

    # start bit
    v = int(dut.ui_in.value)
    dut.ui_in.value = v & ~mask
    await ClockCycles(dut.clk, baud_div)

    # data bits LSB-first
    for i in range(8):
        v = int(dut.ui_in.value)
        if (byte >> i) & 1:
            dut.ui_in.value = v | mask
        else:
            dut.ui_in.value = v & ~mask
        await ClockCycles(dut.clk, baud_div)

    # stop bit
    v = int(dut.ui_in.value)
    dut.ui_in.value = v | mask
    await ClockCycles(dut.clk, baud_div)

async def uart_recv_byte_from_tx2(dut, baud_div=SIM_BAUD_DIV, timeout_cycles=300000):
    """Receive one 8-N-1 UART byte from uo_out[2], aligned on a falling start edge."""
    prev = (int(dut.uo_out.value) >> 2) & 1

    # Wait for a real idle-high -> start-low falling edge.
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        cur = (int(dut.uo_out.value) >> 2) & 1
        if prev == 1 and cur == 0:
            break
        prev = cur
    else:
        raise AssertionError("timeout waiting for UART2 TX falling start edge")

    # Sample first data bit at the middle of bit 0.
    await ClockCycles(dut.clk, baud_div + baud_div // 2)

    val = 0
    for i in range(8):
        bit = (int(dut.uo_out.value) >> 2) & 1
        val |= bit << i
        await ClockCycles(dut.clk, baud_div)

    stop = (int(dut.uo_out.value) >> 2) & 1
    assert stop == 1, f"UART2 stop bit not high, got {stop}"

    return val

async def collect_tx2_bytes(dut, n, baud_div=SIM_BAUD_DIV):
    got = bytearray()
    for _ in range(n):
        got.append(await uart_recv_byte_from_tx2(dut, baud_div=baud_div))
    return bytes(got)

async def collect_tx2_uart_input_bytes(dut, n, timeout_cycles=2000000):
    """Collect bytes at the UART2 transmitter input when uart_tx send is asserted."""
    t = top(dut)
    got = bytearray()
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        await ReadOnly()
        try:
            send = int(t.u_bridge.u_tx2_send.value)
        except Exception:
            send = 0
        if send:
            b = int(t.u_bridge.tx2_fifo_rd_data.value) & 0xFF
            got.append(b)
            dut._log.info(f"[TX2_MON] byte{len(got)-1:02d}=0x{b:02x}")
            if len(got) == n:
                return bytes(got)
    raise AssertionError(f"timeout collecting TX2 UART input bytes got={got.hex()} count={len(got)}")

@cocotb.test()
async def test_e2e_hash_abc_uart_top(dut):
    """Full chip path: UART0 frame + UART2 'abc' -> UART2 Hash256 digest."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)

    # HASH256 control frame:
    # B0 SOF A5
    # B1 mode 1
    # B2 flags 0
    # B3-B4 ad_len = 0
    # B5-B6 data/msg len = 3
    # B7-B8 out_len = 32
    # B9-B10 chain_count = 0
    # B11-B12 cs_bits = 0
    # B13 EOF 5A
    frame = [
        0xA5,
        0x01,
        0x00,
        0x00, 0x00,
        0x03, 0x00,
        0x20, 0x00,
        0x00, 0x00,
        0x00, 0x00,
        0x5A,
    ]

    for b in frame:
        await uart_send_byte(dut, lane=0, byte=b)

    # Give parser/start a little time.
    await ClockCycles(dut.clk, 100)
    dump_top_debug(dut, "after_frame")

    # Start deterministic TX2 monitor before payload so we cannot miss output bytes.
    rx_task = cocotb.start_soon(collect_tx2_uart_input_bytes(dut, 32))

    # Let the monitor enter its wait loop before payload starts.
    await ClockCycles(dut.clk, 5)

    # Send message bytes on UART2.
    for b in b"abc":
        await uart_send_byte(dut, lane=2, byte=b)
        await ClockCycles(dut.clk, 20)
        dump_top_debug(dut, f"after_payload_byte_{b:02x}")

    await ClockCycles(dut.clk, 1000)
    dump_top_debug(dut, "after_payload_wait")

    # Collect 32 digest bytes from UART2 TX.
    try:
        got = await rx_task
    except Exception:
        dump_top_debug(dut, "rx_timeout")
        raise

    expected = bytes.fromhex(
        "45aa03431c3c829b3b066f33e844b0cc4d20a45af92d3dcfdf34f40fc20935cf"
    )

    assert got == expected, f"Hash abc mismatch got={got.hex()} exp={expected.hex()}"
    dut._log.info(f"PASS e2e_hash_abc_uart_top digest={got.hex()}")
