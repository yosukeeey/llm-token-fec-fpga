import subprocess
from pathlib import Path

import yaml

from scripts.generate_protocol_constants import generated_outputs
from sw.common import protocol_constants as constants


def test_generated_constants_are_current() -> None:
    for path, content in generated_outputs().items():
        assert path.read_bytes() == content


def test_fixed_sizes_and_offsets_match_specification() -> None:
    specification = yaml.safe_load(
        Path("spec/test_protocol_v0.yaml").read_text(encoding="utf-8")
    )
    assert constants.TOKEN_RECORD_BASE_SIZE == 40
    assert constants.PROTECTION_REQUEST_SIZE == 16
    assert constants.CHANNEL_STATE_SIZE == 4
    assert constants.RESULT_STATUS_SIZE == 8
    assert specification["token_record"]["fields"][-1]["offset"] == 38
    assert constants.PROTOCOL_SPEC_SHA256 in Path(
        "rtl/interfaces/protocol_pkg.sv"
    ).read_text(encoding="ascii")


def test_generated_systemverilog_package_compiles() -> None:
    tool_root = Path("build/tools/iverilog")
    executable = tool_root / "bin/iverilog.exe"
    if not executable.exists():
        return
    top = Path("build/test/protocol_constants_tb.sv")
    top.parent.mkdir(parents=True, exist_ok=True)
    top.write_text(
        "module protocol_constants_tb;\n"
        "  import protocol_pkg::*;\n"
        "  initial begin\n"
        "    if (TOKEN_RECORD_BASE_SIZE != 40) $fatal(1);\n"
        "  end\n"
        "endmodule\n",
        encoding="ascii",
    )
    subprocess.run(
        [
            executable,
            "-B",
            tool_root / "lib/ivl",
            "-g2012",
            "-s",
            "protocol_constants_tb",
            "-o",
            "build/test/protocol_constants.vvp",
            "rtl/interfaces/protocol_pkg.sv",
            top,
        ],
        check=True,
    )
