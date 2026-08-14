# Bring-up Results

Store one immutable directory per hardware run.

```text
basys3/
  <run-id>/
    run.md
    manifest.json
    uart-capture.bin
    results.jsonl
    evaluation.txt
```

`run-id` uses `YYYYMMDDTHHMMSS+0900-<git-short-sha>`.

`uart-capture.bin` contains RX bytes in transport order without Frame repair or byte transformation. `results.jsonl` uses the versioned `CaseResult` schema and contains one actual response Frame per completed case. Result status names are decoded from the received TOKEN_RESULT or ERROR_RESPONSE payload.

`manifest.json` records the board serial, Git commit, tool versions, bitstream SHA-256, COM settings, commands, and artifact SHA-256 values.

Do not overwrite an existing run. Failed runs are retained with their failure reason.
