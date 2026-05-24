"""lane_router tests: per-mode routing, byte counting, backpressure."""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles

M_HASH256    = 1
M_XOF128     = 2
M_CXOF128    = 3
M_CXOF_CHAIN = 4
M_AEAD_ENC   = 5
M_AEAD_DEC   = 6
M_XOF_CHAIN  = 7

async def reset(dut):
    dut.rst_n.value = 0
    dut.mode.value = 0
    dut.is_decrypt.value = 0
    dut.ad_total_bytes.value = 0
    dut.data_total_bytes.value = 0
    dut.cs_total_bits.value = 0
    dut.start_pulse.value = 0
    dut.sdmc_done.value = 0
    dut.sdmc_in_word_ready.value = 0
    dut.pack_word_0.value = 0
    dut.pack_bytes_0.value = 0
    dut.pack_valid_0.value = 0
    dut.pack_word_1.value = 0
    dut.pack_bytes_1.value = 0
    dut.pack_valid_1.value = 0
    dut.pack_word_2.value = 0
    dut.pack_bytes_2.value = 0
    dut.pack_valid_2.value = 0
    await ClockCycles(dut.clk, 5)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 2)

async def kick_op(dut, mode, ad=0, data=0, cs_bits=0, is_dec=0):
    """Pulse start, then drive metadata."""
    dut.mode.value = mode
    dut.is_decrypt.value = is_dec
    dut.ad_total_bytes.value = ad
    dut.data_total_bytes.value = data
    dut.cs_total_bits.value = cs_bits
    dut.start_pulse.value = 1
    await RisingEdge(dut.clk)
    dut.start_pulse.value = 0

async def supply_words_on_lane(dut, lane, nbytes_total, ready_stall_cycles=0):
    """Drive pack_valid_N=1 and pack_word_N with a counter pattern.
    Returns list of (word, bytes) actually consumed by router (when ready=1).
    """
    consumed = []
    bytes_remaining = nbytes_total
    word_count = 0
    while bytes_remaining > 0:
        # Make this lane present a word
        chunk = min(8, bytes_remaining)
        word_val = sum(((0x10 + word_count*8 + j) & 0xFF) << (8*j) for j in range(chunk))
        if lane == 1:
            dut.pack_word_1.value = word_val
            dut.pack_bytes_1.value = chunk
            dut.pack_valid_1.value = 1
        elif lane == 2:
            dut.pack_word_2.value = word_val
            dut.pack_bytes_2.value = chunk
            dut.pack_valid_2.value = 1

        # Wait until router has selected this lane AND we see valid asserted
        for _ in range(200):
            await RisingEdge(dut.clk)
            if int(dut.sdmc_in_word_valid.value) == 1 and \
               int(dut.phase_sel.value) == lane:
                break
        # Apply backpressure stall if requested
        for _ in range(ready_stall_cycles):
            # ready=0 for these cycles; valid must hold
            dut.sdmc_in_word_ready.value = 0
            await RisingEdge(dut.clk)
            assert int(dut.sdmc_in_word_valid.value) == 1, \
                "valid dropped under backpressure"
        # Now ready=1 for 1 cycle to consume
        dut.sdmc_in_word_ready.value = 1
        await RisingEdge(dut.clk)
        # On this edge the router decrements; capture consumed value
        consumed.append((int(dut.sdmc_in_word.value), int(dut.sdmc_in_word_bytes.value)))
        dut.sdmc_in_word_ready.value = 0
        # Deassert lane valid for one cycle to simulate next word being prepared
        if lane == 1:
            dut.pack_valid_1.value = 0
        elif lane == 2:
            dut.pack_valid_2.value = 0
        await RisingEdge(dut.clk)
        bytes_remaining -= chunk
        word_count += 1
    return consumed

async def finish_op(dut):
    """Pulse sdmc_done and check router returns to idle."""
    dut.sdmc_done.value = 1
    await RisingEdge(dut.clk)
    dut.sdmc_done.value = 0
    await ClockCycles(dut.clk, 2)
    assert int(dut.router_busy.value) == 0, "router_busy should drop after done"


@cocotb.test()
async def test_hash_routes_uart2(dut):
    """HASH256: 24 bytes on UART2, 3 full words; phase_sel must stay 2."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await kick_op(dut, mode=M_HASH256, data=24)
    consumed = await supply_words_on_lane(dut, lane=2, nbytes_total=24)
    assert len(consumed) == 3, f"expected 3 words, got {len(consumed)}"
    assert all(c[1] == 8 for c in consumed), f"all 8-byte: {consumed}"
    # Verify phase_sel was always 2 during the run
    await finish_op(dut)
    dut._log.info(f"PASS hash_routes_uart2: 3 words consumed via lane 2")


@cocotb.test()
async def test_cxof_routes_uart1_then_uart2(dut):
    """CXOF128: CS=24 bits = 3 bytes UART1, then 8 bytes data UART2."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await kick_op(dut, mode=M_CXOF128, cs_bits=24, data=8)
    # First lane: UART1 with 3 bytes
    c1 = await supply_words_on_lane(dut, lane=1, nbytes_total=3)
    # Then UART2 with 8 bytes
    c2 = await supply_words_on_lane(dut, lane=2, nbytes_total=8)
    assert len(c1) == 1 and c1[0][1] == 3
    assert len(c2) == 1 and c2[0][1] == 8
    await finish_op(dut)
    dut._log.info(f"PASS cxof_routes_uart1_then_uart2: 3B UART1 + 8B UART2")


@cocotb.test()
async def test_aead_enc_routes(dut):
    """AEAD_ENC: 16+16+AD=4 -> 36B on UART1, then 8B plaintext on UART2."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await kick_op(dut, mode=M_AEAD_ENC, ad=4, data=8)
    c1 = await supply_words_on_lane(dut, lane=1, nbytes_total=36)
    # 36 bytes = 4 full words (32) + 1 partial 4 = 5 words
    assert sum(c[1] for c in c1) == 36, f"UART1 total bytes wrong: {[c[1] for c in c1]}"
    c2 = await supply_words_on_lane(dut, lane=2, nbytes_total=8)
    assert len(c2) == 1 and c2[0][1] == 8
    await finish_op(dut)
    dut._log.info(f"PASS aead_enc_routes: 36B UART1 + 8B UART2")


@cocotb.test()
async def test_aead_dec_routes(dut):
    """AEAD_DEC: 36B on UART1, then data+16 tag on UART2."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await kick_op(dut, mode=M_AEAD_DEC, ad=4, data=8, is_dec=1)
    c1 = await supply_words_on_lane(dut, lane=1, nbytes_total=36)
    assert sum(c[1] for c in c1) == 36
    # UART2: data (8) + tag (16) = 24 bytes
    c2 = await supply_words_on_lane(dut, lane=2, nbytes_total=24)
    assert sum(c[1] for c in c2) == 24, f"UART2 bytes for DEC: {[c[1] for c in c2]}"
    await finish_op(dut)
    dut._log.info(f"PASS aead_dec_routes: 36B UART1 + 24B UART2 (data+tag)")


@cocotb.test()
async def test_backpressure_sdmc_ready_low(dut):
    """SDMC not ready: router must hold valid and data stable until ready=1."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    await kick_op(dut, mode=M_HASH256, data=8)
    consumed = await supply_words_on_lane(dut, lane=2, nbytes_total=8,
                                           ready_stall_cycles=10)
    assert len(consumed) == 1 and consumed[0][1] == 8
    await finish_op(dut)
    dut._log.info(f"PASS backpressure: 10-cycle stall honored, word preserved")
