# Test Protocol V0

Python、C++、RTL、FPGAの答え合わせに必要な最小仕様だけを定義する。Frame V0はテスト用であり、将来のToken FEC通信仕様ではない。

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
| `10` | TEST_REQUEST |
| `11` | TEST_RESULT |
| `7f` | ERROR_RESPONSE |

PINGのKnown Answer:

```text
a5 5a 00 01 00 00 00 00 26 13 3b 6f
```

Frame V0 Parserはgarbage prefix、CRC不一致、不正length、未対応versionの後にSOFを再探索する。PayloadのToken / FEC layoutはV0で規定しない。

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
