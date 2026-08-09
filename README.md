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
