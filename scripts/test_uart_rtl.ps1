[CmdletBinding()]
param(
    [string]$VectorDirectory = "datasets/test_vectors/protocol_v0",
    [string]$ResultDirectory = "build/results/rtl"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$toolRoot = Join-Path $repositoryRoot "build\tools\iverilog"
$iverilog = Join-Path $toolRoot "bin\iverilog.exe"
$vvp = Join-Path $toolRoot "bin\vvp.exe"
$libraryRoot = Join-Path $toolRoot "lib\ivl"
$simulationRoot = Join-Path $repositoryRoot "build\rtl\sim"
$rtlVectorRoot = Join-Path $repositoryRoot "build\rtl\vectors"
$referenceVectorRoot = Join-Path $repositoryRoot $VectorDirectory
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

function Invoke-UartCase {
    param(
        [string]$Name,
        [string]$Top,
        [string[]]$Sources,
        [int]$ExpectedCases,
        [string]$VectorFile = ""
    )

    $simulation = Join-Path $simulationRoot "$Name.vvp"
    & $iverilog -B $libraryRoot -g2012 -Wall -s $Top -o $simulation @Sources
    Assert-NativeSuccess "$Name RTL compile"

    $resultPath = Join-Path $resultRoot "$Name.jsonl"
    New-Item -ItemType File -Path $resultPath -Force | Out-Null
    $arguments = @(
        "+RESULT_FILE=$(Convert-ToSimulatorPath $resultPath)"
    )
    if ($VectorFile) {
        $arguments += "+VECTOR_FILE=$(Convert-ToSimulatorPath (Join-Path $rtlVectorRoot $VectorFile))"
    }
    $simulationOutput = @(& $vvp -M $libraryRoot $simulation @arguments 2>&1)
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

New-Item -ItemType Directory -Path $simulationRoot, $rtlVectorRoot, $resultRoot -Force |
    Out-Null

Push-Location $repositoryRoot
try {
    uv run python -m scripts.generate_rtl_vectors `
        --vectors $referenceVectorRoot `
        --output-dir $rtlVectorRoot
    Assert-NativeSuccess "RTL vector generation"

    Invoke-UartCase `
        -Name "uart_tx" `
        -Top "uart_tx_tb" `
        -ExpectedCases 7 `
        -Sources @(
            "rtl/common/uart_tx.sv",
            "rtl/tb/uart_tx_tb.sv"
        )
    Invoke-UartCase `
        -Name "uart_rx" `
        -Top "uart_rx_tb" `
        -ExpectedCases 8 `
        -Sources @(
            "rtl/interfaces/stream_assertions.sv",
            "rtl/common/uart_rx.sv",
            "rtl/tb/uart_rx_tb.sv"
        )
    Invoke-UartCase `
        -Name "uart_frame_pipeline" `
        -Top "uart_frame_pipeline_tb" `
        -ExpectedCases 5 `
        -VectorFile "protocol_pipeline.txt" `
        -Sources @(
            "rtl/interfaces/protocol_pkg.sv",
            "rtl/common/stream_fifo.sv",
            "rtl/fec/repetition_encoder.sv",
            "rtl/fec/majority_decoder.sv",
            "rtl/fec/hamming74_encoder.sv",
            "rtl/fec/hamming74_decoder.sv",
            "rtl/common/crc32c_stream.sv",
            "rtl/common/frame_rx.sv",
            "rtl/common/frame_tx.sv",
            "rtl/common/token_request_handler.sv",
            "rtl/top/frame_pipeline.sv",
            "rtl/common/uart_rx.sv",
            "rtl/common/uart_tx.sv",
            "rtl/top/uart_frame_pipeline.sv",
            "rtl/tb/uart_frame_pipeline_tb.sv"
        )
}
finally {
    Pop-Location
}
