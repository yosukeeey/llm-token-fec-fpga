"""Run one Qwen3 CPU inference smoke check."""

import argparse
import json
from pathlib import Path

from sw.experiment import load_experiment_config
from sw.experiment.qwen3_cpu import (
    MODEL_NAME,
    MODEL_QUANTIZATION,
    load_cpu_model,
    read_model_metadata,
    run_non_thinking_inference,
)

DEFAULT_CONFIG = Path("experiments/configs/qwen3_4b_cpu.yaml")


def main() -> int:
    """Run one configured non-thinking prompt and print JSON.

    Returns
    -------
    int
        Zero after successful inference.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--prompt", default="Reply with only: OK")
    parser.add_argument("--max-tokens", type=int)
    arguments = parser.parse_args()

    config = load_experiment_config(arguments.config)
    if config.model.name != MODEL_NAME:
        raise ValueError(f"model.name must be {MODEL_NAME}")
    if config.model.quantization != MODEL_QUANTIZATION:
        raise ValueError(f"model.quantization must be {MODEL_QUANTIZATION}")
    if config.generation.thinking:
        raise ValueError("generation.thinking must be false for this smoke path")

    max_tokens = (
        config.generation.max_tokens
        if arguments.max_tokens is None
        else arguments.max_tokens
    )
    metadata = read_model_metadata(config.model.path)
    model = load_cpu_model(config.model.path, seed=config.generation.seed)
    result = run_non_thinking_inference(
        model,
        metadata,
        prompt=arguments.prompt,
        seed=config.generation.seed,
        max_tokens=max_tokens,
        temperature=config.generation.temperature,
    )
    print(json.dumps(result.to_dict(), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
