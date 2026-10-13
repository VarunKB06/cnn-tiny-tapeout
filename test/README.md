# Test and verification

This directory contains the Cocotb testbench for `tt_um_cnn_accelerator`, the Tiny Tapeout wrapper for the resource-shared 4×4 signed INT4 MAC accelerator.

The functional regression contains six Cocotb tests:

- `test_int4_systolic_accelerator_4x4`: checks seven directed signed-INT4 input/weight vectors against the reference equation `output[r] = feature[r] * sum(weights)`.
- `test_ena_low_during_completion`: checks completion/result-valid retention when `ena` is low during completion, then verifies the four outputs.
- `test_status_signals`: checks `busy`, result-valid, `uio_oe`, reserved status bits, and the byte-read protocol.
- `test_reset_during_compute_and_recovery`: resets during an active computation and verifies that a fresh transaction succeeds afterward.
- `test_repeated_transactions_without_reset`: runs two complete transactions without an intervening reset.
- `test_deterministic_randomized_vectors`: checks 20 reproducible signed-INT4 vectors using seed `0xC0C07B`.

The testbench exercises the Tiny Tapeout command interface using `uio_in[1:0]`: `00` = IDLE, `01` = LOAD, `10` = START, `11` = READ. Features and weights are loaded as signed INT4 nibbles through `ui_in[3:0]`. Each signed 10-bit result is read through the wrapper's byte-wise output protocol; the Cocotb helper interprets the returned words as signed 16-bit values.

## Prerequisites

- Python 3.11 or a compatible version supported by the pinned test dependencies
- Icarus Verilog (`iverilog` and `vvp`)
- GTKWave (optional, for viewing waveforms)

Install the Python dependencies from the repository root:

```sh
python -m pip install -r test/requirements.txt
```

On Ubuntu/WSL, install Icarus Verilog with:

```sh
sudo apt-get update
sudo apt-get install -y iverilog
```

## Run RTL simulation

From the repository root:

```sh
cd test
make clean
make
python -m cocotb_tools.check_results results.xml
```

Checking `results.xml` is important: the Makefile's simulator process may return success even when Cocotb has recorded a failed test. A successful regression should report all six Cocotb tests passing with zero failures.

The testbench uses a 20 ns clock period to match the project's declared 50 MHz clock configuration. Functional simulation checks behavior; it is not a substitute for static timing analysis or physical-design sign-off.

## View waveforms

The RTL testbench writes `tb.fst` in this directory. From `test/`, run:

```sh
gtkwave tb.fst tb.gtkw
```

The GTKWave save file uses a relative dumpfile path so it can be opened from another checkout or machine. If GTKWave reports that a signal is missing, open `tb.fst` directly and select signals from the current `tb` hierarchy.

## Gate-level simulation

The repository's GDS GitHub Actions workflow runs the configured Tiny Tapeout gate-level test. For a local gate-level run, the SKY130A PDK must be installed and `PDK_ROOT` set, and `test/gate_level_netlist.v` must contain a compatible gate-level netlist for `tt_um_cnn_accelerator`. Then, from `test/`, run:

```sh
make clean
make GATES=yes
python -m cocotb_tools.check_results results.xml
```

Do not copy a netlist from an unrelated project or an older build. If the correct netlist and PDK setup are not available locally, use the gate-level test artifact/results from the repository's GDS workflow instead.
