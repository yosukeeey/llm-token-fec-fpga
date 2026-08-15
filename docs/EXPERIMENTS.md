# Experiment configuration

Experiment definitions live in `experiments/configs/`. Each YAML file records
the model, generation controls, prompt dataset, channel, FEC, and optional
tracking settings needed by later experiment runners.

`results/raw/` contains generated JSONL and logs and is not tracked. Reviewed,
reproducible summaries may be committed under `results/processed/`.

Recreate the Python environment from a clean checkout with:

```powershell
uv sync --frozen
```

## Qwen3-4B CPU smoke check

The CPU inference path uses the official `Qwen/Qwen3-4B-GGUF` repository and
`Qwen3-4B-Q4_K_M.gguf`. GGUF is selected because inference runs on the CPU
through `llama.cpp` and `llama-cpp-python`.

| Field | Fixed value |
| --- | --- |
| Revision | `bc640142c66e1fdd12af0bd68f40445458f3869b` |
| Quantization | `Q4_K_M` |
| File size | `2497280256` bytes |
| SHA-256 | `7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5` |

Download the fixed revision into the ignored `models/` directory and verify
its SHA-256:

```powershell
uv run python -m scripts.download_qwen3_4b_gguf
```

Run one CPU-only, non-thinking smoke prompt. The JSON output contains the
response, rendered input token IDs, generated output token IDs, model identity,
file SHA-256, and installed `llama-cpp-python` version.

```powershell
uv run python -m scripts.run_qwen3_cpu_smoke --max-tokens 16
```
