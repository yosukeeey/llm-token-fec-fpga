from sw.common.crc32c import CRC32C_INITIAL, CRC32C_XOR_OUT, crc32c, crc32c_update


def test_crc32c_known_answers() -> None:
    assert crc32c(b"") == 0
    assert crc32c(b"123456789") == 0xE3069283


def test_crc32c_incremental_matches_one_shot() -> None:
    state = CRC32C_INITIAL
    for byte in b"123456789":
        state = crc32c_update(state, bytes([byte]))
    assert state ^ CRC32C_XOR_OUT == crc32c(b"123456789")
