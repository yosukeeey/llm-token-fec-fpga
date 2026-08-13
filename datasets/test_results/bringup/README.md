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

`manifest.json` records the board serial, Git commit, tool versions, bitstream SHA-256, COM settings, commands, and artifact SHA-256 values. `results.jsonl` uses the versioned `CaseResult` schema.

Do not overwrite an existing run. Failed runs are retained with their failure reason.
