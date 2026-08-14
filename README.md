# # LLMトークン通信向け適応型誤り訂正のFPGA実装

## Overview

LLM間でTokenを直接通信する際に、各Tokenの重要度に応じて誤り保護強度を変更する方式をFPGA上に実装・評価するプロジェクト。

重要なTokenには強いFECやRepetitionを適用し、重要度の低いTokenには軽い保護を適用することで、通信量や遅延を抑えながらLLMのタスク性能を維持することを目指す。

```text
Local LLM
    ↓
Token ID + Importance
    ↓
FPGA
 ├─ Protection Controller
 ├─ Adaptive Repetition
 └─ Adaptive FEC
    ↓
Communication Channel
    ↓
FPGA Decoder
    ↓
Recovered Tokens
    ↓
Local LLM
```

## Why FPGA

Token Importanceと通信路状態に応じて、FEC強度やRepetition回数をリアルタイムに切り替える処理は、ストリーミング・パイプライン処理との相性がよい。

FPGAを用いることで、以下を狙う。

* Token受信と同時にProtection Levelを決定
* FEC・Repetition・復号処理の並列化
* 固定レイテンシでのリアルタイム処理
* 高スループットなToken / Bit Stream処理
* PHYに近い位置での高速な通信路適応
* CPUを介さずProtection ControlからFECまで連続処理

LLM推論そのものはPC上で実行し、FPGAはToken通信におけるリアルタイムなProtection ControlとError Correctionを担当する。

## Development environment

PythonはGolden Model、Test Vector生成、offline検証に使用する。PC-FPGA通信はC++20とWin32 APIで実装し、Pythonに通信ライブラリを入れない。

Prerequisites:

* Python 3.12と[uv](https://docs.astral.sh/uv/)
* Visual Studio 2022のDesktop development with C++、MSVC x64、Windows SDK
* [CMake](https://cmake.org/) 3.25以上
* Git。`bootstrap.ps1`が固定commitの[vcpkg](https://learn.microsoft.com/en-us/vcpkg/)を`build/tools/vcpkg/`へ準備する

`bootstrap.ps1`はRTL単体検証用のIcarus Verilogも固定Version・SHA-256検証付きで`build/tools/iverilog/`へ配置する。Perlは使用しない。

PowerShellで初回SetupとSmoke Testを実行する。

```powershell
.\scripts\bootstrap.ps1
```

Pull Request CIと同じ回帰検証は、LLM用依存とvcpkg準備を除外して実行できる。

```powershell
.\scripts\bootstrap.ps1 -ContinuousIntegration
```

個別に実行する場合:

```powershell
.\scripts\check_dev_env.ps1
cmake --preset dev-msvc
cmake --build --preset dev-msvc-release
ctest --preset dev-msvc-release
.\scripts\test_rtl.ps1
.\scripts\test_streaming_rtl.ps1
.\scripts\test_frame_rtl.ps1
.\scripts\test_uart_rtl.ps1
```

Pythonの依存は`uv.lock`、C++の依存は必要になった時点で`vcpkg.json`へ追加し、`builtin-baseline`で固定する。現在のC++ Environment Smoke Testは標準Libraryだけを使う。生成物、Tool本体、cacheは`build/`、vcpkg packageは`vcpkg_installed/`に置き、Git管理しない。

## Python reference implementation

Python参照実装は通信を行わず、C++ / RTL / FPGAの独立な答え合わせに使用する。Frame V0は接続試験用transportとして維持し、Token payload境界はVersion 1として固定する。詳細は[`docs/TEST_PROTOCOL_V0.md`](docs/TEST_PROTOCOL_V0.md)を参照する。

```text
spec/            Python / C++ / RTL共通定数の正本
sw/common/       bit列、CRC-32C、Frame V0、Token payload型
sw/fec/          Parity、Repetition、Hamming(7,4)
sw/evaluation/   JSONL schema、Vector生成、Result比較
sw/cpp/          独立なC++20実装とPython Vector一致Test
scripts/         Vector生成CLI、Result評価CLI
rtl/common/      Streaming CRC-32Cと同期FIFO
rtl/fec/         組合せFECとValid/Ready wrapper
rtl/tb/          Python Vector駆動・Streaming自己検査Testbench
```

C++のCRC / FEC / Frame実装は標準Libraryだけを使う。JSONL readerのみ[nlohmann/json](https://github.com/nlohmann/json)を使い、BootstrapがVersionとSHA-256を検証して`build/tools/`へ配置する。PythonとC++は同じ実装を共有せず、固定JSONL Vector経由でbit / byte一致をCTestする。

Golden Vectorの生成と再現性確認:

```powershell
uv run python -m scripts.generate_protocol_constants --check
uv run python -m scripts.generate_reference_vectors
uv run python -m scripts.generate_reference_vectors --check
```

C++ / RTL / FPGAが出力したResult JSONLのoffline評価:

```powershell
uv run python -m scripts.evaluate_reference_results `
  --vectors datasets/test_vectors/protocol_v0/repetition.jsonl `
  --results build/results/repetition.jsonl
```

RTL検証は固定JSONLからSimulator入力を生成し、Parity 3件、Repetition 5件、Hamming(7,4) 128件を実行する。各TestbenchのResult JSONLは`build/results/rtl/`へ出力され、同じoffline evaluatorで照合される。

```powershell
.\scripts\test_rtl.ps1
.\scripts\test_streaming_rtl.ps1
.\scripts\test_frame_rtl.ps1
.\scripts\test_uart_rtl.ps1
```

Basys 3実機検証の準備状況と記録方法は[`docs/bringup/README.md`](docs/bringup/README.md)に定義する。
