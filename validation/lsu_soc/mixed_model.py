"""Independent integer reference, not derived from RTL outputs. Python 3.10+."""
import argparse
from pathlib import Path


def expected():
    mask = 0xffffffff
    values = [0, 1, mask, 0x80000000, 0x7fffffff, 0x8000ff, 0x13579bdf, 0xfedcba98]
    seed = 0x20260927
    for _ in range(24):
        seed = (1664525 * seed + 1013904223) & mask
        values.append(seed)
    words, checksum, negative = [], 0, 0
    for i, x in enumerate(values):
        y = ((x * 7 + i) & mask) ^ (x >> 3)
        signed = y if y < 0x80000000 else y - 0x100000000
        # Python // rounds down, RISC-V DIV truncates toward zero.
        q = (abs(signed) // 3) * (-1 if signed < 0 else 1)
        r = signed - q * 3
        byte, half = q & 255, r & 65535
        checksum = (checksum + byte + half + (-q if signed < 0 else q)) & mask
        checksum ^= y
        negative += signed < 0
        words.extend([q & mask, r & mask, byte << (8 * (i % 4)),
                      half << (16 * (i % 2)), y, checksum,
                      (byte if byte < 128 else byte - 256) & mask,
                      (half if half < 32768 else half - 65536) & mask])
    assert 0 < negative < len(values)
    assert words[:8] == [0] * 8
    return values, words, negative


if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("output", type=Path)
    args = parser.parse_args()
    values, words, negative = expected()
    args.output.mkdir(parents=True, exist_ok=True)
    (args.output / "mixed_inputs.inc").write_text(
        "".join(f".word 0x{x:08x}\n" for x in values), encoding="ascii")
    (args.output / "mixed_expected.hex").write_text(
        "".join(f"{x:08x}\n" for x in words), encoding="ascii")
    print(f"REFERENCE: rows=32 words=256 negative={negative} nonnegative={32-negative}")
