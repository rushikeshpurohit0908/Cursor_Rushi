#!/usr/bin/env python3
"""Reference RS(255,239) over GF(2^8) and table header for the FC128 RTL.

Production 128GFC uses an RS(544,514)-class code. This PoC engine is a real
t=8 Reed-Solomon codec with the same streaming RAM interface the wider code
would drop into. The script self-checks encode/decode (including shortened
messages and 1..8 symbol errors) and writes rtl/fc128/fc_rs_tables.vh.
"""

from __future__ import annotations

import os
import random
import sys

PRIM = 0x11D
T = 8
N_FULL = 255
K_FULL = 239
PARITY = 2 * T


class GF:
    def __init__(self) -> None:
        self.exp = [0] * 512
        self.log = [0] * 256
        x = 1
        for i in range(255):
            self.exp[i] = x
            self.log[x] = i
            x <<= 1
            if x & 0x100:
                x ^= PRIM
        for i in range(255, 512):
            self.exp[i] = self.exp[i - 255]

    def mul(self, a: int, b: int) -> int:
        if a == 0 or b == 0:
            return 0
        return self.exp[self.log[a] + self.log[b]]

    def div(self, a: int, b: int) -> int:
        if b == 0:
            raise ZeroDivisionError
        if a == 0:
            return 0
        return self.exp[(self.log[a] - self.log[b]) % 255]

    def pow_a(self, n: int) -> int:
        return 1 if n % 255 == 0 else self.exp[n % 255]


gf = GF()


def generator() -> list[int]:
    """g(x) = prod_{i=1..16} (x + alpha^i). Index is the power of x."""
    poly = [1]
    for i in range(1, PARITY + 1):
        root = gf.exp[i]
        nxt = [0] * (len(poly) + 1)
        for j, coef in enumerate(poly):
            nxt[j] ^= gf.mul(coef, root)
            nxt[j + 1] ^= coef
        poly = nxt
    assert len(poly) == PARITY + 1
    assert poly[PARITY] == 1
    return poly


G = generator()


def encode(msg: list[int]) -> list[int]:
    """Systematic encode. First byte is the highest-degree coefficient."""
    if not msg or len(msg) > K_FULL:
        raise ValueError(f"message length {len(msg)} out of range")
    # rem[j] is the coefficient of x^j. rem[15] is the current high term.
    rem = [0] * PARITY
    for symbol in msg:
        feedback = symbol ^ rem[PARITY - 1]
        new_rem = [0] * PARITY
        new_rem[0] = gf.mul(feedback, G[0])
        for j in range(1, PARITY):
            new_rem[j] = rem[j - 1] ^ gf.mul(feedback, G[j])
        rem = new_rem
    parity_tx = list(reversed(rem))  # x^15 transmitted first
    return msg + parity_tx


def horner(coeffs: list[int], x: int) -> int:
    acc = 0
    for coef in coeffs:
        acc = gf.mul(acc, x) ^ coef
    return acc


def syndromes(cw: list[int]) -> list[int]:
    return [horner(cw, gf.exp[i]) for i in range(1, PARITY + 1)]


def berlekamp_massey(s: list[int]) -> tuple[list[int], int]:
    n = PARITY
    lam = [0] * (n + 1)
    b = [0] * (n + 1)
    lam[0] = 1
    b[0] = 1
    length = 0
    m = 1
    bcoef = 1
    for n_idx in range(n):
        delta = s[n_idx]
        for j in range(1, length + 1):
            delta ^= gf.mul(lam[j], s[n_idx - j])
        if delta == 0:
            m += 1
        elif 2 * length <= n_idx:
            tpoly = lam[:]
            coef = gf.div(delta, bcoef)
            for j in range(m, n + 1):
                lam[j] ^= gf.mul(coef, b[j - m])
            length = n_idx + 1 - length
            b = tpoly
            bcoef = delta
            m = 1
        else:
            coef = gf.div(delta, bcoef)
            for j in range(m, n + 1):
                lam[j] ^= gf.mul(coef, b[j - m])
            m += 1
    return lam, length


def eval_poly(poly: list[int], deg: int, x: int) -> int:
    acc = 0
    xp = 1
    for j in range(deg + 1):
        acc ^= gf.mul(poly[j], xp)
        xp = gf.mul(xp, x)
    return acc


def chien(lam: list[int], length: int, nwords: int) -> list[int]:
    """Return byte indexes (0 = first transmitted) that have errors."""
    positions = []
    for power in range(nwords):
        # Locator argument alpha^{-power}. power 0 -> alpha^0 = 1.
        x = gf.pow_a(-power)
        if eval_poly(lam, length, x) == 0:
            positions.append(nwords - 1 - power)
    return positions


