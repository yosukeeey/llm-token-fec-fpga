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

## W&B tracking

Tracking is optional and off by default (`tracking.wandb.enabled: false`). The
adapter in `sw/experiment/tracking/` is the only place that calls the W&B SDK.
It records the run configuration (experiment name, model name, SHA-256,
quantization, seed, max tokens, temperature, thinking, prompt ID, channel, FEC,
git commit) and per-generation metrics (generation time, input and output token
counts, tokens per second).

The adapter stays inactive, without importing the SDK, when tracking is
disabled or when no credentials are available, so local experiments never
depend on W&B.

| Mode | Condition | Result |
| --- | --- | --- |
| Disabled | `tracking.wandb.enabled: false` | No SDK import, no network |
| Offline | `WANDB_MODE=offline` | Local run under ignored `wandb/` |
| Online | `WANDB_API_KEY` or a `~/.netrc` entry for `api.wandb.ai` | Uploaded run |

Record one dummy run without loading a model. `--enable-tracking` overrides the
disabled setting in the config file:

```powershell
$env:WANDB_MODE = "offline"
uv run python -m scripts.run_wandb_dummy --enable-tracking
```

The smoke command records the same fields for a real generation when tracking
is enabled:

```powershell
uv run python -m scripts.run_qwen3_cpu_smoke --max-tokens 16 --prompt-id smoke-001
```

Offline runs stay local under `wandb/`, which is ignored. Upload one later with
`wandb sync wandb/offline-run-<id>`.
