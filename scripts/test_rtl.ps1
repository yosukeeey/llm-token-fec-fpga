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
$simRoot = Join-Path $repositoryRoot "build\rtl\sim"
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

function Invoke-RtlCase {
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

    $vectorPath = Convert-ToSimulatorPath (Join-Path $rtlVectorRoot "$Name.txt")
    $resultPath = Join-Path $resultRoot "$Name.jsonl"
    New-Item -ItemType File -Path $resultPath -Force | Out-Null
    $simulatorResultPath = Convert-ToSimulatorPath $resultPath
    $simulationOutput = @(
        & $vvp -M $libraryRoot $simulation `
            "+VECTOR_FILE=$vectorPath" `
            "+RESULT_FILE=$simulatorResultPath" 2>&1
    )
    $simulationOutput | Write-Host
    Assert-NativeSuccess "$Name RTL simulation"

    # This Windows VVP build can return zero after $fatal, so require the
    # explicit terminal success record in addition to its process exit code.
    $successLine = "$Name`: $ExpectedCases cases passed"
    if ($simulationOutput -notcontains $successLine) {
        throw "$Name RTL simulation did not report success"
    }

    uv run python -m scripts.evaluate_reference_results `
        --vectors (Join-Path $referenceVectorRoot "$Name.jsonl") `
        --results $resultPath
    Assert-NativeSuccess "$Name RTL result evaluation"
}

if (-not (Test-Path -LiteralPath $iverilog) -or -not (Test-Path -LiteralPath $vvp)) {
    throw "Run scripts/bootstrap.ps1 to install the pinned RTL simulator"
}

New-Item -ItemType Directory -Path $simRoot, $rtlVectorRoot, $resultRoot -Force |
    Out-Null

Push-Location $repositoryRoot
try {
    uv run python -m scripts.generate_rtl_vectors `
        --vectors $referenceVectorRoot `
        --output-dir $rtlVectorRoot
    Assert-NativeSuccess "RTL vector generation"

    Invoke-RtlCase `
        -Name "parity" `
        -Top "parity_tb" `
        -ExpectedCases 3 `
        -Sources @(
            "rtl/fec/parity_gen.sv",
            "rtl/fec/parity_check.sv",
            "rtl/tb/parity_tb.sv"
        )
    Invoke-RtlCase `
        -Name "repetition" `
        -Top "repetition_tb" `
        -ExpectedCases 5 `
        -Sources @(
            "rtl/fec/repetition_encoder.sv",
            "rtl/fec/majority_decoder.sv",
            "rtl/tb/repetition_tb.sv"
        )
    Invoke-RtlCase `
        -Name "hamming74" `
        -Top "hamming74_tb" `
        -ExpectedCases 128 `
        -Sources @(
            "rtl/fec/hamming74_encoder.sv",
            "rtl/fec/hamming74_decoder.sv",
            "rtl/tb/hamming74_tb.sv"
        )
}
finally {
    Pop-Location
}
