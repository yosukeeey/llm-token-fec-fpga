# Basys 3 Bring-up

Basys 3実機検証の順序、合格条件、保存物を定義する。未実装の手順を推測で補完しない。

## Current status

| Item | Status | Location |
| --- | --- | --- |
| UART RTL simulation | Ready | `scripts/test_uart_rtl.ps1` |
| Fixed test vectors | Ready | `datasets/test_vectors/protocol_v0/` |
| JSONL offline evaluator | Ready | `scripts/evaluate_reference_results.py` |
| Vivado and serial-port detection | Ready | `scripts/check_dev_env.ps1` |
| Basys 3 board top and XDC | Missing | Future Issue |
| Reproducible Vivado build and programming | Missing | Future Issue |
| C++20 Win32 UART runner | Ready | `sw/cpp/apps/uart_vector_runner.cpp` |
| Hardware capture to Result JSONL | Ready | `sw/cpp/src/uart_artifacts.cpp` |

`scripts/evaluate_streaming_results.py` validates self-checking RTL testbench records only. It does not evaluate hardware captures.

## Fixed interface

- Board: Digilent Basys 3
- FPGA clock: 100 MHz
- UART: 115200 baud, 8-N-1, LSB-first, idle High
- Transport: Frame V0
- Host communication: C++20 and Win32 API
- Python: fixed-vector generation and offline evaluation only

Protocol details are defined in [`docs/TEST_PROTOCOL_V0.md`](../TEST_PROTOCOL_V0.md).

## Bring-up order

Do not combine stages during initial bring-up. Advance only after the current stage passes.

| Stage | Test design | Isolates | Pass condition | Evidence |
| --- | --- | --- | --- | --- |
| 0 | Preflight | Host tools and existing regressions | Environment checks and all software/RTL regressions pass | Tool versions, Git commit, and command output |
| 1 | LED blink | Configuration, 100 MHz clock pin, LED pin, and counter | One onboard LED blinks at the designed human-visible rate for at least 10 cycles after programming | Bitstream SHA-256, LED identifier, and observed result |
| 2 | UART TX beacon | UART TX pin, baud rate, and bit timing | The host repeatedly receives the designed byte pattern without changes | Raw RX capture and decoded bytes |
| 3 | UART byte echo | UART RX pin, sampling, and bidirectional path | `00`, `FF`, `55`, and `AA` are returned byte-exactly in order | Sent and received bytes |
| 4 | Frame PING/PONG | Frame boundary, length, CRC, and response path | The fixed PING Frame produces the expected PONG Frame | Raw capture, Result JSONL, and evaluator output |
| 5 | Token/FEC | Token payload and protection processing | The fixed TOKEN_REQUEST produces the expected TOKEN_RESULT and status | Raw capture, Result JSONL, and evaluator output |

Stage 1 uses only the onboard clock and one onboard LED; UART and protocol logic remain inactive. Record the build command and bitstream SHA-256 before every programming step. Stages 1 through 5 remain blocked until the missing top, XDC, and Vivado build assets in the status table are implemented.

## Preflight

```powershell
.\scripts\check_dev_env.ps1 -RequireVivado -RequireSerialPort
.\scripts\test_rtl.ps1
.\scripts\test_streaming_rtl.ps1
.\scripts\test_frame_rtl.ps1
.\scripts\test_uart_rtl.ps1
```

## Host runner

The runner validates the complete vector file before opening the COM port. It uses the
fixed 115200 baud, 8-N-1 settings and one absolute timeout per request/response case.

```powershell
.\build\dev\cpp\Release\uart_vector_runner.exe `
  --port COM3 `
  --vectors datasets\test_vectors\protocol_v0\protocol_pipeline.jsonl `
  --capture datasets\test_results\bringup\basys3\<run-id>\uart-capture.bin `
  --results datasets\test_results\bringup\basys3\<run-id>\results.jsonl `
  --timeout-ms 2000
```

Success requires byte-identical PONG and TOKEN_RESULT Frames in vector order. The
runner exits nonzero on timeout, serial failure, malformed response, or byte mismatch.
The capture contains every received UART byte without transformation. Completed Frames
are written as `CaseResult` records, with status flags decoded from the actual payload.
Existing artifact paths are rejected.

Offline evaluation remains a separate Python step.

```powershell
uv run python -m scripts.evaluate_reference_results `
  --vectors datasets\test_vectors\protocol_v0\protocol_pipeline.jsonl `
  --results datasets\test_results\bringup\basys3\<run-id>\results.jsonl
```

## Acceptance

- All preflight commands exit with zero.
- Each earlier bring-up stage passes before the next stage starts.
- The LED-only design blinks reliably before any UART design is programmed.
- The programmed bitstream matches the recorded SHA-256.
- Every transmitted Frame has one expected byte-exact response.
- No unexpected response, timeout, UART framing error, or FIFO overflow occurs.
- Result JSONL passes the fixed-vector evaluator.
- A run is not accepted without raw capture and the completed run record.

## Records

Copy [`RUN_RECORD_TEMPLATE.md`](RUN_RECORD_TEMPLATE.md) for each run. Store machine-readable artifacts under `datasets/test_results/bringup/` according to its README.
