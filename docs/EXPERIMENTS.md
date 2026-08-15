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
