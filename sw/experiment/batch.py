"""Batch CPU inference over a prompt dataset."""

from collections.abc import Callable, Iterable, Iterator, Sequence
from dataclasses import asdict, dataclass
from json import JSONDecodeError, loads
from pathlib import Path
from time import perf_counter
from typing import Any

from sw.experiment.config import ExperimentConfig
from sw.experiment.qwen3_cpu import (
    InferenceResult,
    ModelMetadata,
    run_non_thinking_inference,
)
from sw.experiment.tracking import GenerationMetrics


@dataclass(frozen=True)
class PromptRecord:
    """One prompt dataset record.

    Attributes
    ----------
    prompt_id : str
        Identifier unique within the dataset.
    prompt : str
        User prompt text.
    """

    prompt_id: str
    prompt: str


@dataclass(frozen=True)
class BatchRecord:
    """One generated response with its measurements.

    Attributes
    ----------
    prompt_id : str
        Prompt dataset record identifier.
    prompt : str
        User prompt text.
    response : str
        Generated response text.
    input_token_ids : tuple[int, ...]
        Token IDs for the rendered chat prompt.
    output_token_ids : tuple[int, ...]
        Generated token IDs.
    generation_time_s : float
        Wall-clock generation time in seconds.
    input_tokens : int
        Input token count.
    output_tokens : int
        Output token count.
    tokens_per_sec : float
        Output token throughput.
    max_tokens : int
        Maximum generated token count applied to this generation.
    """

    prompt_id: str
    prompt: str
    response: str
    input_token_ids: tuple[int, ...]
    output_token_ids: tuple[int, ...]
    generation_time_s: float
    input_tokens: int
    output_tokens: int
    tokens_per_sec: float
    max_tokens: int

    def metrics(self) -> GenerationMetrics:
        """Convert the measurements to tracking metrics.

        Returns
        -------
        sw.experiment.tracking.GenerationMetrics
            Metrics recorded for this response.
        """
        return GenerationMetrics(
            generation_time_s=self.generation_time_s,
            input_tokens=self.input_tokens,
            output_tokens=self.output_tokens,
            tokens_per_sec=self.tokens_per_sec,
        )

    def to_dict(
        self,
        *,
        metadata: ModelMetadata,
        config: ExperimentConfig,
        git_commit: str,
    ) -> dict[str, Any]:
        """Build a self-contained JSON-compatible result line.

        Parameters
        ----------
        metadata : sw.experiment.qwen3_cpu.ModelMetadata
            Verified model identity.
        config : sw.experiment.config.ExperimentConfig
            Experiment definition used for the run.
        git_commit : str
            Source commit identifier.

        Returns
        -------
        dict[str, Any]
            Result, measurements, model identity, and generation settings.
        """
        return {
            "experiment_name": config.name,
            "prompt_id": self.prompt_id,
            "prompt": self.prompt,
            "response": self.response,
            "input_token_ids": list(self.input_token_ids),
            "output_token_ids": list(self.output_token_ids),
            "generation_time_s": self.generation_time_s,
            "input_tokens": self.input_tokens,
            "output_tokens": self.output_tokens,
            "tokens_per_sec": self.tokens_per_sec,
            "model": asdict(metadata),
            "generation": {
                **asdict(config.generation),
                "max_tokens": self.max_tokens,
            },
            "channel": config.channel,
            "fec": config.fec,
            "git_commit": git_commit,
        }


