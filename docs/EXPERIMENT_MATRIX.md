# Experiment matrix

Fixes the conditions under which equal and unequal protection are compared, so
that a difference in the result cannot come from a difference in what was
spent. Metric definitions live in [Transmission metrics](METRICS.md).

## Equivalence condition

Two protection assignments are comparable when they hand the same number of
bits to the channel for the same payload. This is the matched budget rule.

Let `N` be the payload bit count and `R` the code rate of a scheme, so a
uniform assignment transmits `N / R` channel bits. Splitting the payload into
classes with bit counts `N_i` and rates `R_i` transmits the sum of `N_i / R_i`.

```text
matched budget:  sum(N_i / R_i) = N / R_reference
payload split:   sum(N_i) = N
```

The second constraint keeps the payload fixed, so the comparison varies only
how protection is distributed. A uniform assignment is the special case with
one class.

Equal average code rate is the same condition rewritten, since the average rate
is `N / sum(N_i / R_i)`. Matched budget is used as the primary form because it
is the quantity the channel and the link actually spend, and because it stays
meaningful when a class uses no coding.

## Available rates

Only schemes already implemented in `sw/fec/` are used.

| Scheme | Rate | Correction |
| --- | --- | --- |
| none | 1 | none |
| Hamming(7,4) | 4/7 | one bit per codeword |
| repetition, R equal to 3 | 1/3 | one bit per group |

Even parity is detection only and carries no correction, so it is not used as a
protection class in this matrix.

## Baseline sweep

Equal protection across the whole payload, one row per combination. Token IDs
come from the recorded baseline responses, so no inference runs here.

| Axis | Values |
| --- | --- |
| Scheme | none, Hamming(7,4), repetition R equal to 3 |
| Bit flip probability | 0.0001, 0.001, 0.01, 0.05 |
| Seed | 1, 2, 3 |
| Dataset | `datasets/prompts/baseline_v1.jsonl` responses |

That is 3 schemes by 4 probabilities by 3 seeds, which is 36 runs over 39
records each. Each run is bit manipulation only, so a full sweep completes in
seconds rather than the tens of minutes an inference pass takes.

## Matched budget comparison

The unequal assignment is compared against uniform Hamming(7,4), which spends
`1.75 N` channel bits. A two class split that protects a fraction `f` of the
payload with repetition R equal to 3 and leaves the rest uncoded spends
`N (1 + 2 f)`. Matching the budget fixes the fraction.

```text
N (1 + 2 f) = 1.75 N
f = 0.375
```

So the unequal assignment protects 37.5 percent of the payload bits with
repetition and none of the rest, and spends exactly what uniform
Hamming(7,4) spends. The same construction applies to any reference scheme:
solve for the fraction that equalizes the budget, then assign the protected
fraction by importance.

| Condition | High class | Low class | Channel bits |
| --- | --- | --- | --- |
| Equal protection reference | Hamming(7,4) over all bits | none | 1.75 N |
| Unequal protection | repetition R equal to 3 over 0.375 N | none over 0.625 N | 1.75 N |

Which bits fall in the high class is decided by the importance work and is not
fixed here. This document fixes only the budget the two conditions may spend.

## Reporting

Every run records the scheme assignment, the bit flip probability, the seed,
and the channel bit count. A comparison is only valid when the channel bit
counts of the compared rows are equal, so the count is reported rather than
assumed.
