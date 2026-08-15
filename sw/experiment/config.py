"""Experiment configuration loading and validation."""

from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path
from typing import Any

import yaml


@dataclass(frozen=True)
class ModelConfig:
    """Local model selection.

    Attributes
    ----------
    name : str
        Stable model name.
    path : pathlib.Path
        Local model file path.
    quantization : str
        Model quantization identifier.
    """

    name: str
    path: Path
    quantization: str


@dataclass(frozen=True)
class GenerationConfig:
    """Text generation controls.

    Attributes
    ----------
    seed : int
        Random seed.
    max_tokens : int
        Maximum generated token count.
    temperature : float
        Sampling temperature.
    thinking : bool
        Whether thinking mode is enabled.
    """

    seed: int
    max_tokens: int
    temperature: float
    thinking: bool


@dataclass(frozen=True)
class WandbConfig:
    """Optional W&B settings.

    Attributes
    ----------
    enabled : bool
        Whether W&B tracking is requested.
    project : str
        W&B project name.
    """

    enabled: bool
    project: str


@dataclass(frozen=True)
class TrackingConfig:
    """Experiment tracking settings.

    Attributes
    ----------
    wandb : WandbConfig
        W&B adapter settings.
    """

    wandb: WandbConfig


@dataclass(frozen=True)
class ExperimentConfig:
    """Validated experiment definition.

    Attributes
    ----------
    name : str
        Experiment name.
    model : ModelConfig
        Local model selection.
    generation : GenerationConfig
        Generation controls.
    prompt_dataset : pathlib.Path
        Prompt dataset path.
    channel : str
        Channel model identifier.
    fec : str
        FEC scheme identifier.
    tracking : TrackingConfig
        Optional tracking settings.
    """

    name: str
    model: ModelConfig
    generation: GenerationConfig
    prompt_dataset: Path
    channel: str
    fec: str
    tracking: TrackingConfig


def _mapping(value: Any, location: str) -> Mapping[str, Any]:
    if not isinstance(value, Mapping):
        raise TypeError(f"{location} must be a mapping")
    return value


def _keys(value: Mapping[str, Any], location: str, expected: set[str]) -> None:
    actual = set(value)
    if actual != expected:
        missing = sorted(expected - actual)
        unknown = sorted(actual - expected)
        details = []
        if missing:
            details.append(f"missing {', '.join(missing)}")
        if unknown:
            details.append(f"unknown {', '.join(unknown)}")
        raise ValueError(f"{location}: {'; '.join(details)}")


def _text(value: Any, location: str) -> str:
    if not isinstance(value, str) or not value.strip():
        raise ValueError(f"{location} must be a non-empty string")
    return value


def _integer(value: Any, location: str, *, positive: bool = False) -> int:
    if type(value) is not int:
        raise ValueError(f"{location} must be an integer")
    if positive and value <= 0:
        raise ValueError(f"{location} must be positive")
    return value


def _temperature(value: Any) -> float:
    if type(value) not in {int, float}:
        raise ValueError("generation.temperature must be numeric")
    result = float(value)
    if result < 0.0:
        raise ValueError("generation.temperature must be non-negative")
    return result


def load_experiment_config(path: str | Path) -> ExperimentConfig:
    """Load and validate one YAML experiment definition.

    Parameters
    ----------
    path : str or pathlib.Path
        YAML configuration path.

    Returns
    -------
    ExperimentConfig
        Validated immutable configuration.

    Raises
    ------
    TypeError
        If a required mapping has the wrong type.
    ValueError
        If the document is malformed or contains unsupported fields.
    """
    config_path = Path(path)
    document = _mapping(
        yaml.safe_load(config_path.read_text(encoding="utf-8")), "config"
    )
    _keys(
        document,
        "config",
        {
            "name",
            "model",
            "generation",
            "prompt_dataset",
            "channel",
            "fec",
            "tracking",
        },
    )

    model = _mapping(document["model"], "model")
    _keys(model, "model", {"name", "path", "quantization"})
    generation = _mapping(document["generation"], "generation")
    _keys(
        generation,
        "generation",
        {"seed", "max_tokens", "temperature", "thinking"},
    )
    tracking = _mapping(document["tracking"], "tracking")
    _keys(tracking, "tracking", {"wandb"})
    wandb = _mapping(tracking["wandb"], "tracking.wandb")
    _keys(wandb, "tracking.wandb", {"enabled", "project"})

    thinking = generation["thinking"]
    if type(thinking) is not bool:
        raise ValueError("generation.thinking must be a boolean")
    wandb_enabled = wandb["enabled"]
    if type(wandb_enabled) is not bool:
        raise ValueError("tracking.wandb.enabled must be a boolean")

    return ExperimentConfig(
        name=_text(document["name"], "name"),
        model=ModelConfig(
            name=_text(model["name"], "model.name"),
            path=Path(_text(model["path"], "model.path")),
            quantization=_text(model["quantization"], "model.quantization"),
        ),
        generation=GenerationConfig(
            seed=_integer(generation["seed"], "generation.seed"),
            max_tokens=_integer(
                generation["max_tokens"],
                "generation.max_tokens",
                positive=True,
            ),
            temperature=_temperature(generation["temperature"]),
            thinking=thinking,
        ),
        prompt_dataset=Path(_text(document["prompt_dataset"], "prompt_dataset")),
        channel=_text(document["channel"], "channel"),
        fec=_text(document["fec"], "fec"),
        tracking=TrackingConfig(
            wandb=WandbConfig(
                enabled=wandb_enabled,
                project=_text(wandb["project"], "tracking.wandb.project"),
            )
        ),
    )
