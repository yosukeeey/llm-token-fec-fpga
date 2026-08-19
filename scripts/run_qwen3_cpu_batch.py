"""Run Qwen3 CPU inference over a prompt dataset and record JSONL results."""

import argparse
import json
from datetime import UTC, datetime
from pathlib import Path

from sw.experiment import load_experiment_config
from sw.experiment.batch import (
    completed_prompt_ids,
    load_prompts,
    run_prompts,
)
from sw.experiment.qwen3_cpu import (
    MODEL_NAME,
    MODEL_QUANTIZATION,
    load_cpu_model,
    read_model_metadata,
)
from sw.experiment.tracking import WandbTracker, build_run_config, current_git_commit

DEFAULT_CONFIG = Path("experiments/configs/qwen3_4b_cpu.yaml")
DEFAULT_OUTPUT_DIR = Path("results/raw")


def main() -> int:
    """Generate one response per dataset prompt and append JSONL results.

    Returns
    -------
    int
        Zero after every selected prompt is recorded.

    Raises
    ------
    ValueError
        If the configuration does not match the supported CPU path.
    FileExistsError
        If the output exists without an explicit resume or overwrite request.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--output", type=Path)
    parser.add_argument("--max-tokens", type=int)
    parser.add_argument("--limit", type=int)
    parser.add_argument("--resume", action="store_true")
    parser.add_argument("--overwrite", action="store_true")
    arguments = parser.parse_args()

    config = load_experiment_config(arguments.config)
    if config.model.name != MODEL_NAME:
        raise ValueError(f"model.name must be {MODEL_NAME}")
    if config.model.quantization != MODEL_QUANTIZATION:
        raise ValueError(f"model.quantization must be {MODEL_QUANTIZATION}")
    if config.generation.thinking:
        raise ValueError("generation.thinking must be false for this batch path")
    if arguments.resume and arguments.overwrite:
        raise ValueError("--resume and --overwrite are mutually exclusive")

    if arguments.output is None:
        stamp = datetime.now(UTC).strftime("%Y%m%d_%H%M%S")
        output_path = DEFAULT_OUTPUT_DIR / f"{config.name}-{stamp}.jsonl"
    else:
        output_path = arguments.output

    if output_path.is_file() and not (arguments.resume or arguments.overwrite):
        raise FileExistsError(
            f"{output_path} exists. Pass --resume to continue or --overwrite to replace."
        )
    already_recorded = completed_prompt_ids(output_path) if arguments.resume else set()

    prompts = [
        record
        for record in load_prompts(config.prompt_dataset)
        if record.prompt_id not in already_recorded
    ]
    if arguments.limit is not None:
        prompts = prompts[: arguments.limit]

    if not prompts:
        print(
            json.dumps(
                {
                    "output": str(output_path),
                    "recorded": 0,
                    "skipped": len(already_recorded),
                    "total_output_tokens": 0,
                    "total_generation_time_s": 0.0,
                    "mean_tokens_per_sec": 0.0,
                },
                ensure_ascii=False,
                sort_keys=True,
            )
        )
        return 0

    metadata = read_model_metadata(config.model.path)
    git_commit = current_git_commit()
    output_path.parent.mkdir(parents=True, exist_ok=True)
    if arguments.overwrite and output_path.is_file():
        output_path.unlink()

    tracker = WandbTracker.start(
        config.tracking.wandb,
        build_run_config(
            config,
            model_sha256=metadata.model_sha256,
            prompt_id=Path(config.prompt_dataset).stem,
            git_commit=git_commit,
        ),
    )
    model = load_cpu_model(config.model.path, seed=config.generation.seed)

    recorded = 0
    total_output_tokens = 0
    total_generation_time_s = 0.0
    with output_path.open("a", encoding="utf-8") as result_file:
        for record in run_prompts(
            model,
            metadata,
            config,
            prompts,
            max_tokens=arguments.max_tokens,
        ):
            line = record.to_dict(
                metadata=metadata, config=config, git_commit=git_commit
            )
            result_file.write(
                json.dumps(line, ensure_ascii=False, sort_keys=True) + "\n"
            )
            result_file.flush()
            tracker.log(record.metrics())
            recorded += 1
            total_output_tokens += record.output_tokens
            total_generation_time_s += record.generation_time_s
    tracker.finish()

    print(
        json.dumps(
            {
                "output": str(output_path),
                "recorded": recorded,
                "skipped": len(already_recorded),
                "total_output_tokens": total_output_tokens,
                "total_generation_time_s": round(total_generation_time_s, 3),
                "mean_tokens_per_sec": (
                    round(total_output_tokens / total_generation_time_s, 3)
                    if total_generation_time_s > 0.0
                    else 0.0
                ),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
