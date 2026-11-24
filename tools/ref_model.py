#!/usr/bin/env python3
"""
independent reference model for the lfsr dice project.

written separately from the verilog so the two can cross-check each other:
  1. proves the chosen feedback polynomial is primitive (pure GF(2) algebra,
     no simulation) -> guarantees period 2^16-1.
  2. brute-forces the period of the shift-register as implemented.
  3. prints golden vectors that are hard-coded into tb/lfsr_tb.v.
  4. models the dice roller (4 lfsr steps per draw, reject 0 and 7) and
     writes every roll to a file that run_sim.sh diffs against the
     verilog simulation output.
  5. computes exact full-period statistics (faces, pairs, sums) and the
     naive-modulo bias for comparison.

usage: python3 ref_model.py [out_dir]
"""
import sys, os

N = 16
PERIOD = (1 << N) - 1                    # 65535 = 3 * 5 * 17 * 257
PRIME_FACTORS = [3, 5, 17, 257]

# feedback polynomial  p(x) = x^16 + x^14 + x^13 + x^11 + 1
POLY_EXPONENTS = [16, 14, 13, 11, 0]
DEFAULT_SEED = 0xACE1
STEPS_PER_DRAW = 4


# ---------------------------------------------------------------- GF(2) math
def poly_from_exps(exps):
    v = 0
    for e in exps:
        v |= 1 << e
    return v


def gf2_mulmod(a, b, m):
    deg = m.bit_length() - 1
    r = 0
    while b:
        if b & 1:
            r ^= a
        b >>= 1
        a <<= 1
        if (a >> deg) & 1:
            a ^= m
    return r


def gf2_powmod(base, e, m):
    r = 1
    while e:
        if e & 1:
            r = gf2_mulmod(r, base, m)
        base = gf2_mulmod(base, base, m)
        e >>= 1
    return r


