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

## Prompt datasets

Prompt datasets live in `datasets/prompts/` as JSONL, one record per line.
`smoke.jsonl` holds the single prompt used by the smoke check.
`baseline_v1.jsonl` is the first measurement set, referenced by
`experiments/configs/qwen3_4b_baseline.yaml`.

Every record carries these fields:

| Field | Meaning |
| --- | --- |
| `prompt_id` | `<category prefix>-<three digits>`, unique within the dataset |
| `category` | Task domain |
| `answer_type` | `exact` for one correct answer, `free` for reviewed answers |
| `length_class` | `short`, `medium`, or `long` expected output |
| `prompt` | Prompt text |
| `expected` | Correct answer. Present only when `answer_type` is `exact` |
| `criteria` | Review condition. Present only when `answer_type` is `free` |

`baseline_v1.jsonl` covers nine domains, mixing scoring style, output length,
and token distribution so that later corruption experiments can separate those
factors:

| Category | Prefix | Records | Answer type | Length |
| --- | --- | ---: | --- | --- |
| sequence | `seq` | 5 | exact | short |
| arithmetic | `ari` | 6 | exact | short |
| weather | `wea` | 4 | exact | short |
| history | `his` | 4 | exact | short |
| commonsense | `com` | 4 | exact | short |
| translation | `tra` | 4 | free | medium |
| control | `ctl` | 4 | free | medium |
| story | `sto` | 3 | free | long |
| code, format, summary, extraction, conversion | `oth` | 5 | mixed | mixed |

Selection rules:

- Every prompt must be deterministic at `temperature: 0.0`.
- `exact` prompts instruct the model to answer with the value alone, so scoring
  is a string comparison.
- Weather prompts state their conditions inline. The model has no live data.
- Japanese and English prompts are both present, and the translation records
  exercise multilingual output.
- Free-form records record a review condition instead of an answer. Scoring
  them needs a semantic evaluator, which is not part of this dataset.

At the measured 5.63 tokens per second for Qwen3-4B Q4_K_M on CPU, one pass
over the 39 records takes roughly 15 to 20 minutes, dominated by the long
records.

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
