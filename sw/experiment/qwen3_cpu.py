"""Qwen3 GGUF identification and CPU inference."""

from dataclasses import asdict, dataclass
from hashlib import sha256
from importlib.metadata import version
from pathlib import Path
from typing import Any

MODEL_NAME = "Qwen/Qwen3-4B-GGUF"
MODEL_REVISION = "bc640142c66e1fdd12af0bd68f40445458f3869b"
MODEL_FILENAME = "Qwen3-4B-Q4_K_M.gguf"
MODEL_QUANTIZATION = "Q4_K_M"
MODEL_SHA256 = "7485fe6f11af29433bc51cab58009521f205840f5b4ae3a32fa7f92e8534fdf5"


@dataclass(frozen=True)
class ModelMetadata:
    """Reproducible model identity.

    Attributes
    ----------
    model_name : str
        Hugging Face model repository identifier.
    model_source : str
        Model distribution source.
    model_revision : str
        Immutable source revision.
    model_file : str
        GGUF filename.
    quantization : str
        GGUF quantization identifier.
    model_sha256 : str
        SHA-256 of the local GGUF file.
    llama_cpp_python_version : str
        Installed llama-cpp-python version.
    """

    model_name: str
    model_source: str
    model_revision: str
    model_file: str
    quantization: str
    model_sha256: str
    llama_cpp_python_version: str


@dataclass(frozen=True)
class InferenceResult:
    """One CPU inference result with exact token IDs.

    Attributes
    ----------
    prompt : str
        Original user prompt.
    response : str
        Generated response text.
    input_token_ids : tuple[int, ...]
        Token IDs for the rendered non-thinking chat prompt.
    output_token_ids : tuple[int, ...]
        Generated token IDs before the end-of-sequence token.
    model : ModelMetadata
        Reproducible model identity.
    """

    prompt: str
    response: str
    input_token_ids: tuple[int, ...]
    output_token_ids: tuple[int, ...]
    model: ModelMetadata

    def to_dict(self) -> dict[str, Any]:
        """Convert the result to a JSON-compatible mapping.

        Returns
        -------
        dict[str, Any]
            Result and model metadata.
        """
        return asdict(self)


def sha256_file(path: str | Path) -> str:
    """Calculate a file SHA-256 digest.

    Parameters
    ----------
    path : str or pathlib.Path
        File to hash.

    Returns
    -------
    str
        Lowercase hexadecimal SHA-256 digest.
    """
    digest = sha256()
    with Path(path).open("rb") as model_file:
        for block in iter(lambda: model_file.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def read_model_metadata(
    path: str | Path,
    *,
    expected_sha256: str = MODEL_SHA256,
    llama_cpp_python_version: str | None = None,
) -> ModelMetadata:
    """Verify a local GGUF and return its fixed identity.

    Parameters
    ----------
    path : str or pathlib.Path
        Local GGUF path.
    expected_sha256 : str
        Required GGUF SHA-256 digest.
    llama_cpp_python_version : str or None
        Installed package version override for isolated tests.

    Returns
    -------
    ModelMetadata
        Verified model identity.

    Raises
    ------
    FileNotFoundError
        If the GGUF is not present.
    ValueError
        If the GGUF digest does not match the fixed artifact.
    """
    model_path = Path(path)
    if not model_path.is_file():
        raise FileNotFoundError(
            f"GGUF not found: {model_path}. Run the model download command first."
        )
    actual_sha256 = sha256_file(model_path)
    if actual_sha256 != expected_sha256:
        raise ValueError(
            f"GGUF SHA-256 mismatch: expected {expected_sha256}, got {actual_sha256}"
        )
    return ModelMetadata(
        model_name=MODEL_NAME,
        model_source="https://huggingface.co/Qwen/Qwen3-4B-GGUF",
        model_revision=MODEL_REVISION,
        model_file=MODEL_FILENAME,
        quantization=MODEL_QUANTIZATION,
        model_sha256=actual_sha256,
        llama_cpp_python_version=(
            llama_cpp_python_version or version("llama-cpp-python")
        ),
    )


def load_cpu_model(path: str | Path, *, seed: int, context_size: int = 4096) -> Any:
    """Load a GGUF with CPU-only llama.cpp settings.

    Parameters
    ----------
    path : str or pathlib.Path
        Local GGUF path.
    seed : int
        Sampling seed.
    context_size : int
        llama.cpp context size.

    Returns
    -------
    Any
        Loaded ``llama_cpp.Llama`` model.
    """
    from llama_cpp import Llama

    return Llama(
        model_path=str(path),
        n_gpu_layers=0,
        n_ctx=context_size,
        seed=seed,
        verbose=False,
    )


def run_non_thinking_inference(
    model: Any,
    metadata: ModelMetadata,
    *,
    prompt: str,
    seed: int,
    max_tokens: int,
    temperature: float,
) -> InferenceResult:
    """Run one Qwen3 non-thinking generation and preserve exact token IDs.

    Parameters
    ----------
    model : Any
        Loaded ``llama_cpp.Llama`` model.
    metadata : ModelMetadata
        Verified model identity.
    prompt : str
        User prompt.
    seed : int
        Sampling seed.
    max_tokens : int
        Maximum generated token count.
    temperature : float
        Sampling temperature.

    Returns
    -------
    InferenceResult
        Response, exact token IDs, and model identity.

    Raises
    ------
    ValueError
        If inputs or required GGUF chat metadata are invalid.
    """
    from llama_cpp.llama_chat_format import Jinja2ChatFormatter

    if not prompt:
        raise ValueError("prompt must not be empty")
    if max_tokens <= 0:
        raise ValueError("max_tokens must be positive")
    if temperature < 0.0:
        raise ValueError("temperature must be non-negative")

    template = model.metadata.get("tokenizer.chat_template")
    if not isinstance(template, str) or not template:
        raise ValueError("GGUF tokenizer.chat_template metadata is required")

    eos_id = model.token_eos()
    bos_id = model.token_bos()
    eos_text = (
        model.detokenize([eos_id], special=True).decode("utf-8") if eos_id != -1 else ""
    )
    bos_text = (
        model.detokenize([bos_id], special=True).decode("utf-8") if bos_id != -1 else ""
    )
    formatter = Jinja2ChatFormatter(
        template=template,
        eos_token=eos_text,
        bos_token=bos_text,
        stop_token_ids=[eos_id] if eos_id != -1 else None,
    )
    formatted = formatter(
        messages=[{"role": "user", "content": prompt}],
        enable_thinking=False,
    )
    input_ids = model.tokenize(
        formatted.prompt.encode("utf-8"), add_bos=False, special=True
    )

    model.set_seed(seed)
    output_ids: list[int] = []
    for token_id in model.generate(input_ids, temp=temperature):
        if token_id == eos_id:
            break
        output_ids.append(token_id)
        if len(output_ids) >= max_tokens:
            break

    response = model.detokenize(output_ids, prev_tokens=input_ids).decode("utf-8")
    return InferenceResult(
        prompt=prompt,
        response=response,
        input_token_ids=tuple(input_ids),
        output_token_ids=tuple(output_ids),
        model=metadata,
    )
