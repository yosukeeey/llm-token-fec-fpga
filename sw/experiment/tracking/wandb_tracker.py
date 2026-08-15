"""Optional W&B experiment tracking."""

from __future__ import annotations

import os
from collections.abc import Mapping
from dataclasses import asdict, dataclass
from importlib import import_module
from netrc import NetrcParseError, netrc
from pathlib import Path
from typing import Protocol
from urllib.parse import urlparse

from sw.experiment.config import WandbConfig


class _WandbRun(Protocol):
    def log(self, data: Mapping[str, int | float]) -> None:
        """Record scalar metrics.

        Parameters
        ----------
        data : Mapping[str, int or float]
            Metrics for one generated response.
        """
        ...

    def finish(self) -> None: ...


@dataclass(frozen=True)
class WandbRunConfig:
    """Reproducibility metadata recorded for one experiment run.

    Attributes
    ----------
    experiment_name : str
        Experiment identifier.
    model_name : str
        Stable model identifier.
    model_sha256 : str
        SHA-256 digest of the model file.
    quantization : str
        Model quantization identifier.
    seed : int
        Generation random seed.
    max_tokens : int
        Maximum generated token count.
    temperature : float
        Sampling temperature.
    thinking : bool
        Whether thinking mode is enabled.
    prompt_id : str
        Prompt dataset record identifier.
    channel : str
        Channel model identifier.
    fec : str
        FEC scheme identifier.
    git_commit : str
        Source commit identifier.
    """

    experiment_name: str
    model_name: str
    model_sha256: str
    quantization: str
    seed: int
    max_tokens: int
    temperature: float
    thinking: bool
    prompt_id: str
    channel: str
    fec: str
    git_commit: str


@dataclass(frozen=True)
class GenerationMetrics:
    """Generation measurements recorded for one prompt.

    Attributes
    ----------
    generation_time_s : float
        Wall-clock generation time in seconds.
    input_tokens : int
        Input token count.
    output_tokens : int
        Output token count.
    tokens_per_sec : float
        Output token throughput.
    """

    generation_time_s: float
    input_tokens: int
    output_tokens: int
    tokens_per_sec: float


def _has_online_credentials(environment: Mapping[str, str]) -> bool:
    if environment.get("WANDB_API_KEY"):
        return True

    base_url = environment.get("WANDB_BASE_URL", "https://api.wandb.ai")
    parsed_url = urlparse(base_url if "://" in base_url else f"https://{base_url}")
    if parsed_url.hostname is None:
        return False

    explicit_path = environment.get("NETRC")
    paths = (
        (Path(explicit_path),)
        if explicit_path
        else (Path.home() / ".netrc", Path.home() / "_netrc")
    )
    for path in paths:
        try:
            credentials = netrc(path).authenticators(parsed_url.hostname)
        except (FileNotFoundError, NetrcParseError, OSError):
            continue
        if credentials is not None and credentials[2]:
            return True
    return False


@dataclass
class WandbTracker:
    """Thin optional adapter around one W&B run."""

    _run: _WandbRun | None = None

    @classmethod
    def start(
        cls,
        settings: WandbConfig,
        run_config: WandbRunConfig,
        *,
        environ: Mapping[str, str] | None = None,
    ) -> WandbTracker:
        """Start tracking when configured and credentials permit it.

        Parameters
        ----------
        settings : WandbConfig
            Project-level W&B settings.
        run_config : WandbRunConfig
            Reproducibility metadata for the run.
        environ : Mapping[str, str], optional
            Environment used to select credentials and offline mode.

        Returns
        -------
        WandbTracker
            Active adapter or a safe no-op adapter.
        """
        if not settings.enabled:
            return cls()

        environment = os.environ if environ is None else environ
        requested_mode = environment.get("WANDB_MODE", "").lower()
        if requested_mode == "disabled":
            return cls()
        offline = requested_mode in {"offline", "dryrun"}
        if not offline and not _has_online_credentials(environment):
            return cls()

        try:
            wandb = import_module("wandb")
            init_options = {
                "project": settings.project,
                "name": run_config.experiment_name,
                "config": asdict(run_config),
            }
            if offline:
                init_options["mode"] = "offline"
            run = wandb.init(**init_options)
        except Exception:  # noqa: BLE001
            # Tracking failures must never stop the local experiment.
            return cls()
        return cls(_run=run)

    @property
    def active(self) -> bool:
        """Return whether a W&B run is active."""
        return self._run is not None

    def log(self, metrics: GenerationMetrics) -> None:
        """Record generation metrics when tracking is active.

        Parameters
        ----------
        metrics : GenerationMetrics
            Measurements for one generated response.
        """
        if self._run is not None:
            try:
                self._run.log(asdict(metrics))
            except Exception:  # noqa: BLE001
                # Tracking failures must never stop the local experiment.
                return

    def finish(self) -> None:
        """Finish the active run, if any."""
        run = self._run
        self._run = None
        if run is not None:
            try:
                run.finish()
            except Exception:  # noqa: BLE001
                # Tracking failures must never stop the local experiment.
                return
