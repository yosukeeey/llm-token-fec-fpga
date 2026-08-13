"""Generate language constants from the shared protocol specification."""

import argparse
import hashlib
import re
from pathlib import Path
from typing import Any

import yaml

SPEC_PATH = Path("spec/test_protocol_v0.yaml")
OUTPUT_PATHS = (
    Path("sw/common/protocol_constants.py"),
    Path("sw/cpp/include/reference/protocol_constants.hpp"),
    Path("rtl/interfaces/protocol_pkg.sv"),
)


def _constant_name(*parts: str) -> str:
    return "_".join(re.sub(r"[^A-Za-z0-9]+", "_", part).upper() for part in parts)


def _load_spec(path: Path) -> tuple[dict[str, Any], str]:
    source = path.read_bytes()
    value = yaml.safe_load(source)
    if not isinstance(value, dict):
        raise TypeError("protocol specification must be a mapping")
    return value, hashlib.sha256(source).hexdigest()


def _validate_fields(section: str, value: dict[str, Any], expected_size: int) -> None:
    fields = value.get("fields")
    if not isinstance(fields, list) or not fields:
        raise ValueError(f"{section}.fields must be a non-empty list")
    next_offset = 0
    for field in fields:
        if not isinstance(field, dict):
            raise TypeError(f"{section}.fields entries must be mappings")
        if field.get("offset") != next_offset:
            raise ValueError(f"{section}.{field.get('name')} is not contiguous")
        size = field.get("size")
        if not isinstance(size, int) or size <= 0:
            raise ValueError(f"{section}.{field.get('name')} has an invalid size")
        next_offset += size
    if next_offset != expected_size:
        raise ValueError(f"{section} size is {next_offset}, expected {expected_size}")


def _validate_spec(spec: dict[str, Any]) -> None:
    if spec.get("byte_order") != "little" or spec.get("bit_order") != "lsb_first":
        raise ValueError("only little-endian LSB-first storage is supported")
    _validate_fields(
        "frame",
        spec["frame"],
        len(spec["frame"]["sof"]) + spec["frame"]["header_size"],
    )
    for section, size_key in (
        ("token_record", "base_size"),
        ("protection_request", "size"),
        ("channel_state", "size"),
        ("result_status", "size"),
        ("error_response", "size"),
    ):
        value = spec[section]
        _validate_fields(section, value, value[size_key])


def _entries(spec: dict[str, Any], source_sha256: str) -> list[tuple[str, int | str]]:
    entries: list[tuple[str, int | str]] = [
        ("PROTOCOL_SCHEMA_VERSION", spec["schema_version"]),
        ("PROTOCOL_SPEC_SHA256", source_sha256),
        ("BYTE_ORDER", spec["byte_order"]),
        ("BIT_ORDER", spec["bit_order"]),
        ("SEQUENCE_BITS", spec["sequence"]["bits"]),
        ("SEQUENCE_INITIAL", spec["sequence"]["initial"]),
        ("SEQUENCE_MODULUS", spec["sequence"]["modulus"]),
        ("FRAME_VERSION", spec["frame"]["version"]),
        ("FRAME_MAX_PAYLOAD_BYTES", spec["frame"]["max_payload_bytes"]),
        ("FRAME_HEADER_SIZE", spec["frame"]["header_size"]),
        ("CRC32C_POLYNOMIAL", spec["crc32c"]["polynomial"]),
        ("CRC32C_REFLECTED_POLYNOMIAL", spec["crc32c"]["reflected_polynomial"]),
        ("CRC32C_INITIAL", spec["crc32c"]["initial"]),
        ("CRC32C_XOR_OUT", spec["crc32c"]["xor_out"]),
        ("TOKEN_RECORD_VERSION", spec["token_record"]["version"]),
        ("TOKEN_RECORD_BASE_SIZE", spec["token_record"]["base_size"]),
        ("EXTENSION_TLV_HEADER_SIZE", spec["extension_tlv"]["header_size"]),
        ("EXTENSION_TLV_MAX_VALUE_BYTES", spec["extension_tlv"]["max_value_bytes"]),
        ("PROTECTION_REQUEST_VERSION", spec["protection_request"]["version"]),
        ("PROTECTION_REQUEST_SIZE", spec["protection_request"]["size"]),
        ("CHANNEL_STATE_VERSION", spec["channel_state"]["version"]),
        ("CHANNEL_STATE_SIZE", spec["channel_state"]["size"]),
        ("RESULT_STATUS_SIZE", spec["result_status"]["size"]),
        ("ERROR_RESPONSE_SIZE", spec["error_response"]["size"]),
        ("STREAM_BYTE_DATA_BITS", spec["stream"]["byte_data_bits"]),
        ("STREAM_BIT_DATA_BITS", spec["stream"]["bit_data_bits"]),
    ]
    for section in (
        "message_types",
        "token_flags",
        "protection_modes",
        "channel_flags",
        "result_flags",
    ):
        prefix = section.removesuffix("s")
        entries.extend(
            (_constant_name(prefix, name), value)
            for name, value in spec[section].items()
        )
    for section in (
        "frame",
        "token_record",
        "protection_request",
        "channel_state",
        "result_status",
        "error_response",
    ):
        prefix = section
        for field in spec[section]["fields"]:
            entries.append(
                (_constant_name(prefix, field["name"], "offset"), field["offset"])
            )
            entries.append(
                (_constant_name(prefix, field["name"], "size"), field["size"])
            )
    return entries


