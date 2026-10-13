# Verification and Physical-Design Notes

## Functional reference equation

The datapath computes:

`y[r] = x[r] * (w[0] + w[1] + w[2] + w[3])`.

Features and weights are signed INT4 values in the range -8 through +7. The output and accumulator are signed 10-bit values.

## Directed arithmetic vectors

The Cocotb arithmetic regression exercises positive and negative values, boundary values, and zero weights.

| Case | Features | Weights | Expected outputs |
|---:|---|---|---|
| 1 | `[1, 2, 3, 4]` | `[1, 2, -1, 1]` | `[3, 6, 9, 12]` |
| 2 | `[2, -3, 7, -8]` | `[4, -2, 1, -1]` | `[4, -6, 14, -16]` |
| 3 | `[7, -8, 0, -1]` | `[7, 7, 7, 7]` | `[196, -224, 0, -28]` |
| 4 | `[-8, 7, -5, 3]` | `[-8, -8, -8, -8]` | `[256, -224, 160, -96]` |
| 5 | `[-8, -1, 1, 7]` | `[-8, 7, -8, 7]` | `[16, 2, -2, -14]` |
| 6 | `[-8, -1, 0, 7]` | `[0, 0, 0, 0]` | `[0, 0, 0, 0]` |
| 7 | `[-7, 5, -2, 6]` | `[-3, 2, 4, -1]` | `[-14, 10, -4, 12]` |

## Latest Cocotb regression

The latest supplied GitHub Actions screenshot shows the `test` workflow completing successfully on branch `test/status-signal-coverage` (the branch label is truncated in the screenshot) at commit `98a19b3`. The run summary reports **6 tests passed** with a total workflow duration of 27 seconds. No Node.js deprecation warning was shown after updating the test-summary action.

- [GitHub Actions test workflow history](https://github.com/VarunKB06/cnn-tiny-tapeout/actions/workflows/test.yaml)
- [Commit `98a19b3`](https://github.com/VarunKB06/cnn-tiny-tapeout/commit/98a19b3)

The workflow page above is the workflow history, not a run-specific URL. Open the run for commit `98a19b3` to inspect the exact logs. Add the direct run URL here when it is copied from the browser address bar.

| Cocotb test | Result | Coverage |
|---|---|---|
| `test_int4_systolic_accelerator_4x4` | PASS | Seven directed arithmetic vectors; expected outputs match the received outputs. |
| `test_ena_low_during_completion` | PASS | Checks completion retention when `ena` is low during the completion pulse and validates the four outputs. |
| `test_status_signals` | PASS | Checks `busy`, result-valid, output-enable, reserved status bits, and byte-read status behavior. |
| `test_reset_during_compute_and_recovery` | PASS | Asserts reset during computation and checks successful recovery with a new transaction. |
| `test_repeated_transactions_without_reset` | PASS | Checks two complete transactions without an intervening reset. |
| `test_deterministic_randomized_vectors` | PASS | Checks 20 reproducible signed-INT4 vectors using seed `0xC0C07B`. |
| **Total** | **6 passed, 0 failed** | Successful workflow summary. |

## Enable / completion handshake

The wrapper retains the completion event independently of `ena`, because the core controller continues to compute while the wrapper may be disabled. The result-valid status is held until all eight result bytes have been read. The `test_ena_low_during_completion` test disables `ena` around completion, re-enables the wrapper, and checks all four signed results.

## Clock used by the Cocotb tests

Both Cocotb tests use a 20 ns clock period (50 MHz), matching `info.yaml` and the 20 ns period in `src/config.json`. Functional simulation is not a replacement for physical timing analysis.

## Recorded physical-design results

Source previously recorded in the successful LibreLane GDS artifact's `runs/wokwi/final/metrics.csv`. These metrics have not been re-associated with a specific GDS run URL in this document yet.

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

## Known physical-design issue

The recorded metrics report one maximum-fanout violation on the root clock buffer (`clkbuf_0_clk/X`), which drives 16 loads against a configured limit of 10. The maximum-transition setting is 1.5 ns. Zero reported slew violations means the checks pass under that configured threshold; it does not show that the physical transition improved because of the threshold change. Obtain guidance for the intended shuttle before deciding whether further clock-tree changes are required.

## Reproducibility

When publishing new results, record the full commit SHA, direct GitHub Actions run URL, `src/config.json`, `info.yaml`, and the corresponding GDS logs. Physical metrics can change when RTL, tool versions, PDK revisions, or configuration changes.
