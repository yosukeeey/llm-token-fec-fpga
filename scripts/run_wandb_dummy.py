"""Record one dummy W&B tracking run without model inference."""

import argparse
import json
from dataclasses import asdict, replace
from pathlib import Path

from sw.experiment import load_experiment_config
from sw.experiment.tracking import (
    GenerationMetrics,
    WandbTracker,
    build_run_config,
    current_git_commit,
)

DEFAULT_CONFIG = Path("experiments/configs/qwen3_4b_cpu.yaml")
DUMMY_MODEL_SHA256 = "0" * 64
DUMMY_METRICS = GenerationMetrics(
    generation_time_s=2.0,
    input_tokens=8,
    output_tokens=16,
    tokens_per_sec=8.0,
)


def main() -> int:
    """Track one dummy run and print what tracking received.

    Returns
    -------
    int
        Zero after the dummy run completes.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--config", type=Path, default=DEFAULT_CONFIG)
    parser.add_argument("--prompt-id", default="dummy-001")
    parser.add_argument("--enable-tracking", action="store_true")
    arguments = parser.parse_args()

    config = load_experiment_config(arguments.config)
    if arguments.enable_tracking:
        config = replace(
            config,
            tracking=replace(
                config.tracking,
                wandb=replace(config.tracking.wandb, enabled=True),
            ),
        )

    run_config = build_run_config(
        config,
        model_sha256=DUMMY_MODEL_SHA256,
        prompt_id=arguments.prompt_id,
        git_commit=current_git_commit(),
    )
    tracker = WandbTracker.start(config.tracking.wandb, run_config)
    tracking_active = tracker.active
    tracker.log(DUMMY_METRICS)
    tracker.finish()

    print(
        json.dumps(
            {
                "tracking_active": tracking_active,
                "run_config": asdict(run_config),
                "metrics": asdict(DUMMY_METRICS),
            },
            ensure_ascii=False,
            sort_keys=True,
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
