# Verification and Physical-Design Notes

## Functional test vectors

The Cocotb suite exercises positive and negative INT4 values, boundary values, and zero weights. Expected outputs follow the current datapath equation:

`y[r] = x[r] * (w[0] + w[1] + w[2] + w[3])`.

| Case | Features | Weights | Expected outputs |
|---:|---|---|---|
| 1 | `[1, 2, 3, 4]` | `[1, 2, -1, 1]` | `[3, 6, 9, 12]` |
| 2 | `[2, -3, 7, -8]` | `[4, -2, 1, -1]` | `[4, -6, 14, -16]` |
| 3 | `[7, -8, 0, -1]` | `[7, 7, 7, 7]` | `[196, -224, 0, -28]` |
| 4 | `[-8, 7, -5, 3]` | `[-8, -8, -8, -8]` | `[256, -224, 160, -96]` |
| 5 | `[-8, -1, 1, 7]` | `[-8, 7, -8, 7]` | `[16, 2, -2, -14]` |
| 6 | `[-8, -1, 0, 7]` | `[0, 0, 0, 0]` | `[0, 0, 0, 0]` |
| 7 | `[-7, 5, -2, 6]` | `[-3, 2, 4, -1]` | `[-14, 10, -4, 12]` |

For another commit, use the [GitHub Actions test workflow](https://github.com/VarunKB06/cnn-tiny-tapeout/actions/workflows/test.yaml) and record its run number and commit SHA here after the run completes.

## Cocotb regression results

The GitHub Actions **`test`** workflow completed successfully on `main` in run **#41**, at commit `a84317d25f6684a2aea3dc41ae07d7ee14b4eb93`. The [test workflow page](https://github.com/VarunKB06/cnn-tiny-tapeout/actions/workflows/test.yaml) provides access to the run history and logs.

Environment reported by the run:

- Icarus Verilog 12.0
- Cocotb 2.1.0
- Python 3.11

| Test | Result | Details |
|---|---|---|
| `test_int4_systolic_accelerator_4x4` | PASS | All 7 directed arithmetic vectors passed; expected and received outputs matched. Simulation time: 4191 ns. |
| `test_ena_low_during_completion` | PASS | Completion was retained while `ena` was low; expected outputs `[256, -224, 0, 32]` matched the received outputs. Simulation time: 701 ns. |
| **Regression total** | **2 passed, 0 failed, 0 skipped** | Total simulation time: 4892 ns. |

### Enable / completion handshake

The wrapper latches the core completion event independently of `ena`, because the core continues computing even when the wrapper is disabled. `uio_out[3]` is a result-valid level that remains asserted until all eight result bytes have been read. The `test_ena_low_during_completion` regression drops `ena` after completion becomes visible, holds it low for several cycles, re-enables the wrapper, and checks all four signed results. This test passed in the run listed above.

## Recorded physical-design results

Source: the successful LibreLane GDS artifact's `runs/wokwi/final/metrics.csv`.

| Metric | Value |
|---|---:|
| Standard-cell area | 13,098.8 µm² |
| Core area | 16,493.3 µm² |
| Core utilization | 79.42% |
| Setup worst slack | +6.383 ns |
| Hold worst slack | +0.110 ns |
| Setup violations | 0 |
| Hold violations | 0 |
| Maximum-slew violations under the configured 1.5 ns limit | 0 |
| Maximum-capacitance violations | 0 |
| Maximum-fanout violations | 1 |
| Magic DRC errors | 0 |
| LVS device differences | 0 |
| LVS net differences | 0 |
| Antenna violations | 0 |

## Known issue

The metrics report one maximum-fanout violation on the root clock buffer (`clkbuf_0_clk/X`), which drives 16 loads against a configured limit of 10. The design's maximum-transition setting is 1.5 ns; zero reported slew violations means the checks pass under that threshold, not that the transition was physically improved by the setting. Obtain guidance for the intended shuttle before deciding if more clock-tree changes are required.

## Reproducibility

Record the commit SHA, GitHub Actions run URL, `src/config.json`, `info.yaml`, and the downloaded GDS logs when capturing new results. Metrics can change when RTL, tool versions, PDK revisions, or configuration changes.
