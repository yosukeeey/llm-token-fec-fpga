[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$uvCacheDir = Join-Path $repositoryRoot "build\cache\uv"
$vcpkgCacheRoot = Join-Path $repositoryRoot "build\cache\vcpkg"
$vcpkgRoot = Join-Path $repositoryRoot "build\tools\vcpkg"
$vcpkgCommit = "aae277acf4e7de287ddb5e208b5316614de6aad7"
$jsonHeader = Join-Path $repositoryRoot "build\tools\nlohmann-json\include\nlohmann\json.hpp"
$jsonVersion = "v3.12.0"
$jsonSha256 = "aaf127c04cb31c406e5b04a63f1ae89369fccde6d8fa7cdda1ed4f32dfc5de63"
$iverilogRoot = Join-Path $repositoryRoot "build\tools\iverilog"
$iverilogArchive = Join-Path $repositoryRoot "build\cache\iverilog\toolchain-iverilog-windows_amd64-1.1.1.tar.gz"
$iverilogReleaseTag = "v1.1.1"
$iverilogAsset = "toolchain-iverilog-windows_amd64-1.1.1.tar.gz"
$iverilogSha256 = "4698ebfdbb17f22c0db0d0977c2c4b8990e4d529b580cd67949d8823c9bdf28c"
$iverilogExeSha256 = "60668908af4c19f47b3c0c535d2d6572677e26b7ddc2f0a3d7c4b473cf7bbdfe"
$vvpExeSha256 = "ecc8917327d97471485e1631dbf9ff4e3fe25af12243c22646a0952a6a427ceb"
$env:UV_CACHE_DIR = $uvCacheDir
$env:VCPKG_ROOT = $vcpkgRoot
$env:VCPKG_DOWNLOADS = Join-Path $vcpkgCacheRoot "downloads"
$env:VCPKG_DEFAULT_BINARY_CACHE = Join-Path $vcpkgCacheRoot "binary"
$env:X_VCPKG_REGISTRIES_CACHE = Join-Path $vcpkgCacheRoot "registries"

@(
    $uvCacheDir,
    $env:VCPKG_DOWNLOADS,
    $env:VCPKG_DEFAULT_BINARY_CACHE,
    $env:X_VCPKG_REGISTRIES_CACHE
) | ForEach-Object {
    New-Item -ItemType Directory -Path $_ -Force | Out-Null
}

function Assert-NativeSuccess {
    param([string]$CommandName)

    if ($LASTEXITCODE -ne 0) {
        throw "$CommandName failed with exit code $LASTEXITCODE"
    }
}

function Initialize-Vcpkg {
    $vcpkgExe = Join-Path $vcpkgRoot "vcpkg.exe"
    $vcpkgGit = Join-Path $vcpkgRoot ".git"

    if (-not (Test-Path -LiteralPath $vcpkgGit)) {
        New-Item -ItemType Directory -Path $vcpkgRoot -Force | Out-Null
        git -C $vcpkgRoot init
        Assert-NativeSuccess "vcpkg git init"
        git -C $vcpkgRoot remote add origin https://github.com/microsoft/vcpkg.git
        Assert-NativeSuccess "vcpkg git remote add"
    }

    $currentCommit = git -C $vcpkgRoot rev-parse HEAD 2>$null
    if ($LASTEXITCODE -ne 0 -or $currentCommit -ne $vcpkgCommit) {
        git -C $vcpkgRoot fetch --depth 1 origin $vcpkgCommit
        Assert-NativeSuccess "vcpkg git fetch"
        git -C $vcpkgRoot checkout --detach $vcpkgCommit
        Assert-NativeSuccess "vcpkg git checkout"
    }

    if (-not (Test-Path -LiteralPath $vcpkgExe)) {
        $metadataPath = Join-Path $vcpkgRoot "scripts\vcpkg-tool-metadata.txt"
        $metadata = ConvertFrom-StringData (Get-Content -LiteralPath $metadataPath -Raw)
        $gh = Get-Command gh -ErrorAction SilentlyContinue

        if ($gh) {
            gh release download $metadata.VCPKG_TOOL_RELEASE_TAG `
                --repo microsoft/vcpkg-tool `
                --pattern vcpkg.exe `
                --output $vcpkgExe
            Assert-NativeSuccess "vcpkg tool download"
        }
        else {
            & (Join-Path $vcpkgRoot "bootstrap-vcpkg.bat") -disableMetrics
            Assert-NativeSuccess "vcpkg bootstrap"
        }
    }

    & $vcpkgExe version --disable-metrics | Select-Object -First 1
    Assert-NativeSuccess "vcpkg version"
}

function Initialize-JsonHeader {
    if (Test-Path -LiteralPath $jsonHeader) {
        $currentHash = (Get-FileHash -LiteralPath $jsonHeader -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($currentHash -eq $jsonSha256) {
            Write-Host "nlohmann/json $jsonVersion"
            return
        }
    }

    $headerDirectory = Split-Path -Parent $jsonHeader
    $downloadPath = "$jsonHeader.download"
    New-Item -ItemType Directory -Path $headerDirectory -Force | Out-Null
    if (Test-Path -LiteralPath $downloadPath) {
        Remove-Item -LiteralPath $downloadPath -Force
    }

    $gh = Get-Command gh -ErrorAction SilentlyContinue
    if ($gh) {
        gh release download $jsonVersion `
            --repo nlohmann/json `
            --pattern json.hpp `
            --output $downloadPath
        Assert-NativeSuccess "nlohmann/json download"
    }
    else {
        $uri = "https://github.com/nlohmann/json/releases/download/$jsonVersion/json.hpp"
        Invoke-WebRequest -Uri $uri -OutFile $downloadPath
    }

    $downloadHash = (Get-FileHash -LiteralPath $downloadPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($downloadHash -ne $jsonSha256) {
        Remove-Item -LiteralPath $downloadPath -Force
        throw "nlohmann/json SHA-256 mismatch"
    }
    Move-Item -LiteralPath $downloadPath -Destination $jsonHeader -Force
    Write-Host "nlohmann/json $jsonVersion"
}

function Initialize-IcarusVerilog {
    $iverilogExe = Join-Path $iverilogRoot "bin\iverilog.exe"
    $vvpExe = Join-Path $iverilogRoot "bin\vvp.exe"
    if ((Test-Path -LiteralPath $iverilogExe) -and (Test-Path -LiteralPath $vvpExe)) {
        $currentIverilogHash = (Get-FileHash -LiteralPath $iverilogExe -Algorithm SHA256).Hash.ToLowerInvariant()
        $currentVvpHash = (Get-FileHash -LiteralPath $vvpExe -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($currentIverilogHash -ne $iverilogExeSha256 -or $currentVvpHash -ne $vvpExeSha256) {
            throw "Installed RTL simulator SHA-256 mismatch"
        }
        & $iverilogExe -V 2>&1 | Select-Object -First 1
        Assert-NativeSuccess "Icarus Verilog version"
        return
    }

    $archiveDirectory = Split-Path -Parent $iverilogArchive
    New-Item -ItemType Directory -Path $archiveDirectory -Force | Out-Null
    if (-not (Test-Path -LiteralPath $iverilogArchive)) {
        $gh = Get-Command gh -ErrorAction SilentlyContinue
        if ($gh) {
            gh release download $iverilogReleaseTag `
                --repo FPGAwars/toolchain-iverilog `
                --pattern $iverilogAsset `
                --output $iverilogArchive
            Assert-NativeSuccess "Icarus Verilog download"
        }
        else {
            $uri = "https://github.com/FPGAwars/toolchain-iverilog/releases/download/$iverilogReleaseTag/$iverilogAsset"
            Invoke-WebRequest -Uri $uri -OutFile $iverilogArchive
        }
    }

    $archiveHash = (Get-FileHash -LiteralPath $iverilogArchive -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($archiveHash -ne $iverilogSha256) {
        throw "Icarus Verilog SHA-256 mismatch"
    }

    New-Item -ItemType Directory -Path $iverilogRoot -Force | Out-Null
    tar -xzf $iverilogArchive -C $iverilogRoot
    Assert-NativeSuccess "Icarus Verilog extraction"
    $installedIverilogHash = (Get-FileHash -LiteralPath $iverilogExe -Algorithm SHA256).Hash.ToLowerInvariant()
    $installedVvpHash = (Get-FileHash -LiteralPath $vvpExe -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($installedIverilogHash -ne $iverilogExeSha256 -or $installedVvpHash -ne $vvpExeSha256) {
        throw "Extracted RTL simulator SHA-256 mismatch"
    }
    & $iverilogExe -V 2>&1 | Select-Object -First 1
    Assert-NativeSuccess "Icarus Verilog version"
}

Push-Location $repositoryRoot
try {
    Write-Host "== Git commit policy =="
    & (Join-Path $PSScriptRoot "configure_git.ps1")

    Write-Host "== Python environment =="
    uv sync --frozen
    Assert-NativeSuccess "uv sync"
    uv run python --version
    Assert-NativeSuccess "uv run python"

    Write-Host "== Python checks =="
    uv run ruff check .
    Assert-NativeSuccess "ruff"
    uv run pytest
    Assert-NativeSuccess "pytest"
    uv run python -m scripts.generate_reference_vectors --check
    Assert-NativeSuccess "reference vector reproducibility"

    Write-Host "== vcpkg environment =="
    Initialize-Vcpkg

    Write-Host "== C++ test dependency =="
    Initialize-JsonHeader

    Write-Host "== RTL simulator =="
    Initialize-IcarusVerilog

    Write-Host "== Environment check =="
    & (Join-Path $PSScriptRoot "check_dev_env.ps1") -RequireIcarus

    Write-Host "== C++ configure =="
    cmake --preset dev-msvc --fresh
    Assert-NativeSuccess "cmake configure"

    Write-Host "== C++ build =="
    cmake --build --preset dev-msvc-release
    Assert-NativeSuccess "cmake build"

    Write-Host "== C++ test =="
    ctest --preset dev-msvc-release
    Assert-NativeSuccess "ctest"

    Write-Host "== RTL test =="
    & (Join-Path $PSScriptRoot "test_rtl.ps1")
}
finally {
    Pop-Location
}
