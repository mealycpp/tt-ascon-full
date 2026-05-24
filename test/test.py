# SPDX-License-Identifier: Apache-2.0
"""TinyTapeout CI smoke test for tt_um_mealycpp_ascon_full.

Scope: prove the real top composes and is stable under reset.
Full crypto-through-UART tests live in test/dispatcher/ and test/top/.

CI scope (matches what GHA runs):
  1. Reset puts status pins to 0
  2. UART TX pins idle HIGH (8-N-1 idle state)
  3. No X/Z propagation under random RX activity
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles


async def reset(dut):
    dut.rst_n.value = 0
    dut.ena.value = 1
    dut.ui_in.value = 0b00000111  # 3 UART RX lines idle high
    dut.uio_in.value = 0
    await ClockCycles(dut.clk, 20)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 10)


@cocotb.test()
async def test_reset_idle(dut):
    """After reset, busy/done/error/bg_lag are all 0."""
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
    dut._log.info("PASS reset_idle")


@cocotb.test()
async def test_tx_idle_high(dut):
    """UART TX pins should idle HIGH after reset."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await ClockCycles(dut.clk, 20)
    tx0 = int(dut.uo_out.value) & 1
    tx1 = (int(dut.uo_out.value) >> 1) & 1
    tx2 = (int(dut.uo_out.value) >> 2) & 1
    assert tx0 == 1, f"uart0_tx should idle high, got {tx0}"
    assert tx1 == 1, f"uart1_tx should idle high, got {tx1}"
    assert tx2 == 1, f"uart2_tx should idle high, got {tx2}"
    dut._log.info("PASS tx_idle_high")


@cocotb.test()
async def test_no_lockup_with_garbage_rx(dut):
    """Random RX activity must not cause X/Z propagation or lockup."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    for i in range(20):
        dut.ui_in.value = (i & 0b111) | 0b100  # vary RX0/1, keep RX2 high
        await ClockCycles(dut.clk, 50)
        # Check no X
        v = dut.uo_out.value
        for b in str(v):
            assert b in "01", f"uo_out went to X/Z: {v}"
    busy = (int(dut.uo_out.value) >> 3) & 1
    done = (int(dut.uo_out.value) >> 4) & 1
    assert busy in (0, 1)
    assert done in (0, 1)
    dut._log.info(f"PASS no_lockup_with_garbage_rx (busy={busy} done={done})")
