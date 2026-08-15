from pathlib import Path

import pytest

from sw.experiment.config import load_experiment_config

CONFIG_PATH = Path("experiments/configs/qwen3_4b_cpu.yaml")


def test_loads_tracked_experiment_definition() -> None:
    config = load_experiment_config(CONFIG_PATH)

    assert config.name == "qwen3-4b-cpu-smoke"
    assert config.model.name == "Qwen/Qwen3-4B-GGUF"
    assert config.model.path == Path("models/Qwen3-4B-Q4_K_M.gguf")
    assert config.model.quantization == "Q4_K_M"
    assert config.generation.seed == 1
    assert config.generation.max_tokens == 128
    assert config.generation.temperature == 0.0
    assert config.generation.thinking is False
    assert config.prompt_dataset == Path("datasets/prompts/smoke.jsonl")
    assert config.channel == "none"
    assert config.fec == "none"
    assert config.tracking.wandb.enabled is False
    assert config.tracking.wandb.project == "llm-token-fec-fpga"


@pytest.mark.parametrize(
    ("replacement", "message"),
    [
        ("max_tokens: 128", "missing max_tokens"),
        ("temperature: 0.0", "generation.temperature must be numeric"),
        ("thinking: false", "generation.thinking must be a boolean"),
        ("enabled: false", "tracking.wandb.enabled must be a boolean"),
    ],
)
def test_rejects_invalid_required_values(
    tmp_path: Path, replacement: str, message: str
) -> None:
    source = CONFIG_PATH.read_text(encoding="utf-8")
    if replacement == "max_tokens: 128":
        invalid = source.replace("  max_tokens: 128\n", "")
    elif replacement == "temperature: 0.0":
        invalid = source.replace(replacement, "temperature: invalid")
    elif replacement == "thinking: false":
        invalid = source.replace(replacement, "thinking: disabled")
    else:
        invalid = source.replace(replacement, "enabled: disabled")
    path = tmp_path / "invalid.yaml"
    path.write_text(invalid, encoding="utf-8")

    with pytest.raises(ValueError, match=message):
        load_experiment_config(path)


def test_rejects_unknown_fields(tmp_path: Path) -> None:
    source = CONFIG_PATH.read_text(encoding="utf-8")
    path = tmp_path / "invalid.yaml"
    path.write_text(f"{source}unexpected: true\n", encoding="utf-8")

    with pytest.raises(ValueError, match="unknown unexpected"):
        load_experiment_config(path)
