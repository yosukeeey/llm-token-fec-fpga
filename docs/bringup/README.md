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
| C++20 Win32 UART runner | Missing | Future Issue |
| Hardware capture to Result JSONL | Missing | Future Issue |

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

1. Record the board, cable, host, tool versions, and Git commit.
2. Run the software and RTL regressions.
3. Confirm Vivado and the serial port.
4. Build the bitstream from the recorded command.
5. Record the bitstream SHA-256 before programming.
6. Program the FPGA.
7. Run PING to PONG byte-exact tests.
8. Run TOKEN_REQUEST to TOKEN_RESULT byte-exact tests.
9. Save raw capture, Result JSONL, evaluator output, and the completed run record.

Steps 4 through 9 remain blocked until the missing assets in the status table are implemented.

## Preflight

```powershell
.\scripts\check_dev_env.ps1 -RequireVivado -RequireSerialPort
.\scripts\test_rtl.ps1
.\scripts\test_streaming_rtl.ps1
.\scripts\test_frame_rtl.ps1
.\scripts\test_uart_rtl.ps1
```

## Acceptance

- All preflight commands exit with zero.
- The programmed bitstream matches the recorded SHA-256.
- Every transmitted Frame has one expected byte-exact response.
- No unexpected response, timeout, UART framing error, or FIFO overflow occurs.
- Result JSONL passes the fixed-vector evaluator.
- A run is not accepted without raw capture and the completed run record.

## Records

Copy [`RUN_RECORD_TEMPLATE.md`](RUN_RECORD_TEMPLATE.md) for each run. Store machine-readable artifacts under `datasets/test_results/bringup/` according to its README.
