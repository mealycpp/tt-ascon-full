"""UART bridge integration tests.

Drives actual UART serial data into rx pins at baud_div=16 (16 cycles/bit
with 16x oversampling = bit_div=1 internally, fastest legal config).
Verifies word stream emerges at sdmc_in_word.

Then drives sdmc_out_block words and decodes serial out from tx pins.
"""
import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, ClockCycles, Timer

BAUD_DIV = 16  # 16 cycles per bit (minimum for 16x oversampling)

async def reset(dut):
    dut.rst_n.value = 0
    dut.baud_div.value = BAUD_DIV
    dut.uart0_rx.value = 1
    dut.uart1_rx.value = 1
    dut.uart2_rx.value = 1
    dut.phase_sel.value = 0
    dut.flush.value = 0
    dut.sdmc_in_word_ready.value = 0
    dut.tx_sel.value = 0
    dut.sdmc_out_block.value = 0
    dut.sdmc_out_byte_count.value = 0
    dut.sdmc_out_valid.value = 0
    await ClockCycles(dut.clk, 8)
    dut.rst_n.value = 1
    await ClockCycles(dut.clk, 4)

async def uart_send_byte(dut, channel, byte):
    """Send 1 byte over uartN_rx pin. 8-N-1: start(0) + 8 data LSB-first + stop(1)."""
    # 10 bits total: 0, d0, d1, d2, d3, d4, d5, d6, d7, 1
    bits = [0] + [(byte >> i) & 1 for i in range(8)] + [1]
    for b in bits:
        if channel == 0:
            dut.uart0_rx.value = b
        elif channel == 1:
            dut.uart1_rx.value = b
        elif channel == 2:
            dut.uart2_rx.value = b
        await ClockCycles(dut.clk, BAUD_DIV)

async def uart_send_bytes(dut, channel, data):
    for b in data:
        await uart_send_byte(dut, channel, b)
    # Ensure line returns to idle (high) afterward
    if channel == 0: dut.uart0_rx.value = 1
    elif channel == 1: dut.uart1_rx.value = 1
    elif channel == 2: dut.uart2_rx.value = 1