def load_prompts(path: str | Path) -> tuple[PromptRecord, ...]:
    """Read and validate one JSONL prompt dataset.

    Parameters
    ----------
    path : str or pathlib.Path
        Prompt dataset path.

    Returns
    -------
    tuple[PromptRecord, ...]
        Dataset records in file order.

    Raises
    ------
    FileNotFoundError
        If the dataset is not present.
    TypeError
        If a line is not a JSON object.
    ValueError
        If a line is malformed, incomplete, or repeats a prompt ID.
    """
    dataset_path = Path(path)
    if not dataset_path.is_file():
        raise FileNotFoundError(f"prompt dataset not found: {dataset_path}")

    records: list[PromptRecord] = []
    seen: set[str] = set()
    for number, line in enumerate(
        dataset_path.read_text(encoding="utf-8").splitlines(), start=1
    ):
        if not line.strip():
            continue
        try:
            document = loads(line)
        except JSONDecodeError as error:
            raise ValueError(f"{dataset_path}:{number} is not valid JSON") from error
        if not isinstance(document, dict):
            raise TypeError(f"{dataset_path}:{number} must be a JSON object")
        missing = {"prompt_id", "prompt"} - set(document)
        if missing:
            raise ValueError(
                f"{dataset_path}:{number} is missing {', '.join(sorted(missing))}"
            )
        prompt_id = document["prompt_id"]
        prompt = document["prompt"]
        for name, value in (("prompt_id", prompt_id), ("prompt", prompt)):
            if not isinstance(value, str) or not value.strip():
                raise ValueError(
                    f"{dataset_path}:{number} {name} must be a non-empty string"
                )
        if prompt_id in seen:
            raise ValueError(f"{dataset_path}:{number} repeats prompt_id {prompt_id}")
        seen.add(prompt_id)
        records.append(PromptRecord(prompt_id=prompt_id, prompt=prompt))

    if not records:
        raise ValueError(f"{dataset_path} contains no prompts")
    return tuple(records)


def completed_prompt_ids(path: str | Path) -> set[str]:
    """Collect prompt IDs already present in a result file.

    Parameters
    ----------
    path : str or pathlib.Path
        Result JSONL path. A missing file yields an empty set.

    Returns
    -------
    set[str]
        Prompt IDs recorded by an earlier run.
    """
    result_path = Path(path)
    if not result_path.is_file():
        return set()

    completed: set[str] = set()
    for line in result_path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            document = loads(line)
        except JSONDecodeError:
            continue
        prompt_id = document.get("prompt_id") if isinstance(document, dict) else None
        if isinstance(prompt_id, str):
            completed.add(prompt_id)
    return completed


def run_prompts(
    model: Any,
    metadata: ModelMetadata,
    config: ExperimentConfig,
    prompts: Sequence[PromptRecord] | Iterable[PromptRecord],
    *,
    max_tokens: int | None = None,
    inference: Callable[..., InferenceResult] = run_non_thinking_inference,
    clock: Callable[[], float] = perf_counter,
) -> Iterator[BatchRecord]:
    """Generate one response per prompt and measure each generation.

    Parameters
    ----------
    model : Any
        Loaded ``llama_cpp.Llama`` model.
    metadata : sw.experiment.qwen3_cpu.ModelMetadata
        Verified model identity.
    config : sw.experiment.config.ExperimentConfig
        Experiment definition supplying generation controls.
    prompts : collections.abc.Sequence or collections.abc.Iterable
        Prompt dataset records to generate.
    max_tokens : int or None
        Maximum generated token count. The configured value is used when omitted.
    inference : collections.abc.Callable
        Generation function, replaced in tests.
    clock : collections.abc.Callable
        Monotonic clock returning seconds, replaced in tests.

    Yields
    ------
    BatchRecord
        Response and measurements for one prompt.
    """
    limit = config.generation.max_tokens if max_tokens is None else max_tokens
    for record in prompts:
        started = clock()
        result = inference(
            model,
            metadata,
            prompt=record.prompt,
            seed=config.generation.seed,
            max_tokens=limit,
            temperature=config.generation.temperature,
        )
        generation_time_s = clock() - started
        output_tokens = len(result.output_token_ids)
        yield BatchRecord(
            prompt_id=record.prompt_id,
            prompt=record.prompt,
            response=result.response,
            input_token_ids=tuple(result.input_token_ids),
            output_token_ids=tuple(result.output_token_ids),
            generation_time_s=generation_time_s,
            input_tokens=len(result.input_token_ids),
            output_tokens=output_tokens,
            tokens_per_sec=(
                output_tokens / generation_time_s if generation_time_s > 0.0 else 0.0
            ),
            max_tokens=limit,
        )
