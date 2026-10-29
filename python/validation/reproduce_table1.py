"""
Reproduces Table 1 of de Melo, Graziadei & Targino (2026): empirical size at
alpha = 0.05 when the reference table is correct (Poisson DGP), using the
paper's design: ages 40-90, E_x ~ Normal(N/51, N/(3*51)) rounded,
Gompertz q_x = a exp(b x), a = 4.87e-5, b = 8.87e-2, 1,000 replications.

Run:  python validation/reproduce_table1.py
"""
import sys
import numpy as np
from mortalityAdherence import _tests as T

PAPER = {500: (16, .212, .025, .047, .048, .059),
         1200: (39, .182, .026, .053, .045, .057),
         4500: (147, .117, .024, .047, .045, .049),
         25000: (816, .071, .021, .046, .044, .048),
         45000: (1468, .066, .021, .052, .053, .053)}


def run(N, reps=1000, seed=2026):
    rng = np.random.default_rng(seed)
    ages = np.arange(40, 91).astype(float)
    qx = 4.87e-5 * np.exp(8.87e-2 * ages)
    g = (ages - ages.mean()) / ages.std(ddof=1)
    rej = np.zeros(5); Qs = []
    for _ in range(reps):
        E = np.maximum(np.round(rng.normal(N / 51, N / (3 * 51), size=51)), 1)
        mu0 = E * qx
        d = rng.poisson(mu0).astype(float)
        Qs.append(mu0.sum())
        ks = T.test_ks(d, mu0, 0.05)
        chi = T.test_chisq(d, mu0, 0.05)
        p = T.poisson_family(d, mu0, g, 0.05, d, mu0)
        rej += [chi["reject"], bool(ks["reject"]), p["WaldI_P"]["reject"],
                p["WaldII_P"]["reject"], p["BayesCI"]["reject"]]
    return np.mean(Qs), rej / reps


if __name__ == "__main__":
    reps = int(sys.argv[1]) if len(sys.argv) > 1 else 1000
    print(f"{'N':>6} {'Q':>6} | {'Chi2':>11} {'KS':>11} {'Wald I':>11} {'Wald II':>11} {'Bayes CI':>11}")
    print(" " * 16 + "   python / paper" * 1)
    for N, ref in PAPER.items():
        Q, r = run(N, reps)
        cells = " ".join(f"{a:.3f}/{b:.3f}".rjust(11) for a, b in zip(r, ref[1:]))
        print(f"{N:>6} {Q:>6.0f} | {cells}")