async def uart_recv_byte(dut, channel, timeout_cycles=2000):
    """Decode 1 byte from uartN_tx pin. Wait for start bit, sample mid-bit."""
    # Wait for start bit (line goes low)
    for _ in range(timeout_cycles):
        await RisingEdge(dut.clk)
        if channel == 0: bit = int(dut.uart0_tx.value)
        elif channel == 1: bit = int(dut.uart1_tx.value)
        elif channel == 2: bit = int(dut.uart2_tx.value)
        if bit == 0:
            break
    else:
        raise RuntimeError("UART RX timeout - no start bit")
    # Wait half a bit to sample mid-bit
    await ClockCycles(dut.clk, BAUD_DIV // 2)
    # Sample 8 data bits, LSB first
    byte_val = 0
    for i in range(8):
        await ClockCycles(dut.clk, BAUD_DIV)
        if channel == 0: bit = int(dut.uart0_tx.value)
        elif channel == 1: bit = int(dut.uart1_tx.value)
        elif channel == 2: bit = int(dut.uart2_tx.value)
        byte_val |= (bit << i)
    # Skip stop bit
    await ClockCycles(dut.clk, BAUD_DIV)
    return byte_val


@cocotb.test()
async def test_rx_uart0_to_word(dut):
    """Send 8 bytes via UART0 RX, expect 1 word on sdmc_in_word."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.phase_sel.value = 0
    dut.sdmc_in_word_ready.value = 1

    bytes_in = [0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]
    # Send bytes in background
    cocotb.start_soon(uart_send_bytes(dut, 0, bytes_in))

    # Wait for word valid
    for _ in range(8000):
        await RisingEdge(dut.clk)
        if int(dut.sdmc_in_word_valid.value) == 1:
            break
    else:
        raise RuntimeError("No word emitted within timeout")
    word = int(dut.sdmc_in_word.value)
    nbytes = int(dut.sdmc_in_word_bytes.value)
    expected = sum(b << (8*i) for i, b in enumerate(bytes_in))
    assert word == expected, f"word=0x{word:016x} expected=0x{expected:016x}"
    assert nbytes == 8
    dut._log.info(f"PASS rx_uart0_to_word: 0x{word:016x}")


@cocotb.test()
async def test_rx_each_channel(dut):
    """Verify each RX channel routes to sdmc independently."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for ch in range(3):
        await reset(dut)
        dut.phase_sel.value = ch
        dut.sdmc_in_word_ready.value = 1
        bytes_in = [0x20 + i for i in range(8)]
        cocotb.start_soon(uart_send_bytes(dut, ch, bytes_in))
        for _ in range(8000):
            await RisingEdge(dut.clk)
            if int(dut.sdmc_in_word_valid.value) == 1:
                break
        else:
            raise RuntimeError(f"channel {ch}: no word emitted")
        word = int(dut.sdmc_in_word.value)
        expected = sum(b << (8*i) for i, b in enumerate(bytes_in))
        assert word == expected, f"ch{ch}: word=0x{word:016x} expected=0x{expected:016x}"
        dut._log.info(f"PASS rx_each_channel ch{ch}")


@cocotb.test()
async def test_tx_word_to_uart2(dut):
    """Push 8 bytes via sdmc_out_block, decode from uart2_tx."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.tx_sel.value = 2

    word = 0xfedcba9876543210
    expected_bytes = [0x10, 0x32, 0x54, 0x76, 0x98, 0xba, 0xdc, 0xfe]

    # Push the word into the bridge
    while True:
        await RisingEdge(dut.clk)
        if int(dut.sdmc_out_ready.value) == 1:
            break
    dut.sdmc_out_block.value = word
    dut.sdmc_out_byte_count.value = 8
    dut.sdmc_out_valid.value = 1
    await RisingEdge(dut.clk)
    dut.sdmc_out_valid.value = 0

    # Decode 8 bytes from uart2_tx
    got = []
    for _ in range(8):
        b = await uart_recv_byte(dut, 2)
        got.append(b)
    assert got == expected_bytes, f"got={got} expected={expected_bytes}"
    dut._log.info(f"PASS tx_word_to_uart2: bytes={[hex(b) for b in got]}")


@cocotb.test()
async def test_tx_each_channel(dut):
    """Verify each TX channel works independently."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    for ch in range(3):
        await reset(dut)
        dut.tx_sel.value = ch
        # Send 4 bytes via a partial-word
        word_bytes = [0x40 + i for i in range(4)]
        word = sum(b << (8*i) for i, b in enumerate(word_bytes))
        while True:
            await RisingEdge(dut.clk)
            if int(dut.sdmc_out_ready.value) == 1:
                break
        dut.sdmc_out_block.value = word
        dut.sdmc_out_byte_count.value = 4
        dut.sdmc_out_valid.value = 1
        await RisingEdge(dut.clk)
        dut.sdmc_out_valid.value = 0
        got = []
        for _ in range(4):
            b = await uart_recv_byte(dut, ch)
            got.append(b)
        assert got == word_bytes, f"ch{ch}: got={got} expected={word_bytes}"
        dut._log.info(f"PASS tx_each_channel ch{ch}")


@cocotb.test()
async def test_rx_16_bytes(dut):
    """Send 16 bytes via UART0 RX, expect 2 consecutive words."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.phase_sel.value = 0
    dut.sdmc_in_word_ready.value = 1

    bytes_in = [0x10 + i for i in range(16)]
    cocotb.start_soon(uart_send_bytes(dut, 0, bytes_in))

    words = []
    for _ in range(20000):
        await RisingEdge(dut.clk)
        if int(dut.sdmc_in_word_valid.value) == 1:
            words.append(int(dut.sdmc_in_word.value))
            if len(words) == 2:
                break
    assert len(words) == 2, f"expected 2 words, got {len(words)}"
    exp0 = sum(bytes_in[i] << (8*i) for i in range(8))
    exp1 = sum(bytes_in[i+8] << (8*i) for i in range(8))
    assert words[0] == exp0 and words[1] == exp1, f"w0=0x{words[0]:016x} w1=0x{words[1]:016x}"
    dut._log.info(f"PASS rx_16_bytes: 2 words 0x{words[0]:016x} 0x{words[1]:016x}")


@cocotb.test()
async def test_rx_partial_with_flush(dut):
    """Send 3 bytes, then flush, expect 1 partial word with byte_count=3."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.phase_sel.value = 0
    dut.sdmc_in_word_ready.value = 1

    bytes_in = [0xa1, 0xb2, 0xc3]
    # Send bytes (3 bytes * ~160 cycles UART time each) and WAIT for completion
    await uart_send_bytes(dut, 0, bytes_in)
    # Then wait a generous additional period so RX finishes the final stop
    # bit and the FIFO sees all 3 bytes
    await ClockCycles(dut.clk, 200)
    # Now wait until packer has consumed all bytes (FIFO empty)
    for _ in range(2000):
        await RisingEdge(dut.clk)
        if (int(dut.rx_fifo_empty.value) & 0x1) == 1:
            break
    else:
        raise RuntimeError("FIFO never drained")
    # Settle
    await ClockCycles(dut.clk, 4)
    # Now assert flush on lane 0; hold until flush_ready AND valid observed
    dut.flush.value = 0b001
    for _ in range(200):
        await RisingEdge(dut.clk)
        if (int(dut.flush_ready.value) & 0x1) == 1 and int(dut.sdmc_in_word_valid.value) == 1:
            break
    else:
        raise RuntimeError("flush_ready + valid never observed")
    word = int(dut.sdmc_in_word.value)
    nbytes = int(dut.sdmc_in_word_bytes.value)
    dut.flush.value = 0
    expected = sum(bytes_in[i] << (8*i) for i in range(3))
    assert nbytes == 3, f"expected nbytes=3, got {nbytes}"
    assert (word & 0xFFFFFF) == expected, f"word LSB 24 bits=0x{word & 0xFFFFFF:06x} expected=0x{expected:06x}"
    dut._log.info(f"PASS rx_partial_with_flush: 3 bytes, word=0x{word:016x}, bytes={nbytes}")


@cocotb.test()
async def test_word_output_backpressure(dut):
    """Send 8 bytes via UART0; hold sdmc_in_word_ready=0; verify word valid
    holds, data stable; release and verify correct value."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.phase_sel.value = 0
    dut.sdmc_in_word_ready.value = 0  # backpressure active

    bytes_in = [0x70 + i for i in range(8)]
    cocotb.start_soon(uart_send_bytes(dut, 0, bytes_in))

    # Wait for word_valid
    for _ in range(8000):
        await RisingEdge(dut.clk)
        if int(dut.sdmc_in_word_valid.value) == 1:
            break
    else:
        raise RuntimeError("word never valid")
    held = int(dut.sdmc_in_word.value)
    held_bytes = int(dut.sdmc_in_word_bytes.value)
    # Hold backpressure for 50 cycles
    for _ in range(50):
        await RisingEdge(dut.clk)
        assert int(dut.sdmc_in_word_valid.value) == 1, "valid dropped under backpressure"
        assert int(dut.sdmc_in_word.value) == held, "data changed under backpressure"
        assert int(dut.sdmc_in_word_bytes.value) == held_bytes, "bytes changed under backpressure"
    # Release
    dut.sdmc_in_word_ready.value = 1
    await RisingEdge(dut.clk)
    dut.sdmc_in_word_ready.value = 0
    await RisingEdge(dut.clk)
    assert int(dut.sdmc_in_word_valid.value) == 0, "valid should drop after consume"
    expected = sum(bytes_in[i] << (8*i) for i in range(8))
    assert held == expected, f"held=0x{held:016x} expected=0x{expected:016x}"
    assert held_bytes == 8
    dut._log.info(f"PASS word_output_backpressure: held 50 cycles stable, value 0x{held:016x}")


@cocotb.test()
async def test_tx_byte_backpressure(dut):
    """Push 2 words into bridge; UART serialization is the natural
    backpressure source. Verify all 16 bytes emerge in correct order."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())
    await reset(dut)
    dut.tx_sel.value = 2

    bytes_expected = [0x10 + i for i in range(16)]
    w0 = sum(bytes_expected[i] << (8*i) for i in range(8))
    w1 = sum(bytes_expected[i+8] << (8*i) for i in range(8))

    # Push word 0
    while True:
        await RisingEdge(dut.clk)
        if int(dut.sdmc_out_ready.value) == 1:
            break
    dut.sdmc_out_block.value = w0
    dut.sdmc_out_byte_count.value = 8
    dut.sdmc_out_valid.value = 1
    await RisingEdge(dut.clk)
    dut.sdmc_out_valid.value = 0

    # Push word 1 as soon as bridge ready
    while True:
        await RisingEdge(dut.clk)
        if int(dut.sdmc_out_ready.value) == 1:
            break
    dut.sdmc_out_block.value = w1
    dut.sdmc_out_byte_count.value = 8
    dut.sdmc_out_valid.value = 1
    await RisingEdge(dut.clk)
    dut.sdmc_out_valid.value = 0

    # Decode 16 bytes from uart2_tx
    got = []
    for _ in range(16):
        b = await uart_recv_byte(dut, 2)
        got.append(b)
    assert got == bytes_expected, f"tx backpressure: got={got} expected={bytes_expected}"
    dut._log.info(f"PASS tx_byte_backpressure: 16 bytes in order via slow UART")
