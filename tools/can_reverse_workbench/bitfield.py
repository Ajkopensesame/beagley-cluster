from __future__ import annotations


def signal_fits(payload_length: int, start_bit: int, length: int) -> bool:
    return start_bit >= 0 and length > 0 and start_bit + length <= payload_length * 8


def extract_signal_value(data: bytes, start_bit: int, length: int, endian: str, signed: bool) -> int:
    """Extract a CAN signal while preserving the workbench's byte-aligned v1 behavior.

    Byte-aligned fields use Python byteorder semantics. Non-byte-aligned big-endian
    fields use MSB-first bit numbering; non-byte-aligned little-endian fields use
    LSB-first bit numbering.
    """
    if not signal_fits(len(data), start_bit, length):
        raise ValueError("signal does not fit payload")
    if endian not in {"big", "little"}:
        raise ValueError("endian must be big or little")

    if start_bit % 8 == 0 and length % 8 == 0:
        byte_index = start_bit // 8
        byte_length = length // 8
        raw = int.from_bytes(data[byte_index : byte_index + byte_length], byteorder=endian, signed=False)
    elif endian == "big":
        raw = _extract_big_endian_bits(data, start_bit, length)
    else:
        raw = _extract_little_endian_bits(data, start_bit, length)

    if signed:
        return _sign_extend(raw, length)
    return raw


def _extract_big_endian_bits(data: bytes, start_bit: int, length: int) -> int:
    raw = 0
    for bit_offset in range(length):
        bit_index = start_bit + bit_offset
        byte_index = bit_index // 8
        bit_in_byte = 7 - (bit_index % 8)
        raw = (raw << 1) | ((data[byte_index] >> bit_in_byte) & 1)
    return raw


def _extract_little_endian_bits(data: bytes, start_bit: int, length: int) -> int:
    raw = 0
    for bit_offset in range(length):
        bit_index = start_bit + bit_offset
        byte_index = bit_index // 8
        bit_in_byte = bit_index % 8
        raw |= ((data[byte_index] >> bit_in_byte) & 1) << bit_offset
    return raw


def _sign_extend(raw: int, length: int) -> int:
    sign_bit = 1 << (length - 1)
    if raw & sign_bit:
        return raw - (1 << length)
    return raw
