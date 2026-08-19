import pytest

from sw.channel import transmit
from sw.common.bits import unpack_bits

PAYLOAD = bytes([0b10110101, 0b01001110, 0b11110000, 0b00001111])
PAYLOAD_BITS = 32


def test_same_seed_reproduces_the_error_pattern() -> None:
    first = transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=0.25, seed=7)
    second = transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=0.25, seed=7)

    assert first.flipped_positions == second.flipped_positions
    assert first.data == second.data


def test_different_seeds_give_different_patterns() -> None:
    first = transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=0.25, seed=1)
    second = transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=0.25, seed=2)

    assert first.flipped_positions != second.flipped_positions


def test_zero_probability_leaves_the_input_unchanged() -> None:
    result = transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=0.0, seed=1)

    assert result.data == PAYLOAD
    assert result.flipped_positions == ()
    assert result.bit_errors == 0


def test_unit_probability_inverts_every_bit() -> None:
    result = transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=1.0, seed=1)

    sent = unpack_bits(PAYLOAD, PAYLOAD_BITS)
    received = unpack_bits(result.data, PAYLOAD_BITS)
    assert received == [1 - bit for bit in sent]
    assert result.bit_errors == PAYLOAD_BITS


def test_flipped_positions_match_the_received_bits() -> None:
    result = transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=0.5, seed=3)

    sent = unpack_bits(PAYLOAD, PAYLOAD_BITS)
    received = unpack_bits(result.data, PAYLOAD_BITS)
    differing = {index for index in range(PAYLOAD_BITS) if sent[index] != received[index]}
    assert differing == set(result.flipped_positions)
    assert list(result.flipped_positions) == sorted(result.flipped_positions)


def test_observed_rate_approaches_the_requested_probability() -> None:
    bit_length = 40000
    data = bytes(bit_length // 8)

    result = transmit(data, bit_length, flip_probability=0.01, seed=11)

    observed = result.bit_errors / bit_length
    assert abs(observed - 0.01) < 0.002


def test_empty_input_is_accepted() -> None:
    result = transmit(b"", 0, flip_probability=0.5, seed=1)

    assert result.data == b""
    assert result.flipped_positions == ()


@pytest.mark.parametrize("flip_probability", [-0.1, 1.1])
def test_rejects_probabilities_outside_the_unit_interval(
    flip_probability: float,
) -> None:
    with pytest.raises(ValueError, match="flip_probability must be between 0 and 1"):
        transmit(PAYLOAD, PAYLOAD_BITS, flip_probability=flip_probability, seed=1)


def test_rejects_a_non_canonical_bit_length() -> None:
    with pytest.raises(ValueError, match="minimal byte length"):
        transmit(PAYLOAD, 8, flip_probability=0.1, seed=1)
