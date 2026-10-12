import cocotb
from cocotb.clock import Clock
from cocotb.triggers import RisingEdge, Timer

# Tiny Tapeout command encoding (uio_in[1:0])
CMD_IDLE = 0b00
CMD_LOAD = 0b01
CMD_START = 0b10
CMD_READ = 0b11


async def tick(dut):
    """Wait for one rising edge and allow nonblocking assignments to settle."""
    await RisingEdge(dut.clk)
    await Timer(1, unit="ns")


def encode_int4(value):
    """Return the two's-complement low nibble for a signed INT4 value."""
    assert -8 <= value <= 7, f"{value} is outside the signed INT4 range [-8, 7]"
    return value & 0x0F


def signed16(value):
    """Interpret a 16-bit value as signed two's-complement."""
    value &= 0xFFFF
    return value - 0x10000 if value & 0x8000 else value


async def idle_cycle(dut):
    dut.ui_in.value = 0
    dut.uio_in.value = CMD_IDLE
    await tick(dut)


async def send_command(dut, command, data=0):
    """Issue one command cycle, then one idle cycle."""
    dut.ui_in.value = data & 0xFF
    dut.uio_in.value = command & 0x03
    await tick(dut)
    await idle_cycle(dut)


async def load_inputs(dut, features, weights):
    """Load features 0..3, followed by weights 0..3."""
    assert len(features) == 4
    assert len(weights) == 4

    for value in list(features) + list(weights):
        await send_command(dut, CMD_LOAD, encode_int4(value))


async def wait_for_output(dut, timeout_cycles=60):
    """Wait for output_valid, then let wrapper enter its output state."""
    for _ in range(timeout_cycles):
        await tick(dut)
        status = int(dut.uio_out.value)

        # Wrapper maps output_valid to uio_out[3].
        if status & 0x08:
            # The wrapper observes done and transitions to ST_OUTPUT
            # on the following clock edge.
            await tick(dut)
            return

    raise AssertionError(
        f"Timed out waiting for output_valid after {timeout_cycles} cycles"
    )


async def read_byte(dut):
    """Capture the current byte and advance the wrapper with CMD_READ."""
    value = int(dut.uo_out.value)
    await send_command(dut, CMD_READ)
    return value


async def run_case(dut, test_id, features, weights):
    """Run one 4x4 INT4 case and compare all four 16-bit results."""
    weight_sum = sum(weights)
    expected = [feature * weight_sum for feature in features]

    dut._log.info(
        "Test %d: features=%s, weights=%s, weight_sum=%d",
        test_id, features, weights, weight_sum
    )
    dut._log.info("Expected outputs: %s", expected)

    await load_inputs(dut, features, weights)
    await send_command(dut, CMD_START)
    await wait_for_output(dut)

    # Read order: output_0 low/high, ..., output_3 low/high.
    data = [await read_byte(dut) for _ in range(8)]
    actual = [
        signed16(data[0] | (data[1] << 8)),
        signed16(data[2] | (data[3] << 8)),
        signed16(data[4] | (data[5] << 8)),
        signed16(data[6] | (data[7] << 8)),
    ]

    dut._log.info("Received outputs: %s", actual)
    dut._log.info("Output bytes: %s", " ".join(f"{b:02X}" for b in data))

    assert actual == expected, (
        f"Test {test_id} failed: expected {expected}, got {actual}"
    )
    dut._log.info("Test %d PASSED", test_id)


@cocotb.test()
async def test_int4_systolic_accelerator_4x4(dut):
    """Verify the 4x4 signed INT4 systolic accelerator via TT wrapper."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0
    dut.ena.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = CMD_IDLE

    for _ in range(5):
        await tick(dut)

    dut.rst_n.value = 1
    dut.ena.value = 1
    for _ in range(2):
        await idle_cycle(dut)

    # Each tuple is (features[0:4], weights[0:4]).
    # The RTL computes output_r = feature_r * sum(weights).
    test_vectors = [
        ([1, 2, 3, 4], [1, 2, -1, 1]),       # weight sum = 3
        ([2, -3, 7, -8], [4, -2, 1, -1]),    # mixed signed values
        ([7, -8, 0, -1], [7, 7, 7, 7]),      # maximum positive weights
        ([-8, 7, -5, 3], [-8, -8, -8, -8]),  # includes output +256
        ([-8, -1, 1, 7], [-8, 7, -8, 7]),    # alternating boundaries
        ([-8, -1, 0, 7], [0, 0, 0, 0]),      # zero weights
        ([-7, 5, -2, 6], [-3, 2, 4, -1]),    # mixed-sign arithmetic
    ]

    for test_id, (features, weights) in enumerate(test_vectors, start=1):
        await run_case(dut, test_id, features, weights)

    dut._log.info("ALL TESTS PASSED: %d/%d", len(test_vectors), len(test_vectors))

@cocotb.test()
async def test_ena_low_during_completion(dut):
    """Completion must be retained if ena is low during the done pulse."""
    cocotb.start_soon(Clock(dut.clk, 10, unit="ns").start())

    dut.rst_n.value = 0
    dut.ena.value = 0
    dut.ui_in.value = 0
    dut.uio_in.value = CMD_IDLE
    for _ in range(5):
        await tick(dut)

    dut.rst_n.value = 1
    dut.ena.value = 1
    for _ in range(2):
        await idle_cycle(dut)

    # Include the arithmetic extrema exercised by the original regression:
    # (-8) * (-8 - 8 - 8 - 8) = +256.
    features = [-8, 7, 0, -1]
    weights = [-8, -8, -8, -8]
    expected = [feature * sum(weights) for feature in features]

    await load_inputs(dut, features, weights)
    await send_command(dut, CMD_START)

    # Wait until the controller's one-cycle done pulse becomes visible.
    # Drop ena before the next rising edge, which is the edge on which the
    # wrapper would normally consume done and enter ST_OUTPUT.
    saw_valid = False
    for _ in range(60):
        await tick(dut)
        if int(dut.uio_out.value) & 0x08:
            saw_valid = True
            break

    assert saw_valid, "Timed out waiting for completion before ena test"
    dut.ena.value = 0

    # The core leaves FINISH at the next edge. Completion must be latched
    # even though the wrapper is disabled at that edge.
    await tick(dut)
    assert int(dut.uio_out.value) & 0x08, (
        "result-valid was lost when ena was low during completion"
    )

    # Leave the design disabled for additional cycles. Result-valid must
    # remain asserted and the wrapper must retain the pending result.
    for _ in range(3):
        await tick(dut)
        assert int(dut.uio_out.value) & 0x08, (
            "result-valid did not remain asserted while ena was low"
        )

    # Re-enable the wrapper. It must observe the latched completion and
    # enter ST_OUTPUT rather than waiting forever for the expired done pulse.
    dut.ena.value = 1
    await tick(dut)
    assert int(dut.uio_out.value) & 0x08, (
        "result-valid was not retained after ena was re-enabled"
    )

    data = [await read_byte(dut) for _ in range(8)]
    actual = [
        signed16(data[0] | (data[1] << 8)),
        signed16(data[2] | (data[3] << 8)),
        signed16(data[4] | (data[5] << 8)),
        signed16(data[6] | (data[7] << 8)),
    ]
    assert actual == expected, (
        f"ena-low completion test failed: expected {expected}, got {actual}"
    )
    assert not (int(dut.uio_out.value) & 0x08), (
        "result-valid should deassert after the final result byte is read"
    )
    dut._log.info("ENA-LOW COMPLETION TEST PASSED: expected=%s actual=%s", expected, actual)

