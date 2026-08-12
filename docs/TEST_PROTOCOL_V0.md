# Test Protocol V0

Python、C++、RTL、FPGAの答え合わせに必要な仕様を定義する。Frame V0は安定したテスト用transportであり、Token payload境界はVersion 1として固定する。共有定数の正本は`spec/test_protocol_v0.yaml`とする。

## Common bit convention

* Multi-byte integer: little endian
* Byte内のbit: LSBがbit 0
* bit列はbyte 0のbit 0から順に格納
* bit lengthで使わない最終byteの上位bitは0

## Frame V0

| Offset | Size | Field |
| ---: | ---: | --- |
| 0 | 2 | SOF: `a5 5a` |
| 2 | 1 | Version: `0` |
| 3 | 1 | Message type |
| 4 | 2 | Flags |
| 6 | 2 | Payload length |
| 8 | variable | Opaque payload、0〜1024 bytes |
| 8 + N | 4 | CRC-32C |

CRC対象はVersionからPayload末尾まで。SOFとCRC自身は含めない。CRCはlittle endianで格納する。

| Value | Message type |
| ---: | --- |
| `01` | PING |
| `02` | PONG |
| `10` | TOKEN_REQUEST |
| `11` | TOKEN_RESULT |
| `7f` | ERROR_RESPONSE |

PINGのKnown Answer:

```text
a5 5a 00 01 00 00 00 00 26 13 3b 6f
```

Frame V0 Parserはgarbage prefix、CRC不一致、不正length、未対応versionの後にSOFを再探索する。

## Common values

* Timestamp単位: 1 us
* Timestamp基準: 各Run開始時のmonotonic clockを0とする
* `generated_time_us`と`deadline_us`は同じRun基準
* 有効性はflagで判断し、値0だけでは判断しない
* Sequenceは`stream_id`ごとに0から始め、u32 modulo `2^32`でwrapする
* 予約fieldは送信時0、受信時は値を無視する

## TokenRecord Version 1

Base Recordは40 bytes固定。Extension TLVを末尾に連結する。

| Offset | Size | Field | Type |
| ---: | ---: | --- | --- |
| 0 | 1 | `record_version` = 1 | u8 |
| 1 | 1 | `flags`: bit 0 generated time valid、bit 1 deadline valid | u8 |
| 2 | 2 | `base_length` = 40 | u16 |
| 4 | 4 | `stream_id` | u32 |
| 8 | 4 | `sequence` | u32 |
| 12 | 4 | `token_id` | u32 |
| 16 | 1 | `importance` = 0 | u8 |
| 17 | 3 | reserved = 0 | bytes |
| 20 | 8 | `generated_time_us` | u64 |
| 28 | 8 | `deadline_us` | u64 |
| 36 | 2 | `extension_length` | u16 |
| 38 | 2 | reserved = 0 | u16 |

Extensionは`type: u8`、`length: u8`、`value: length bytes`。未知typeもlength分をskipする。headerまたはvalueが不足するExtensionはPayload全体を拒否する。

Known Answer:

```text
stream_id          = 0x11223344
sequence           = 0xffffffff
token_id           = 0x55667788
generated_time_us  = 1000, valid
deadline_us        = 2000, valid
extension          = type 0x80, value aa55

01 03 28 00 44 33 22 11 ff ff ff ff 88 77 66 55
00 00 00 00 e8 03 00 00 00 00 00 00 d0 07 00 00
00 00 00 00 04 00 00 00 80 02 aa 55
```

## ProtectionRequest Version 1

| Offset | Size | Field | Type |
| ---: | ---: | --- | --- |
| 0 | 1 | `request_version` = 1 | u8 |
| 1 | 1 | `mode`: 0 NONE、1 REPETITION、2 HAMMING_7_4 | u8 |
| 2 | 2 | `flags` = 0 | u16 |
| 4 | 2 | `block_length_bits` | u16 |
| 6 | 1 | `repetition_count` | u8 |
| 7 | 1 | reserved = 0 | u8 |
| 8 | 2 | `code_rate_num` | u16 |
| 10 | 2 | `code_rate_den` | u16 |
| 12 | 4 | reserved = 0 | u32 |

