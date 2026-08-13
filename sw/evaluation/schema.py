"""Versioned JSONL boundary between Python, C++, RTL, and FPGA tests."""

import json
from collections.abc import Iterable
from dataclasses import asdict, dataclass, field
from pathlib import Path
from typing import Any, Self

from sw.common.bits import validate_bit_length

SCHEMA_VERSION = 0


def _validate_hex(name: str, value: str, bit_length: int) -> None:
    if value != value.lower() or value.startswith("0x") or len(value) % 2:
        raise ValueError(f"{name} must be lowercase, prefix-free, even-length hex")
    try:
        data = bytes.fromhex(value)
    except ValueError as error:
        raise ValueError(f"{name} is not valid hex") from error
    validate_bit_length(data, bit_length)


class JsonlRecord:
    """Provide dataclass conversion shared by JSONL record types."""

    def to_dict(self) -> dict[str, Any]:
        """Convert this dataclass record to a JSON-compatible dictionary.

        Returns
        -------
        dict[str, Any]
            Dataclass fields and their values.
        """
        return asdict(self)  # type: ignore[arg-type]

    @classmethod
    def from_dict(cls, value: dict[str, Any]) -> Self:
        """Construct a record from decoded JSON object fields.

        Parameters
        ----------
        value : dict[str, Any]
            Field names and decoded JSON values accepted by the record class.

        Returns
        -------
        Self
            Validated record instance.
        """
        return cls(**value)


@dataclass(frozen=True, slots=True)
class TestVector(JsonlRecord):
    """Define one versioned cross-implementation reference case.

    Attributes
    ----------
    case_id : str
        Identifier unique across all vector files.
    algorithm : str
        Reference operation selected by the case.
    input_hex : str
        Lowercase, prefix-free input bytes.
    input_bit_length : int
        Number of valid bits in ``input_hex``.
    encoded_hex : str
        Expected encoded bytes.
    encoded_bit_length : int
        Number of valid bits in ``encoded_hex`` and ``received_hex``.
    received_hex : str
        Encoded bytes after injected test errors.
    decoded_hex : str
        Expected decoded bytes.
    decoded_bit_length : int
        Number of valid bits in ``decoded_hex``.
    parameters : dict[str, int | str]
        Algorithm-specific scalar parameters.
    error_bit_positions : list[int]
        Zero-based LSB-first positions changed by the test case.
    expected_status : list[str]
        Ordered status names expected from the implementation.
    schema_version : int
        JSONL schema version used by this record.
    """

    case_id: str
    algorithm: str
    input_hex: str
    input_bit_length: int
    encoded_hex: str
    encoded_bit_length: int
    received_hex: str
    decoded_hex: str
    decoded_bit_length: int
    parameters: dict[str, int | str] = field(default_factory=dict)
    error_bit_positions: list[int] = field(default_factory=list)
    expected_status: list[str] = field(default_factory=list)
    schema_version: int = SCHEMA_VERSION

    def __post_init__(self) -> None:
        if self.schema_version != SCHEMA_VERSION:
            raise ValueError(f"unsupported vector schema: {self.schema_version}")
        if not self.case_id or not self.algorithm:
            raise ValueError("case_id and algorithm must be non-empty")
        _validate_hex("input_hex", self.input_hex, self.input_bit_length)
        _validate_hex("encoded_hex", self.encoded_hex, self.encoded_bit_length)
        _validate_hex("received_hex", self.received_hex, self.encoded_bit_length)
        _validate_hex("decoded_hex", self.decoded_hex, self.decoded_bit_length)
        if len(set(self.error_bit_positions)) != len(self.error_bit_positions):
            raise ValueError("error_bit_positions must be unique")
        if any(
            position < 0 or position >= self.encoded_bit_length
            for position in self.error_bit_positions
        ):
            raise ValueError("error bit position is outside encoded data")


@dataclass(frozen=True, slots=True)
class CaseResult(JsonlRecord):
    """Define one versioned implementation output for offline evaluation.

    Attributes
    ----------
    case_id : str
        Identifier copied from the evaluated reference case.
    implementation : str
        Name of the implementation that produced the output.
    output_hex : str
        Lowercase, prefix-free output bytes.
    output_bit_length : int
        Number of valid bits in ``output_hex``.
    status : list[str]
        Ordered status names reported by the implementation.
    schema_version : int
        JSONL schema version used by this record.
    """

    case_id: str
    implementation: str
    output_hex: str
    output_bit_length: int
    status: list[str] = field(default_factory=list)
    schema_version: int = SCHEMA_VERSION

    def __post_init__(self) -> None:
        if self.schema_version != SCHEMA_VERSION:
            raise ValueError(f"unsupported result schema: {self.schema_version}")
        if not self.case_id or not self.implementation:
            raise ValueError("case_id and implementation must be non-empty")
        _validate_hex("output_hex", self.output_hex, self.output_bit_length)


def write_jsonl(path: Path, records: Iterable[JsonlRecord]) -> None:
    """Write records as deterministic compact JSON Lines.

    Parameters
    ----------
    path : Path
        Destination file, whose parent directories are created if needed.
    records : Iterable[JsonlRecord]
        Ordered records to serialize.
    """
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(encode_jsonl(records))


def encode_jsonl(records: Iterable[JsonlRecord]) -> bytes:
    """Encode ordered records as compact newline-terminated JSON Lines.

    Parameters
    ----------
    records : Iterable[JsonlRecord]
        Ordered records to serialize.

    Returns
    -------
    bytes
        UTF-8 encoded JSONL content.
    """
    lines = [json.dumps(record.to_dict(), separators=(",", ":")) for record in records]
    return "".join(f"{line}\n" for line in lines).encode()


def read_jsonl[T: JsonlRecord](path: Path, record_type: type[T]) -> list[T]:
    """Read and validate typed records from a JSON Lines file.

    Parameters
    ----------
    path : Path
        Source JSONL file.
    record_type : type[T]
        Record class used to validate each decoded object.

    Returns
    -------
    list[T]
        Records in source order.

    Raises
    ------
    ValueError
        If a line is malformed or fails record validation.
    """
    records: list[T] = []
    for line_number, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        try:
            value = json.loads(line)
            if not isinstance(value, dict):
                raise TypeError("record must be a JSON object")
            records.append(record_type.from_dict(value))
        except (json.JSONDecodeError, TypeError, ValueError) as error:
            raise ValueError(f"{path}:{line_number}: {error}") from error
    return records
