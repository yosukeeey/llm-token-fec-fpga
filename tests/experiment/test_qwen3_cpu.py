import sys
from pathlib import Path
from types import ModuleType, SimpleNamespace

import pytest

from sw.experiment.qwen3_cpu import (
    MODEL_FILENAME,
    MODEL_NAME,
    MODEL_QUANTIZATION,
    MODEL_REVISION,
    ModelMetadata,
    load_cpu_model,
    read_model_metadata,
    run_non_thinking_inference,
    sha256_file,
)


class FakeModel:
    def __init__(self) -> None:
        self.metadata = {"tokenizer.chat_template": "template"}
        self.formatted_prompt = ""
        self.seed = -1

    def token_bos(self) -> int:
        return 1

    def token_eos(self) -> int:
        return 2

    def tokenize(
        self, text: bytes, add_bos: bool = True, special: bool = False
    ) -> list[int]:
        assert add_bos is False
        assert special is True
        self.formatted_prompt = text.decode("utf-8")
        return [10, 11, 12]

    def detokenize(
        self,
        tokens: list[int],
        prev_tokens: list[int] | None = None,
        special: bool = False,
    ) -> bytes:
        if special:
            return {1: b"<s>", 2: b"<|im_end|>"}[tokens[0]]
        assert prev_tokens == [10, 11, 12]
        return b"OK"

    def set_seed(self, seed: int) -> None:
        self.seed = seed

    def generate(self, tokens: list[int], *, temp: float):
        assert tokens == [10, 11, 12]
        assert temp == 0.0
        yield 20
        yield 21
        yield 2
        yield 99


def _metadata() -> ModelMetadata:
    return ModelMetadata(
        model_name=MODEL_NAME,
        model_source="https://huggingface.co/Qwen/Qwen3-4B-GGUF",
        model_revision=MODEL_REVISION,
        model_file=MODEL_FILENAME,
        quantization=MODEL_QUANTIZATION,
        model_sha256="abc",
        llama_cpp_python_version="test-version",
    )


def test_runs_non_thinking_generation_with_exact_token_ids(monkeypatch) -> None:
    calls = {}

    class FakeFormatter:
        def __init__(self, **kwargs) -> None:
            calls["init"] = kwargs

        def __call__(self, **kwargs):
            calls["render"] = kwargs
            prompt = kwargs["messages"][0]["content"]
            return SimpleNamespace(
                prompt=(
                    f"<|im_start|>user\n{prompt}<|im_end|>\n"
                    "<|im_start|>assistant\n<think>\n\n</think>\n\n"
                )
            )

    package = ModuleType("llama_cpp")
    package.__path__ = []
    chat_module = ModuleType("llama_cpp.llama_chat_format")
    chat_module.Jinja2ChatFormatter = FakeFormatter
    monkeypatch.setitem(sys.modules, "llama_cpp", package)
    monkeypatch.setitem(sys.modules, "llama_cpp.llama_chat_format", chat_module)

    model = FakeModel()

    result = run_non_thinking_inference(
        model,
        _metadata(),
        prompt="Return OK.",
        seed=7,
        max_tokens=8,
        temperature=0.0,
    )

    assert model.seed == 7
    assert calls["render"]["enable_thinking"] is False
    assert "Return OK." in model.formatted_prompt
    assert "<think>\n\n</think>\n\n" in model.formatted_prompt
    assert result.response == "OK"
    assert result.input_token_ids == (10, 11, 12)
    assert result.output_token_ids == (20, 21)
    assert result.to_dict()["model"]["model_revision"] == MODEL_REVISION


def test_loads_model_with_cpu_only_settings(monkeypatch, tmp_path: Path) -> None:
    calls = {}

    class FakeLlama:
        def __init__(self, **kwargs) -> None:
            calls.update(kwargs)

    package = ModuleType("llama_cpp")
    package.Llama = FakeLlama
    monkeypatch.setitem(sys.modules, "llama_cpp", package)

    model = load_cpu_model(tmp_path / MODEL_FILENAME, seed=9, context_size=512)

    assert isinstance(model, FakeLlama)
    assert calls["n_gpu_layers"] == 0
    assert calls["n_ctx"] == 512
    assert calls["seed"] == 9


def test_hashes_and_identifies_a_verified_model(tmp_path: Path) -> None:
    model_path = tmp_path / MODEL_FILENAME
    model_path.write_bytes(b"test gguf")
    digest = sha256_file(model_path)

    metadata = read_model_metadata(
        model_path,
        expected_sha256=digest,
        llama_cpp_python_version="test-version",
    )

    assert metadata.model_name == MODEL_NAME
    assert metadata.model_revision == MODEL_REVISION
    assert metadata.quantization == MODEL_QUANTIZATION
    assert metadata.model_sha256 == digest
    assert metadata.llama_cpp_python_version == "test-version"


def test_rejects_missing_or_wrong_model(tmp_path: Path) -> None:
    model_path = tmp_path / MODEL_FILENAME
    with pytest.raises(FileNotFoundError, match="GGUF not found"):
        read_model_metadata(model_path)

    model_path.write_bytes(b"wrong")
    with pytest.raises(ValueError, match="GGUF SHA-256 mismatch"):
        read_model_metadata(model_path)
