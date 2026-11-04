#!/usr/bin/env python3
"""Reference RS(544,514) over GF(2^10) and the table header for fc_rs544.

This is the FC-PI-8 / IEEE 802.3 Clause 91 KP4 code: primitive polynomial
x^10 + x^3 + 1 (0x409), generator roots alpha^0 .. alpha^29. The script
checks the generator against the published 802.3bj coefficients, round-trips
shortened and full codewords through t = 15, and writes
rtl/fc128/fc_rs544_tables.vh.
"""

from __future__ import annotations

import os
import random
import sys

PRIM = 0x409
FIELD = 1023
T = 15
N_FULL = 544
K_FULL = 514
PARITY = 2 * T

# IEEE 802.3bj PAM4 generator, x^29 down to x^0. The x^30 coefficient is 1.
PUBLISHED_HI_TO_LO = [
    575, 552, 187, 230, 552, 1, 108, 565, 282, 249,
    593, 132, 94, 720, 495, 385, 942, 503, 883, 361,
    788, 610, 193, 392, 127, 185, 158, 128, 834, 523,
]


class GF:
    def __init__(self) -> None:
        self.exp = [0] * 2048
        self.log = [0] * 1024
        x = 1
        seen: dict[int, int] = {}
        for i in range(FIELD):
            if x in seen:
                raise RuntimeError(f"polynomial is not primitive at alpha^{i}")
            seen[x] = i
            self.exp[i] = x
            self.log[x] = i
            x <<= 1
            if x & 0x400:
                x ^= PRIM
        if x != 1:
            raise RuntimeError("alpha^1023 did not return to 1")
        for i in range(FIELD, 2048):
            self.exp[i] = self.exp[i - FIELD]

    def mul(self, a: int, b: int) -> int:
        if a == 0 or b == 0:
            return 0
        return self.exp[self.log[a] + self.log[b]]

    def div(self, a: int, b: int) -> int:
        if b == 0:
            raise ZeroDivisionError
        if a == 0:
            return 0
        return self.exp[(self.log[a] - self.log[b]) % FIELD]

    def pow_a(self, n: int) -> int:
        n %= FIELD
        return 1 if n == 0 else self.exp[n]

    def pow_neg(self, power: int) -> int:
        modp = power % FIELD
        if modp == 0:
            return 1
        return self.exp[FIELD - modp]


gf = GF()


def generator() -> list[int]:
    """g(x) = prod_{i=0..29} (x + alpha^i). Index is the power of x."""
    poly = [1]
    for i in range(PARITY):
        root = gf.exp[i]
        nxt = [0] * (len(poly) + 1)
        for j, coef in enumerate(poly):
            nxt[j] ^= gf.mul(coef, root)
            nxt[j + 1] ^= coef
        poly = nxt
    if len(poly) != PARITY + 1 or poly[PARITY] != 1:
        raise RuntimeError("generator is not monic of degree 30")
    if list(reversed(poly[:PARITY])) != PUBLISHED_HI_TO_LO:
        raise RuntimeError("generator does not match the 802.3bj coefficients")
    return poly


G = generator()


def encode(msg: list[int]) -> list[int]:
    """Systematic encode. Symbol 0 is the highest-degree coefficient."""
    if not msg or len(msg) > K_FULL:
        raise ValueError(f"message length {len(msg)} out of range")
    rem = [0] * PARITY
    for symbol in msg:
        feedback = symbol ^ rem[PARITY - 1]
        new_rem = [0] * PARITY
        new_rem[0] = gf.mul(feedback, G[0])
        for j in range(1, PARITY):
            new_rem[j] = rem[j - 1] ^ gf.mul(feedback, G[j])
        rem = new_rem
    return msg + list(reversed(rem))


def horner(coeffs: list[int], x: int) -> int:
    acc = 0
    for coef in coeffs:
        acc = gf.mul(acc, x) ^ coef
    return acc


def syndromes(cw: list[int]) -> list[int]:
    return [horner(cw, gf.exp[i]) for i in range(PARITY)]


def berlekamp_massey(s: list[int]) -> tuple[list[int], int]:
    n = PARITY
    lam = [0] * (n + 1)
    bpoly = [0] * (n + 1)
    lam[0] = 1
    bpoly[0] = 1
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
            saved = lam[:]
            coef = gf.div(delta, bcoef)
            for j in range(m, n + 1):
                lam[j] ^= gf.mul(coef, bpoly[j - m])
            length = n_idx + 1 - length
            bpoly = saved
            bcoef = delta
            m = 1
        else:
            coef = gf.div(delta, bcoef)
            for j in range(m, n + 1):
                lam[j] ^= gf.mul(coef, bpoly[j - m])
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
    """Symbol indexes (0 = first transmitted) whose locator root is alpha^{-power}."""
    positions = []
    for power in range(nwords):
        if eval_poly(lam, length, gf.pow_neg(power)) == 0:
            positions.append(nwords - 1 - power)
    return positions


