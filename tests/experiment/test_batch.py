from pathlib import Path
from typing import Any

import pytest

from sw.experiment.batch import (
    BatchRecord,
    PromptRecord,
    completed_prompt_ids,
    load_prompts,
    run_prompts,
)
from sw.experiment.config import load_experiment_config
from sw.experiment.qwen3_cpu import InferenceResult, ModelMetadata

CONFIG_PATH = Path("experiments/configs/qwen3_4b_cpu.yaml")
DATASET_PATH = Path("datasets/prompts/smoke.jsonl")

METADATA = ModelMetadata(
    model_name="Qwen/Qwen3-4B-GGUF",
    model_source="https://huggingface.co/Qwen/Qwen3-4B-GGUF",
    model_revision="bc640142c66e1fdd12af0bd68f40445458f3869b",
    model_file="Qwen3-4B-Q4_K_M.gguf",
    quantization="Q4_K_M",
    model_sha256="a" * 64,
    llama_cpp_python_version="test-version",
)


def _write(path: Path, lines: list[str]) -> Path:
    path.write_text("".join(f"{line}\n" for line in lines), encoding="utf-8")
    return path


def test_loads_the_tracked_prompt_dataset() -> None:
    prompts = load_prompts(DATASET_PATH)

    assert prompts[0] == PromptRecord(
        prompt_id="smoke-001", prompt="Reply with only: OK"
    )


def test_rejects_repeated_prompt_ids(tmp_path: Path) -> None:
    dataset = _write(
        tmp_path / "prompts.jsonl",
        [
            '{"prompt_id": "a", "prompt": "one"}',
            '{"prompt_id": "a", "prompt": "two"}',
        ],
    )

    with pytest.raises(ValueError, match="repeats prompt_id a"):
        load_prompts(dataset)


@pytest.mark.parametrize(
    ("line", "message"),
    [
        ('{"prompt": "one"}', "missing prompt_id"),
        ('{"prompt_id": "a"}', "missing prompt"),
        ('{"prompt_id": "a", "prompt": "  "}', "prompt must be a non-empty string"),
        ('{"prompt_id": 1, "prompt": "one"}', "prompt_id must be a non-empty string"),
        ("not json", "is not valid JSON"),
    ],
)
def test_rejects_malformed_records(tmp_path: Path, line: str, message: str) -> None:
    dataset = _write(tmp_path / "prompts.jsonl", [line])

    with pytest.raises(ValueError, match=message):
        load_prompts(dataset)


def test_rejects_non_object_records(tmp_path: Path) -> None:
    dataset = _write(tmp_path / "prompts.jsonl", ['["a"]'])

    with pytest.raises(TypeError, match="must be a JSON object"):
        load_prompts(dataset)


def test_rejects_empty_dataset(tmp_path: Path) -> None:
    dataset = _write(tmp_path / "prompts.jsonl", ["", "  "])

    with pytest.raises(ValueError, match="contains no prompts"):
        load_prompts(dataset)


def test_missing_dataset_reports_the_path(tmp_path: Path) -> None:
    with pytest.raises(FileNotFoundError, match="prompt dataset not found"):
        load_prompts(tmp_path / "absent.jsonl")


def test_completed_prompt_ids_reads_recorded_lines(tmp_path: Path) -> None:
    results = _write(
        tmp_path / "results.jsonl",
        [
            '{"prompt_id": "a", "response": "one"}',
            "broken",
            '{"prompt_id": "b", "response": "two"}',
        ],
    )

    assert completed_prompt_ids(results) == {"a", "b"}
    assert completed_prompt_ids(tmp_path / "absent.jsonl") == set()


def test_run_prompts_measures_every_generation() -> None:
    config = load_experiment_config(CONFIG_PATH)
    prompts = (
        PromptRecord(prompt_id="p1", prompt="one"),
        PromptRecord(prompt_id="p2", prompt="two"),
    )
    seen: list[dict[str, Any]] = []
    ticks = iter([0.0, 2.0, 10.0, 14.0])

    def fake_inference(model: Any, metadata: Any, **options: Any) -> InferenceResult:
        seen.append(options)
        return InferenceResult(
            prompt=options["prompt"],
            response="OK",
            input_token_ids=(1, 2, 3),
            output_token_ids=(4, 5, 6, 7),
            model=metadata,
        )

    records = list(
        run_prompts(
            object(),
            METADATA,
            config,
            prompts,
            inference=fake_inference,
            clock=lambda: next(ticks),
        )
    )

    assert [record.prompt_id for record in records] == ["p1", "p2"]
    assert [record.generation_time_s for record in records] == [2.0, 4.0]
    assert [record.tokens_per_sec for record in records] == [2.0, 1.0]
    assert records[0].input_tokens == 3
    assert records[0].output_tokens == 4
    assert records[0].max_tokens == 128
    assert [options["max_tokens"] for options in seen] == [128, 128]
    assert [options["seed"] for options in seen] == [1, 1]
    assert [options["temperature"] for options in seen] == [0.0, 0.0]


def test_run_prompts_honours_a_max_token_override() -> None:
    config = load_experiment_config(CONFIG_PATH)
    seen: list[int] = []

    def fake_inference(model: Any, metadata: Any, **options: Any) -> InferenceResult:
        seen.append(options["max_tokens"])
        return InferenceResult(
            prompt=options["prompt"],
            response="OK",
            input_token_ids=(1,),
            output_token_ids=(2,),
            model=metadata,
        )

    list(
        run_prompts(
            object(),
            METADATA,
            config,
            (PromptRecord(prompt_id="p1", prompt="one"),),
            max_tokens=16,
            inference=fake_inference,
            clock=iter([0.0, 1.0]).__next__,
        )
    )

    assert seen == [16]


def test_record_carries_reproduction_metadata() -> None:
    config = load_experiment_config(CONFIG_PATH)
    record = BatchRecord(
        prompt_id="p1",
        prompt="one",
        response="OK",
        input_token_ids=(1, 2),
        output_token_ids=(3,),
        generation_time_s=0.5,
        input_tokens=2,
        output_tokens=1,
        tokens_per_sec=2.0,
        max_tokens=16,
    )

    line = record.to_dict(metadata=METADATA, config=config, git_commit="abc123")

    assert line["model"]["model_sha256"] == "a" * 64
    assert line["generation"]["seed"] == 1
    assert line["generation"]["max_tokens"] == 16
    assert line["generation"]["thinking"] is False
    assert line["experiment_name"] == config.name
    assert line["channel"] == config.channel
    assert line["fec"] == config.fec
    assert line["git_commit"] == "abc123"
    assert line["input_token_ids"] == [1, 2]
    assert record.metrics().tokens_per_sec == 2.0
