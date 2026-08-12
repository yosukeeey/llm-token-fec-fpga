[CmdletBinding()]
param(
    [switch]$RequireIcarus,
    [switch]$RequireVivado,
    [switch]$RequireSerialPort
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$env:UV_CACHE_DIR = Join-Path $repositoryRoot "build\cache\uv"
$vcpkgCacheRoot = Join-Path $repositoryRoot "build\cache\vcpkg"
$env:VCPKG_DOWNLOADS = Join-Path $vcpkgCacheRoot "downloads"
$env:VCPKG_DEFAULT_BINARY_CACHE = Join-Path $vcpkgCacheRoot "binary"
$env:X_VCPKG_REGISTRIES_CACHE = Join-Path $vcpkgCacheRoot "registries"
$failures = [System.Collections.Generic.List[string]]::new()

function Write-Check {
    param(
        [string]$Name,
        [bool]$Passed,
        [string]$Detail,
        [bool]$Required = $true
    )

    if ($Passed) {
        Write-Host "PASS  $Name - $Detail" -ForegroundColor Green
        return
    }

    if ($Required) {
        Write-Host "FAIL  $Name - $Detail" -ForegroundColor Red
        $script:failures.Add($Name)
    }
    else {
        Write-Host "WARN  $Name - $Detail" -ForegroundColor Yellow
    }
}

function Find-VcpkgRoot {
    $localRoot = Join-Path $repositoryRoot "build\tools\vcpkg"
    if (Test-Path -LiteralPath (Join-Path $localRoot "vcpkg.exe")) {
        return $localRoot
    }

    if ($env:VCPKG_ROOT) {
        $candidate = $env:VCPKG_ROOT
        if (Test-Path -LiteralPath (Join-Path $candidate "vcpkg.exe")) {
            return $candidate
        }
    }

    $vcpkgCommand = Get-Command vcpkg -ErrorAction SilentlyContinue
    if ($vcpkgCommand) {
        return Split-Path -Parent $vcpkgCommand.Source
    }

    $visualStudioRoot = Join-Path $env:ProgramFiles "Microsoft Visual Studio\2022"
    $candidate = Get-ChildItem -LiteralPath $visualStudioRoot -Directory -ErrorAction SilentlyContinue |
        ForEach-Object { Join-Path $_.FullName "VC\vcpkg" } |
        Where-Object { Test-Path -LiteralPath (Join-Path $_ "vcpkg.exe") } |
        Select-Object -First 1
    return $candidate
}

Push-Location $repositoryRoot
try {
    $uv = Get-Command uv -ErrorAction SilentlyContinue
    Write-Check "uv" ($null -ne $uv) $(if ($uv) { (& uv --version) } else { "not found" })

    if ($uv) {
        $pythonVersion = (& uv run python --version 2>&1 | Out-String).Trim()
        Write-Check "Python" ($LASTEXITCODE -eq 0 -and $pythonVersion -match "Python 3\.12") $pythonVersion
    }

    $cmake = Get-Command cmake -ErrorAction SilentlyContinue
    $cmakeVersion = if ($cmake) { (& cmake --version | Select-Object -First 1) } else { "not found" }
    Write-Check "CMake" ($null -ne $cmake) $cmakeVersion

    $ctest = Get-Command ctest -ErrorAction SilentlyContinue
    Write-Check "CTest" ($null -ne $ctest) $(if ($ctest) { $ctest.Source } else { "not found" })

    $vswhere = Join-Path ${env:ProgramFiles(x86)} "Microsoft Visual Studio\Installer\vswhere.exe"
    $vsPath = if (Test-Path -LiteralPath $vswhere) {
        & $vswhere -latest -products * -requires Microsoft.VisualStudio.Component.VC.Tools.x86.x64 -property installationPath
    }
    Write-Check "MSVC x64" (-not [string]::IsNullOrWhiteSpace($vsPath)) $(if ($vsPath) { $vsPath } else { "Visual Studio C++ tools not found" })

    $windowsSdkRoot = Join-Path ${env:ProgramFiles(x86)} "Windows Kits\10\Include"
    $windowsSdk = Get-ChildItem -LiteralPath $windowsSdkRoot -Directory -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending |
        Select-Object -First 1
    Write-Check "Windows SDK" ($null -ne $windowsSdk) $(if ($windowsSdk) { $windowsSdk.Name } else { "not found" })

    $vcpkgRoot = Find-VcpkgRoot
    $vcpkgExe = if ($vcpkgRoot) { Join-Path $vcpkgRoot "vcpkg.exe" }
    $vcpkgVersion = if ($vcpkgExe -and (Test-Path -LiteralPath $vcpkgExe)) {
        (& $vcpkgExe version | Select-Object -First 1)
    } else {
        "not found"
    }
    Write-Check "vcpkg" ($null -ne $vcpkgExe -and (Test-Path -LiteralPath $vcpkgExe)) $vcpkgVersion

    $localIcarus = Join-Path $repositoryRoot "build\tools\iverilog\bin\iverilog.exe"
    $iverilogCommand = if (Test-Path -LiteralPath $localIcarus) {
        Get-Item -LiteralPath $localIcarus
    } else {
        Get-Command iverilog -ErrorAction SilentlyContinue
    }
    $iverilogVersion = if ($iverilogCommand) {
        (& $iverilogCommand.FullName -V 2>&1 | Select-Object -First 1)
    } else {
        "not found"
    }
    Write-Check "Icarus Verilog" ($null -ne $iverilogCommand) $iverilogVersion $RequireIcarus

    $vivado = Get-Command vivado -ErrorAction SilentlyContinue
    Write-Check "Vivado" ($null -ne $vivado) $(if ($vivado) { $vivado.Source } else { "not found on PATH" }) $RequireVivado

    $serialPorts = @(Get-CimInstance Win32_SerialPort -ErrorAction SilentlyContinue)
    $serialDetail = if ($serialPorts.Count -gt 0) {
        ($serialPorts | ForEach-Object { "$($_.DeviceID): $($_.Name)" }) -join "; "
    } else {
        "no serial ports detected"
    }
    Write-Check "Serial port" ($serialPorts.Count -gt 0) $serialDetail $RequireSerialPort
}
finally {
    Pop-Location
}

if ($failures.Count -gt 0) {
    throw "Required environment checks failed: $($failures -join ', ')"
}