def _python_output(
    entries: list[tuple[str, int | str]], sof: list[int]
) -> bytes:
    lines = ['"""Constants generated from the shared protocol specification."""', ""]
    for name, value in entries:
        lines.append(f"{name} = {value!r}")
    lines.append(f"FRAME_SOF = bytes({sof!r})")
    return ("\n".join(lines) + "\n").encode()


def _cpp_output(entries: list[tuple[str, int | str]], sof: list[int]) -> bytes:
    lines = [
        "#pragma once",
        "",
        "#include <array>",
        "#include <cstddef>",
        "#include <cstdint>",
        "#include <string_view>",
        "",
        "namespace reference::protocol_constants {",
        "",
    ]
    for name, value in entries:
        cpp_name = name.lower()
        if isinstance(value, str):
            lines.append(f'inline constexpr std::string_view {cpp_name}{{"{value}"}};')
        else:
            lines.append(f"inline constexpr std::uint64_t {cpp_name} = {value}ULL;")
    sof_values = ", ".join(f"0x{value:02X}U" for value in sof)
    lines.extend(
        [
            f"inline constexpr std::array<std::uint8_t, {len(sof)}> frame_sof{{{sof_values}}};",
            "",
            "}",
        ]
    )
    return ("\n".join(lines) + "\n").encode()


def _sv_output(entries: list[tuple[str, int | str]], sof: list[int]) -> bytes:
    lines = ["package protocol_pkg;"]
    for name, value in entries:
        if name == "PROTOCOL_SPEC_SHA256":
            lines.append(f"    localparam [255:0] {name} = 256'h{value};")
        elif isinstance(value, str):
            continue
        else:
            lines.append(f"    localparam [63:0] {name} = 64'd{value};")
    for index, value in enumerate(sof):
        lines.append(f"    localparam [7:0] FRAME_SOF_{index} = 8'h{value:02x};")
    lines.append("endpackage")
    return ("\n".join(lines) + "\n").encode()


def generated_outputs(spec_path: Path = SPEC_PATH) -> dict[Path, bytes]:
    """Build every generated protocol constants file in memory.

    Parameters
    ----------
    spec_path : Path
        Source YAML specification.

    Returns
    -------
    dict[Path, bytes]
        Generated content keyed by repository-relative output path.
    """
    spec, source_sha256 = _load_spec(spec_path)
    _validate_spec(spec)
    entries = _entries(spec, source_sha256)
    sof = spec["frame"]["sof"]
    return {
        OUTPUT_PATHS[0]: _python_output(entries, sof),
        OUTPUT_PATHS[1]: _cpp_output(entries, sof),
        OUTPUT_PATHS[2]: _sv_output(entries, sof),
    }


def main() -> int:
    """Write generated constants or verify tracked outputs.

    Returns
    -------
    int
        Zero on success, otherwise one when ``--check`` finds a difference.
    """
    parser = argparse.ArgumentParser()
    parser.add_argument("--check", action="store_true")
    arguments = parser.parse_args()
    outputs = generated_outputs()

    if arguments.check:
        mismatches = [
            str(path)
            for path, content in outputs.items()
            if not path.exists() or path.read_bytes() != content
        ]
        if mismatches:
            print("Generated protocol constants differ: " + ", ".join(mismatches))
            return 1
        print("Generated protocol constants are current")
        return 0

    for path, content in outputs.items():
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)
    print("Generated protocol constants")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