def forney(s: list[int], lam: list[int], length: int, positions: list[int], nwords: int) -> list[int]:
    omega = [0] * PARITY
    for i in range(PARITY):
        acc = 0
        for j in range(min(i, length) + 1):
            acc ^= gf.mul(lam[j], s[i - j])
        omega[i] = acc
    mags = []
    for byte_index in positions:
        power = nwords - 1 - byte_index
        xinv = gf.pow_a(-power)
        num = eval_poly(omega, PARITY - 1, xinv)
        den = 0
        xp = 1
        for j in range(1, length + 1, 2):
            den ^= gf.mul(lam[j], xp)
            xp = gf.mul(xp, gf.mul(xinv, xinv))
        if den == 0:
            raise ValueError("Forney denominator is zero")
        # This form matches roots alpha^1..alpha^16 and high-first codewords.
        mags.append(gf.div(num, den))
    return mags


def decode(cw: list[int]) -> tuple[list[int], int, bool]:
    """Return (corrected word, number of corrections, uncorrectable)."""
    s = syndromes(cw)
    if all(v == 0 for v in s):
        return cw[:], 0, False
    lam, length = berlekamp_massey(s)
    if length <= 0 or length > T:
        return cw[:], 0, True
    nwords = len(cw)
    try:
        positions = chien(lam, length, nwords)
    except Exception:
        return cw[:], 0, True
    if len(positions) != length:
        return cw[:], 0, True
    try:
        mags = forney(s, lam, length, positions, nwords)
    except Exception:
        return cw[:], 0, True
    out = cw[:]
    for pos, mag in zip(positions, mags):
        out[pos] ^= mag
    if any(v != 0 for v in syndromes(out)):
        return cw[:], 0, True
    return out, length, False


def self_check() -> None:
    rng = random.Random(128)
    # Full-length and shortened, 0..8 errors, plus a 9-error failure.
    cases = 0
    for k in (1, 2, 8, 16, 24, 64, 128, 239):
        for nerr in range(0, 9):
            for _trial in range(4 if nerr else 1):
                msg = [rng.randrange(256) for _ in range(k)]
                cw = encode(msg)
                assert syndromes(cw) == [0] * PARITY, "encoder did not land in the code"
                corrupted = cw[:]
                idxs = rng.sample(range(len(cw)), nerr) if nerr else []
                for idx in idxs:
                    corrupted[idx] ^= rng.randrange(1, 256)
                fixed, got, fail = decode(corrupted)
                cases += 1
                if nerr <= T:
                    if fail or fixed != cw or got != nerr:
                        raise SystemExit(
                            f"decode mismatch k={k} nerr={nerr} fail={fail} got={got}"
                        )
                else:
                    if not fail:
                        raise SystemExit(f"9-error case was accepted k={k}")
    # Known tiny vector printed for the RTL testbench.
    msg = [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]
    cw = encode(msg)
    bad = cw[:]
    bad[2] ^= 0x0F
    bad[10] ^= 0xA5
    fixed, got, fail = decode(bad)
    assert not fail and fixed == cw and got == 2
    print(f"RS self-check OK ({cases} cases)")
    print("VECTOR msg", " ".join(f"{b:02X}" for b in msg))
    print("VECTOR cw ", " ".join(f"{b:02X}" for b in cw))
    print("VECTOR bad", " ".join(f"{b:02X}" for b in bad))


def _vec(name: str, values: list[int], comment: str) -> str:
    """MSB is the last index so [idx*8 +: 8] selects that byte."""
    width = len(values) * 8 - 1
    lines = [f"// {comment}", f"localparam [{width}:0] {name} = {{"]
    rows = []
    rev = list(reversed(values))
    for i in range(0, len(rev), 8):
        chunk = ", ".join(f"8'h{b:02X}" for b in rev[i:i + 8])
        rows.append(f"  {chunk}")
    lines.append(",\n".join(rows))
    lines.append("};")
    return "\n".join(lines)


def write_header(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    parts = [
        "// Generated by scripts/gen_fc_rs_tables.py — do not edit.",
        "// GF(2^8) primitive polynomial x^8+x^4+x^3+x^2+1 (0x11D).",
        "// RS(255,239) generator roots alpha^1 .. alpha^16.",
        "// Byte 0 of each vector is the LSB, so element i is bits [i*8 +: 8].",
        _vec("RS_EXP_BITS", gf.exp[:512], "alpha^i, duplicated over 0..511"),
        _vec("RS_LOG_BITS", gf.log[:256], "discrete log, log(0) unused"),
        _vec("RS_GEN_BITS", G, "generator poly, index = power of x"),
    ]
    text = "\n".join(parts) + "\n"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"wrote {path}")


def main() -> None:
    self_check()
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    write_header(os.path.join(root, "rtl", "fc128", "fc_rs_tables.vh"))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 — surface the reference failure
        print(f"RS reference failed: {exc}", file=sys.stderr)
        sys.exit(1)
