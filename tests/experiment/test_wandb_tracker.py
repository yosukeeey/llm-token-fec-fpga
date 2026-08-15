import subprocess
from dataclasses import asdict
from pathlib import Path
from typing import Any

import sw.experiment.tracking.wandb_tracker as tracker_module
from sw.experiment.config import WandbConfig, load_experiment_config
from sw.experiment.tracking import (
    GenerationMetrics,
    WandbRunConfig,
    WandbTracker,
    build_run_config,
    current_git_commit,
)

CONFIG_PATH = Path("experiments/configs/qwen3_4b_cpu.yaml")

RUN_CONFIG = WandbRunConfig(
    experiment_name="wandb-dummy",
    model_name="Qwen/Qwen3-4B-GGUF",
    model_sha256="a" * 64,
    quantization="Q4_K_M",
    seed=1,
    max_tokens=128,
    temperature=0.0,
    thinking=False,
    prompt_id="smoke-001",
    channel="none",
    fec="none",
    git_commit="0123456789abcdef",
)
METRICS = GenerationMetrics(
    generation_time_s=2.0,
    input_tokens=8,
    output_tokens=16,
    tokens_per_sec=8.0,
)


class FakeRun:
    def __init__(self) -> None:
        self.logged: list[dict[str, Any]] = []
        self.finished = False

    def log(self, data: dict[str, Any]) -> None:
        self.logged.append(data)

    def finish(self) -> None:
        self.finished = True


class FakeWandb:
    def __init__(self) -> None:
        self.run = FakeRun()
        self.init_options: dict[str, Any] | None = None

    def init(self, **options: Any) -> FakeRun:
        self.init_options = options
        return self.run


def test_build_run_config_maps_tracked_experiment_fields() -> None:
    config = load_experiment_config(CONFIG_PATH)

    run_config = build_run_config(
        config,
        model_sha256="b" * 64,
        prompt_id="smoke-001",
        git_commit="0123456789abcdef",
    )

    assert run_config == WandbRunConfig(
        experiment_name="qwen3-4b-cpu-smoke",
        model_name="Qwen/Qwen3-4B-GGUF",
        model_sha256="b" * 64,
        quantization="Q4_K_M",
        seed=1,
        max_tokens=128,
        temperature=0.0,
        thinking=False,
        prompt_id="smoke-001",
        channel="none",
        fec="none",
        git_commit="0123456789abcdef",
    )


def test_current_git_commit_returns_resolved_hash(monkeypatch: Any) -> None:
    def fake_run(command: list[str], **options: Any) -> Any:
        assert command == ["git", "rev-parse", "HEAD"]
        return subprocess.CompletedProcess(command, 0, stdout="abc123\n", stderr="")

    monkeypatch.setattr(tracker_module.subprocess, "run", fake_run)

    assert current_git_commit() == "abc123"


def test_current_git_commit_falls_back_when_git_is_unavailable(
    monkeypatch: Any,
) -> None:
    def failing_run(command: list[str], **options: Any) -> Any:
        raise OSError("git missing")

    monkeypatch.setattr(tracker_module.subprocess, "run", failing_run)

    assert current_git_commit() == tracker_module.UNKNOWN_GIT_COMMIT


def test_disabled_tracking_does_not_import_wandb(monkeypatch: Any) -> None:
    def unexpected_import(name: str) -> None:
        raise AssertionError(f"unexpected import: {name}")

    monkeypatch.setattr(tracker_module, "import_module", unexpected_import)

    tracker = WandbTracker.start(
        WandbConfig(enabled=False, project="llm-token-fec-fpga"), RUN_CONFIG
    )
    tracker.log(METRICS)
    tracker.finish()

    assert tracker.active is False


def test_missing_credentials_fall_back_without_import(monkeypatch: Any) -> None:
    def unexpected_import(name: str) -> None:
        raise AssertionError(f"unexpected import: {name}")

    monkeypatch.setattr(tracker_module, "import_module", unexpected_import)

    tracker = WandbTracker.start(
        WandbConfig(enabled=True, project="llm-token-fec-fpga"),
        RUN_CONFIG,
        environ={"NETRC": "missing-netrc-for-test"},
    )

    assert tracker.active is False


def test_netrc_credential_allows_online_tracking(
    monkeypatch: Any, tmp_path: Path
) -> None:
    netrc_path = tmp_path / "netrc"
    netrc_path.write_text(
        "machine api.wandb.ai login test-user password test-key\n",
        encoding="utf-8",
    )
    fake_wandb = FakeWandb()
    monkeypatch.setattr(tracker_module, "import_module", lambda name: fake_wandb)

    tracker = WandbTracker.start(
        WandbConfig(enabled=True, project="llm-token-fec-fpga"),
        RUN_CONFIG,
        environ={"NETRC": str(netrc_path)},
    )

    assert tracker.active is True


def test_enabled_tracking_records_required_config_and_metrics(monkeypatch: Any) -> None:
    fake_wandb = FakeWandb()
    monkeypatch.setattr(tracker_module, "import_module", lambda name: fake_wandb)

    tracker = WandbTracker.start(
        WandbConfig(enabled=True, project="llm-token-fec-fpga"),
        RUN_CONFIG,
        environ={"WANDB_API_KEY": "test-key"},
    )
    tracker.log(METRICS)

    assert tracker.active is True
    assert fake_wandb.init_options == {
        "project": "llm-token-fec-fpga",
        "name": "wandb-dummy",
        "config": asdict(RUN_CONFIG),
    }
    assert fake_wandb.run.logged == [asdict(METRICS)]
    tracker.finish()
    assert fake_wandb.run.finished is True
    assert tracker.active is False


def test_offline_tracking_needs_no_api_key(monkeypatch: Any) -> None:
    fake_wandb = FakeWandb()
    monkeypatch.setattr(tracker_module, "import_module", lambda name: fake_wandb)

    tracker = WandbTracker.start(
        WandbConfig(enabled=True, project="llm-token-fec-fpga"),
        RUN_CONFIG,
        environ={"WANDB_MODE": "offline"},
    )

    assert tracker.active is True
    assert fake_wandb.init_options is not None
    assert fake_wandb.init_options["mode"] == "offline"


def test_log_and_finish_failures_do_not_escape(monkeypatch: Any) -> None:
    class FailingRun:
        @staticmethod
        def log(data: dict[str, Any]) -> None:
            raise RuntimeError("log unavailable")

        @staticmethod
        def finish() -> None:
            raise RuntimeError("finish unavailable")

    class FailingWandb:
        @staticmethod
        def init(**options: Any) -> FailingRun:
            return FailingRun()

    monkeypatch.setattr(tracker_module, "import_module", lambda name: FailingWandb())

    tracker = WandbTracker.start(
        WandbConfig(enabled=True, project="llm-token-fec-fpga"),
        RUN_CONFIG,
        environ={"WANDB_MODE": "offline"},
    )
    tracker.log(METRICS)
    tracker.finish()

    assert tracker.active is False


def test_wandb_initialization_failure_falls_back(monkeypatch: Any) -> None:
    class FailingWandb:
        @staticmethod
        def init(**options: Any) -> None:
            raise RuntimeError("unavailable")

    monkeypatch.setattr(tracker_module, "import_module", lambda name: FailingWandb())

    tracker = WandbTracker.start(
        WandbConfig(enabled=True, project="llm-token-fec-fpga"),
        RUN_CONFIG,
        environ={"WANDB_API_KEY": "test-key"},
    )

    assert tracker.active is False
