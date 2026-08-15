import json
from pathlib import Path

import pytest

from sw.experiment.config import load_experiment_config

DATASET_PATH = Path("datasets/prompts/baseline_v1.jsonl")
CONFIG_PATH = Path("experiments/configs/qwen3_4b_baseline.yaml")
REQUIRED_FIELDS = {"prompt_id", "category", "answer_type", "length_class", "prompt"}
ANSWER_TYPES = {"exact", "free"}
LENGTH_CLASSES = {"short", "medium", "long"}
PROMPT_ID_PREFIXES = {
    "sequence": "seq",
    "arithmetic": "ari",
    "weather": "wea",
    "history": "his",
    "commonsense": "com",
    "translation": "tra",
    "control": "ctl",
    "story": "sto",
}


def _records() -> list[dict]:
    lines = DATASET_PATH.read_text(encoding="utf-8").splitlines()
    return [json.loads(line) for line in lines if line.strip()]


def test_dataset_records_are_unique_and_non_empty() -> None:
    records = _records()

    assert records
    prompt_ids = [record["prompt_id"] for record in records]
    assert len(set(prompt_ids)) == len(prompt_ids)
    for record in records:
        assert record["prompt"].strip(), record["prompt_id"]


def test_every_record_carries_the_classification_fields() -> None:
    for record in _records():
        missing = REQUIRED_FIELDS - set(record)
        assert not missing, f"{record.get('prompt_id')} is missing {sorted(missing)}"
        assert record["answer_type"] in ANSWER_TYPES
        assert record["length_class"] in LENGTH_CLASSES


def test_exact_records_carry_an_expected_answer() -> None:
    for record in _records():
        if record["answer_type"] != "exact":
            continue
        expected = record.get("expected")
        assert isinstance(expected, str) and expected.strip(), record["prompt_id"]
        assert "criteria" not in record, record["prompt_id"]


def test_free_records_carry_review_criteria() -> None:
    for record in _records():
        if record["answer_type"] != "free":
            continue
        criteria = record.get("criteria")
        assert isinstance(criteria, str) and criteria.strip(), record["prompt_id"]
        assert "expected" not in record, record["prompt_id"]


def test_prompt_ids_follow_the_category_prefix() -> None:
    for record in _records():
        prefix = PROMPT_ID_PREFIXES.get(record["category"], "oth")
        prompt_id = record["prompt_id"]
        assert prompt_id.startswith(f"{prefix}-"), prompt_id
        assert prompt_id.split("-")[1].isdigit(), prompt_id
        assert len(prompt_id.split("-")[1]) == 3, prompt_id


@pytest.mark.parametrize(
    ("answer_type", "minimum"),
    [("exact", 20), ("free", 10)],
)
def test_dataset_covers_both_answer_types(answer_type: str, minimum: int) -> None:
    counted = sum(
        1 for record in _records() if record["answer_type"] == answer_type
    )

    assert counted >= minimum


def test_dataset_covers_every_length_class() -> None:
    observed = {record["length_class"] for record in _records()}

    assert observed == LENGTH_CLASSES


def test_baseline_config_points_at_the_dataset() -> None:
    config = load_experiment_config(CONFIG_PATH)

    assert config.name == "qwen3-4b-baseline"
    assert config.prompt_dataset == DATASET_PATH
    assert config.generation.thinking is False
    assert config.generation.temperature == 0.0
    assert config.tracking.wandb.enabled is False