def forney(
    s: list[int], lam: list[int], length: int, positions: list[int], nwords: int
) -> list[int]:
    """Magnitudes for roots alpha^0 .. alpha^29. Y = X * Omega(X^-1) / Lambda'(X^-1)."""
    omega = [0] * PARITY
    for i in range(PARITY):
        acc = 0
        for j in range(min(i, length) + 1):
            acc ^= gf.mul(lam[j], s[i - j])
        omega[i] = acc
    mags = []
    for index in positions:
        power = nwords - 1 - index
        xinv = gf.pow_neg(power)
        num = gf.mul(gf.pow_a(power), eval_poly(omega, PARITY - 1, xinv))
        den = 0
        xp = 1
        for j in range(1, length + 1, 2):
            den ^= gf.mul(lam[j], xp)
            xp = gf.mul(xp, gf.mul(xinv, xinv))
        if den == 0:
            raise ValueError("Forney denominator is zero")
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
    positions = chien(lam, length, nwords)
    if len(positions) != length:
        return cw[:], 0, True
    try:
        mags = forney(s, lam, length, positions, nwords)
    except ValueError:
        return cw[:], 0, True
    out = cw[:]
    for pos, mag in zip(positions, mags):
        out[pos] ^= mag
    if any(v != 0 for v in syndromes(out)):
        return cw[:], 0, True
    return out, length, False


def _corrupt(cw: list[int], places: list[int], flip: int) -> list[int]:
    bad = cw[:]
    for index in places:
        bad[index] ^= flip
    return bad


def self_check() -> list[int]:
    rng = random.Random(544)
    cases = 0
    for k in (1, 2, 8, 17, 64, 128, 514):
        span = (0, 1, 2, 8, 15) if k < 514 else (0, 1, 15)
        trials = 1 if k >= 128 else 2
        for nerr in span:
            for _trial in range(1 if nerr == 0 else trials):
                msg = [rng.randrange(1024) for _ in range(k)]
                cw = encode(msg)
                if any(syndromes(cw)):
                    raise SystemExit(f"encoder missed the code k={k}")
                bad = cw[:]
                for index in (rng.sample(range(len(cw)), nerr) if nerr else []):
                    bad[index] ^= rng.randrange(1, 1024)
                fixed, got, fail = decode(bad)
                cases += 1
                if fail or fixed != cw or got != nerr:
                    raise SystemExit(
                        f"decode mismatch k={k} nerr={nerr} fail={fail} got={got}"
                    )
    msg = [0x011, 0x022, 0x033, 0x044, 0x155, 0x266, 0x077, 0x088]
    cw = encode(msg)
    fixed, got, fail = decode(_corrupt(cw, list(range(15)), 0x155))
    if fail or fixed != cw or got != 15:
        raise SystemExit("directed 15-error vector was not corrected")
    _fixed, _got, fail16 = decode(_corrupt(cw, list(range(16)), 0x3FF))
    if not fail16:
        raise SystemExit("directed 16-error vector was accepted")
    full = [i & 0x3FF for i in range(K_FULL)]
    full_cw = encode(full)
    ends = [0, K_FULL - 1, N_FULL - 1]
    bad_full = full_cw[:]
    for index in ends:
        bad_full[index] ^= 0x2A5
    fixed, got, fail = decode(bad_full)
    if fail or fixed != full_cw or got != 3:
        raise SystemExit("full-length end-symbol case failed")
    print(f"RS(544,514) self-check OK ({cases} random cases + directed)")
    print("VECTOR msg", " ".join(f"{b:03X}" for b in msg))
    print("VECTOR cw ", " ".join(f"{b:03X}" for b in cw))
    return cw


def _vec(name: str, values: list[int], comment: str) -> str:
    """Element 0 is the LSB group, so element i is bits [i*10 +: 10]."""
    width = len(values) * 10 - 1
    lines = [f"// {comment}", f"localparam [{width}:0] {name} = {{"]
    rows = []
    rev = list(reversed(values))
    for i in range(0, len(rev), 8):
        chunk = ", ".join(f"10'h{b:03X}" for b in rev[i:i + 8])
        rows.append(f"  {chunk}")
    lines.append(",\n".join(rows))
    lines.append("};")
    return "\n".join(lines)


def write_header(path: str) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    parts = [
        "// Generated by scripts/gen_fc_rs544_tables.py — do not edit.",
        "// GF(2^10) primitive polynomial x^10+x^3+1 (0x409).",
        "// RS(544,514) generator roots alpha^0 .. alpha^29.",
        "// Generator coefficients match IEEE 802.3bj (x^29 .. x^0).",
        "// Element 0 of each vector is the LSB group, bits [i*10 +: 10].",
        _vec("RS544_EXP_BITS", gf.exp[:2048], "alpha^i, duplicated past 1022"),
        _vec("RS544_LOG_BITS", gf.log[:1024], "discrete log, log(0) unused"),
        _vec("RS544_GEN_BITS", G, "generator poly, index = power of x"),
    ]
    text = "\n".join(parts) + "\n"
    with open(path, "w", encoding="utf-8") as fh:
        fh.write(text)
    print(f"wrote {path}")


def main() -> None:
    self_check()
    root = os.path.abspath(os.path.join(os.path.dirname(__file__), ".."))
    write_header(os.path.join(root, "rtl", "fc128", "fc_rs544_tables.vh"))


if __name__ == "__main__":
    try:
        main()
    except Exception as exc:  # noqa: BLE001 — surface the reference failure
        print(f"RS(544,514) reference failed: {exc}", file=sys.stderr)
        sys.exit(1)
