"""Download and verify the fixed Qwen3-4B GGUF artifact."""

import argparse
import json
import os
from dataclasses import asdict
from pathlib import Path

from sw.experiment.qwen3_cpu import (
    MODEL_FILENAME,
    MODEL_NAME,
    MODEL_REVISION,
    read_model_metadata,
)

DEFAULT_MODEL_DIR = Path("models")


def main() -> int:
    """Download the fixed model revision and verify its SHA-256.

    Returns
    -------
    int
        Zero after successful download and verification.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--model-dir", type=Path, default=DEFAULT_MODEL_DIR)
    arguments = parser.parse_args()

    cache_dir = arguments.model_dir / ".cache" / "huggingface"
    os.environ.setdefault("HF_HOME", str(cache_dir.resolve()))
    os.environ.setdefault("HF_XET_CACHE", str((cache_dir / "xet").resolve()))
    from huggingface_hub import hf_hub_download

    downloaded = Path(
        hf_hub_download(
            repo_id=MODEL_NAME,
            filename=MODEL_FILENAME,
            revision=MODEL_REVISION,
            local_dir=arguments.model_dir,
        )
    )
    metadata = read_model_metadata(downloaded)
    print(json.dumps(asdict(metadata), ensure_ascii=False, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