def is_primitive(p):
    """degree-n p is primitive  <=>  order of x mod p is exactly 2^n - 1."""
    n = p.bit_length() - 1
    order = (1 << n) - 1
    if gf2_powmod(2, order, p) != 1:
        return False
    for q in PRIME_FACTORS:
        if gf2_powmod(2, order // q, p) == 1:
            return False
    return True


def reciprocal(p):
    n = p.bit_length() - 1
    return int(format(p, "0%db" % (n + 1))[::-1], 2)


# ---------------------------------------------------------------- the LFSR
# fibonacci form, shifting towards the msb, new bit enters bit 0.
# a tap at polynomial exponent e (e >= 1) reads register bit e-1.
TAP_BITS = [e - 1 for e in POLY_EXPONENTS if e > 0]   # [15, 13, 12, 10]


def lfsr_step(s):
    fb = 0
    for t in TAP_BITS:
        fb ^= (s >> t) & 1
    return ((s << 1) & 0xFFFF) | fb


def lfsr_period(seed):
    s = lfsr_step(seed)
    n = 1
    while s != seed:
        if s == 0:
            raise RuntimeError("hit zero state")
        s = lfsr_step(s)
        n += 1
        if n > PERIOD + 1:
            raise RuntimeError("no return to seed")
    return n


# ---------------------------------------------------------------- dice model
def draw(s):
    """advance STEPS_PER_DRAW times, return (new_state, low 3 bits)."""
    for _ in range(STEPS_PER_DRAW):
        s = lfsr_step(s)
    return s, s & 7


def roll(s):
    """returns (new_state, die1, die2, rejects_before_die1, rejects_before_die2)."""
    dice, rej = [], []
    while len(dice) < 2:
        r = 0
        while True:
            s, v = draw(s)
            if 1 <= v <= 6:
                break
            r += 1
        dice.append(v)
        rej.append(r)
    return s, dice[0], dice[1], rej[0], rej[1]


def chi2(counts, expected):
    return sum((c - expected) ** 2 / expected for c in counts)


def pearson(xs, ys):
    n = len(xs)
    mx, my = sum(xs) / n, sum(ys) / n
    sxy = sum((x - mx) * (y - my) for x, y in zip(xs, ys))
    sxx = sum((x - mx) ** 2 for x in xs)
    syy = sum((y - my) ** 2 for y in ys)
    return sxy / (sxx * syy) ** 0.5


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else "."
    os.makedirs(out_dir, exist_ok=True)
    p = poly_from_exps(POLY_EXPONENTS)
    pr = reciprocal(p)

    print("=== 1. polynomial algebra ===")
    print("p(x)      = 0x%05X  x^16+x^14+x^13+x^11+1     primitive: %s" % (p, is_primitive(p)))
    print("recip p*  = 0x%05X  x^16+x^5+x^3+x^2+1        primitive: %s" % (pr, is_primitive(pr)))
    # negative controls: these must NOT pass the primitivity test
    print("control   x^16+x^15+1                       primitive: %s"
          % is_primitive(poly_from_exps([16, 15, 0])))
    print("control   x^16+x^14+x^13+x^12+1 (wrong tap) primitive: %s"
          % is_primitive(poly_from_exps([16, 14, 13, 12, 0])))
    print("tap bits used by rtl: %s" % TAP_BITS)

    print("\n=== 2. brute-force period ===")
    for seed in (0x0001, DEFAULT_SEED, 0xFFFF, 0x8000):
        print("seed 0x%04X -> period %d" % (seed, lfsr_period(seed)))
    seen = set()
    s = 1
    for _ in range(PERIOD):
        seen.add(s)
        s = lfsr_step(s)
    print("distinct states visited from seed 1: %d (zero visited: %s)" % (len(seen), 0 in seen))

    print("\n=== 3. golden vectors from seed 0x%04X ===" % DEFAULT_SEED)
    s = DEFAULT_SEED
    marks = {1, 2, 3, 16, 100, 1000, 65534, 65535}
    for i in range(1, PERIOD + 1):
        s = lfsr_step(s)
        if i in marks:
            print("after %5d steps: 0x%04X" % (i, s))

    print("\n=== 4. die mapping, exact counts ===")
    # (a) every state once, low 3 bits
    c3 = [0] * 8
    s = 1
    for _ in range(PERIOD):
        c3[s & 7] += 1
        s = lfsr_step(s)
    print("low-3-bit codes over all 65535 states: %s" % c3)
    # (b) decimated draws (4 steps apart), one full period of draws
    cd = [0] * 8
    s = DEFAULT_SEED
    run = maxrun = 0
    for _ in range(PERIOD):
        s, v = draw(s)
        cd[v] += 1
    # cyclic max run of rejects
    vals = []
    s = DEFAULT_SEED
    for _ in range(PERIOD):
        s, v = draw(s)
        vals.append(v)
    vv = vals + vals
    for v in vv:
        if v in (0, 7):
            run += 1
            maxrun = max(maxrun, run)
        else:
            run = 0
    print("codes over 65535 decimated draws:     %s" % cd)
    print("draw sequence returns to seed after 65535 draws: %s" % (s == DEFAULT_SEED))
    print("max consecutive rejected draws (cyclic): %d" % maxrun)

    print("\n=== 5. naive modulo for comparison (faces 1..6) ===")
    n16 = [0] * 6
    s = 1
    for _ in range(PERIOD):
        n16[s % 6] += 1
        s = lfsr_step(s)
    print("(state16 %% 6)+1 over full period: %s" % n16)
    n3 = [0] * 6
    for v in range(8):
        n3[v % 6] += 1
    print("(rnd3 %% 6)+1 over the 8 codes:    %s   <- faces 1,2 twice as likely" % n3)

    print("\n=== 6. game model ===")
    s0 = DEFAULT_SEED
    s = s0
    rolls = []
    starts = []
    while True:
        starts.append(s)
        s, d1, d2, r1, r2 = roll(s)
        rolls.append((d1, d2, r1, r2))
        if s == s0:
            break
        if len(rolls) > 100000:
            raise RuntimeError("no roll period")
    P = len(rolls)
    print("roll-sequence period: %d rolls (lfsr back at seed)" % P)
    with open(os.path.join(out_dir, "rolls_ref.txt"), "w") as f:
        for d1, d2, _, _ in rolls + rolls:      # two periods, same as the tb
            f.write("%d %d\n" % (d1, d2))

    faces1 = [0] * 7
    faces2 = [0] * 7
    pairs = [[0] * 7 for _ in range(7)]
    sums = [0] * 13
    for d1, d2, _, _ in rolls:
        faces1[d1] += 1
        faces2[d2] += 1
        pairs[d1][d2] += 1
        sums[d1 + d2] += 1
    print("die1 faces 1..6: %s" % faces1[1:])
    print("die2 faces 1..6: %s" % faces2[1:])
    print("both combined  : %s" % [a + b for a, b in zip(faces1[1:], faces2[1:])])
    print("pair counts (rows die1=1..6, cols die2=1..6), expected %.2f each:" % (P / 36))
    for a in range(1, 7):
        print("   %d: %s" % (a, " ".join("%4d" % pairs[a][b] for b in range(1, 7))))
    flat = [pairs[a][b] for a in range(1, 7) for b in range(1, 7)]
    print("pair min/max: %d / %d   chi2 (35 dof) = %.2f   (5%% critical value 49.80)"
          % (min(flat), max(flat), chi2(flat, P / 36)))
    print("sum counts 2..12: %s" % sums[2:])
    exp_sum = [P * min(k - 1, 13 - k) / 36 for k in range(2, 13)]
    print("expected        : %s" % ["%.1f" % e for e in exp_sum])
    d1s = [r[0] for r in rolls]
    d2s = [r[1] for r in rolls]
    sm = [r[0] + r[1] for r in rolls]
    print("pearson(die1, die2)          = %+.5f" % pearson(d1s, d2s))
    print("pearson(sum[k], sum[k+1])    = %+.5f" % pearson(sm, sm[1:] + sm[:1]))
    print("pearson(die2[k], die1[k+1])  = %+.5f" % pearson(d2s, d1s[1:] + d1s[:1]))
    # pairs split by rejects between die1 and die2
    for label, cond in (("0 rejects between dice", lambda r: r[3] == 0),
                        (">=3 rejects between", lambda r: r[3] >= 3)):
        sub = [[0] * 7 for _ in range(7)]
        n = 0
        for r in rolls:
            if cond(r):
                sub[r[0]][r[1]] += 1
                n += 1
        f = [sub[a][b] for a in range(1, 7) for b in range(1, 7)]
        print("%-24s n=%5d  pair min/max %d/%d" % (label, n, min(f), max(f)))
    print("mean draws per die: %.4f (ideal 8/6 = 1.3333)"
          % (sum(1 + r[2] + 1 + r[3] for r in rolls) / (2 * P)))

    print("\n=== 7. what the seed actually selects ===")
    # every seed gives a dice stream that is periodic with P rolls and is a
    # rotation of one of two fixed loops (which accepted draws pair up as
    # die1/die2 depends on where you enter the draw cycle).
    def stream(seed, n):
        st, out = seed, []
        for _ in range(n):
            st, a, b, _, _ = roll(st)
            out.append(a * 8 + b)
        return out
    loop_a = bytes(stream(DEFAULT_SEED, P))
    aa = loop_a + loop_a
    loop_b = None
    in_a = in_b = other = 0
    test_seeds = [0x0001, 0xFFFF, 0x8000, 0x1234] + [(i * 7919 + 13) & 0xFFFF or 1 for i in range(60)]
    for sd in test_seeds:
        r = stream(sd, 2 * P)
        if r[:P] != r[P:]:
            other += 1
            continue
        loop = bytes(r[:P])
        if loop in aa:
            in_a += 1
        else:
            if loop_b is None:
                loop_b = loop + loop
            if loop in loop_b:
                in_b += 1
            else:
                other += 1
    print("%d seeds tested: %d on loop A, %d on loop B, %d elsewhere"
          % (len(test_seeds), in_a, in_b, other))
    if loop_b is not None:
        h = [0] * 64
        for v in loop_b[:P]:
            h[v] += 1
        fb = [h[a * 8 + b] for a in range(1, 7) for b in range(1, 7)]
        print("loop B pair min/max %d/%d, chi2 %.2f" % (min(fb), max(fb), chi2(fb, P / 36)))


if __name__ == "__main__":
    main()
