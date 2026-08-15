# Transmission metrics

Definitions for the error metrics reported by transmission experiments. The
definitions apply to simulated channels and to hardware captures, so results
from either source are comparable. Bit order and serialization follow
[Test Protocol V0](TEST_PROTOCOL_V0.md).

## Measured stages

One transmission passes through four stages:

```text
token IDs --serialize--> payload bits --encode--> channel bits
        --channel--> received bits --decode--> recovered payload bits --> recovered token IDs
```

Metrics are counted at two of them: `channel bits` for BER and `token IDs` for
TER.

## Bit error rate

BER counts bit errors introduced by the channel, before decoding.

```text
BER = (number of positions where received bit differs from channel bit)
      / (number of channel bits)
```

- The denominator is the number of bits handed to the channel, including FEC
  redundancy and padding. It is not the payload bit count.
- Padding bits added to complete the last byte or the last codeword are part of
  the transmission and are counted.
- BER is a property of the channel and the transmitted length only. It does not
  depend on the FEC scheme beyond the length the scheme produces.

## Token error rate

TER counts tokens that are not recovered exactly, after decoding.

```text
TER = (number of token positions that do not match the sent token)
      / (number of sent tokens)
```

- The denominator is always the number of sent tokens, so TER stays comparable
  across schemes and channel conditions.
- A token position counts as an error unless the recovered token ID equals the
  sent token ID at the same position.

### Decode failure

A decoder may report failure without producing bits, for example when a CRC
check fails or a codeword is rejected. Every token covered by a failed decode
counts as an error. Failure never removes tokens from the denominator.

### Length mismatch

The recovered token sequence may be shorter or longer than the sent one.

- Positions beyond the end of the recovered sequence count as errors.
- Tokens recovered beyond the sent length are counted as errors and are added
  to the numerator, while the denominator stays at the sent token count. TER
  can therefore exceed 1 when a decode inserts tokens.
- Truncation of the payload before transmission is not a transmission error.
  Truncation is a generation setting and is recorded separately.

## Weighted token error rate

WTER weights each token error by the importance assigned to that token. The
weighting scheme is fixed by the unequal protection work and is not defined
here.

```text
WTER = (sum of weights of mismatched token positions) / (sum of weights of sent tokens)
```

With uniform weights, WTER equals TER.

## Log columns

Experiment logs record the raw counts alongside the rates so that runs can be
aggregated without recomputing from responses.

| Column | Meaning |
| --- | --- |
| `channel_bits` | Bits handed to the channel, the BER denominator |
| `bit_errors` | Bits changed by the channel, the BER numerator |
| `ber` | `bit_errors / channel_bits` |
| `sent_tokens` | Tokens serialized for transmission, the TER denominator |
| `token_errors` | Mismatched token positions, the TER numerator |
| `ter` | `token_errors / sent_tokens` |
| `decode_failures` | Decode operations that reported failure |
| `recovered_tokens` | Tokens produced by the decoder, for length comparison |

Rates are derived columns. When a run is aggregated, sum the counts first and
divide once, rather than averaging per-record rates.
