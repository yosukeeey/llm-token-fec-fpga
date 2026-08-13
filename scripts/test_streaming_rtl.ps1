[CmdletBinding()]
param(
    [string]$ResultDirectory = "build/results/rtl"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $repositoryRoot "build\tools\iverilog"
$iverilog = Join-Path $toolRoot "bin\iverilog.exe"
$vvp = Join-Path $toolRoot "bin\vvp.exe"
$libraryRoot = Join-Path $toolRoot "lib\ivl"
$simRoot = Join-Path $repositoryRoot "build\rtl\sim"
$resultRoot = Join-Path $repositoryRoot $ResultDirectory
$env:UV_CACHE_DIR = Join-Path $repositoryRoot "build\cache\uv"

function Assert-NativeSuccess {
    param([string]$CommandName)

    if ($LASTEXITCODE -ne 0) {
        throw "$CommandName failed with exit code $LASTEXITCODE"
    }
}

function Convert-ToSimulatorPath {
    param([string]$Path)

    return (Resolve-Path -LiteralPath $Path).Path.Replace("\", "/")
}

function Invoke-StreamingCase {
    param(
        [string]$Name,
        [string]$Top,
        [string[]]$Sources,
        [int]$ExpectedCases
    )

    $simulation = Join-Path $simRoot "$Name.vvp"
    $compileArguments = @(
        "-B", $libraryRoot,
        "-g2012",
        "-Wall",
        "-s", $Top,
        "-o", $simulation
    ) + $Sources
    & $iverilog @compileArguments
    Assert-NativeSuccess "$Name RTL compile"

    $resultPath = Join-Path $resultRoot "$Name.jsonl"
    New-Item -ItemType File -Path $resultPath -Force | Out-Null
    $simulatorResultPath = Convert-ToSimulatorPath $resultPath
    $simulationOutput = @(
        & $vvp -M $libraryRoot $simulation "+RESULT_FILE=$simulatorResultPath" 2>&1
    )
    $simulationOutput | Write-Host
    Assert-NativeSuccess "$Name RTL simulation"

    # This Windows VVP build can return zero after $fatal, so require success output.
    if ($simulationOutput -notcontains "$Name`: $ExpectedCases cases passed") {
        throw "$Name RTL simulation did not report success"
    }

    uv run python -m scripts.evaluate_streaming_results `
        --results $resultPath `
        --expected-cases $ExpectedCases
    Assert-NativeSuccess "$Name RTL result evaluation"
}

if (-not (Test-Path -LiteralPath $iverilog) -or -not (Test-Path -LiteralPath $vvp)) {
    throw "Run scripts/bootstrap.ps1 to install the pinned RTL simulator"
}

New-Item -ItemType Directory -Path $simRoot, $resultRoot -Force | Out-Null

Push-Location $repositoryRoot
try {
    Invoke-StreamingCase `
        -Name "crc32c_stream" `
        -Top "crc32c_stream_tb" `
        -ExpectedCases 5 `
        -Sources @(
            "rtl/interfaces/protocol_pkg.sv",
            "rtl/interfaces/stream_assertions.sv",
            "rtl/common/crc32c_stream.sv",
            "rtl/tb/crc32c_stream_tb.sv"
        )
    Invoke-StreamingCase `
        -Name "stream_fifo" `
        -Top "stream_fifo_tb" `
        -ExpectedCases 5 `
        -Sources @(
            "rtl/interfaces/stream_assertions.sv",
            "rtl/common/stream_fifo.sv",
            "rtl/tb/stream_fifo_tb.sv"
        )
    Invoke-StreamingCase `
        -Name "fec_stream" `
        -Top "fec_stream_tb" `
        -ExpectedCases 4 `
        -Sources @(
            "rtl/interfaces/stream_assertions.sv",
            "rtl/fec/repetition_encoder.sv",
            "rtl/fec/majority_decoder.sv",
            "rtl/fec/hamming74_encoder.sv",
            "rtl/fec/hamming74_decoder.sv",
            "rtl/fec/repetition_stream.sv",
            "rtl/fec/hamming74_stream.sv",
            "rtl/tb/fec_stream_tb.sv"
        )
}
finally {
    Pop-Location
}