`block_length_bits`は直前のserialized TokenRecord全体と一致させる。NONEはR=1、rate 1/1。REPETITIONはR=1または3、rate 1/R。HAMMING_7_4はR=1、rate 4/7。不正な組合せを暗黙補正しない。

## ChannelState Version 1

| Offset | Size | Field | Type |
| ---: | ---: | --- | --- |
| 0 | 1 | `state_version` = 1 | u8 |
| 1 | 1 | `flags`: bit 0 quality valid | u8 |
| 2 | 2 | `channel_quality` | u16 |

Qualityは0を最悪、65535を最良とする。物理単位は割り当てず、invalid時は0とする。

## ResultStatus Version 1

| Offset | Size | Field | Type |
| ---: | ---: | --- | --- |
| 0 | 4 | `flags` | u32 |
| 4 | 2 | `corrected_count` | u16 |
| 6 | 2 | `detected_error_count` | u16 |

Flag割当:

| Bit | Name |
| ---: | --- |
| 0 | `PARITY_ERROR` |
| 1 | `FEC_CORRECTED` |
| 2 | `CRC_ERROR` |
| 3 | `MALFORMED_FRAME` |
| 4 | `MALFORMED_REQUEST` |
| 5 | `UNSUPPORTED_VERSION` |
| 6 | `UNSUPPORTED_PROTECTION` |
| 7 | `SEQUENCE_GAP` |
| 8 | `UART_FRAMING_ERROR` |
| 9 | `INTERNAL_OVERFLOW` |

Hamming(7,4)やRepetitionの訂正能力外を推測で`UNCORRECTABLE`にしない。検出できた現象だけを記録する。

## Message payloads

`TOKEN_REQUEST`:

```text
TokenRecord[base_length + extension_length]
ProtectionRequest[16]
ChannelState[4]
```

`TOKEN_RESULT`:

```text
TokenRecord[base_length + extension_length]
ResultStatus[8]
```

`ERROR_RESPONSE`は`flags: u32`、`request_message_type: u8`、reserved 3 bytesの計8 bytes。CRC不一致など信頼できないrequest payloadはechoしない。

## CRC-32C

* Polynomial: Castagnoli `0x1EDC6F41`
* Reflected implementation value: `0x82F63B78`
* Init: `0xFFFFFFFF`
* Xor out: `0xFFFFFFFF`
* Check: `CRC-32C("123456789") = 0xE3069283`

## FEC reference

### Even parity

Data bitとparity bitの1の合計を偶数にする。

### Repetition

* V0はR=1とR=3
* 各input bitを連続してR回出力
* R=3は3bitごとにmajority vote
* R=3の1group内single-bit errorのみ訂正を保証

### Hamming(7,4)

Data nibbleは`d0, d1, d2, d3`のLSB-firstとする。Codeword位置1〜7は次の順。

```text
p1 p2 d0 p4 d1 d2 d3
```

```text
p1 = d0 xor d1 xor d3
p2 = d0 xor d2 xor d3
p4 = d1 xor d2 xor d3
```

single-error correctionのみ。2bit errorの検出・訂正を保証しない。最終nibbleの不足bitは0 paddingし、元bit lengthを別に保持する。

## JSONL boundary

Pythonは`datasets/test_vectors/protocol_v0/*.jsonl`を生成する。C++ / RTL / FPGAは同じ`case_id`でResult JSONLを出力し、Pythonのoffline evaluatorが比較する。

Vectorの主要field:

* `schema_version`: V0は`0`
* `case_id`: 全Vectorで一意
* `algorithm`
* input / encoded / received / decodedのhexとbit length
* `parameters`
* `error_bit_positions`
* `expected_status`

PythonとC++は実行時にFFIやsubprocessで結合せず、このVersion付きJSONLだけを共有する。

## Valid / Ready

* 転送成立は`valid && ready`
* `valid && !ready`中はdata、last、sidebandを保持する
* Reset解除直後の`out_valid`は0
* 入力未受理cycleでは状態を進めない
* Packet末尾は`last`
* Byte streamは`data[7:0]`、bit streamは`data[0]`
* Module間にreadyの組合せloopを作らない
