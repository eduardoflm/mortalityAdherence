"""
The 11 goodness-of-fit tests of de Melo, Graziadei & Targino (2026),
"Annuity Table Validation in Pension Funds: A Comparative Power Analysis of
Goodness-of-Fit Tests", SSRN 6668699.

Notation follows the paper:
    cells C = {(x, t): E_{x,t} > 0},  k = |C|
    D = sum d_{x,t}            (total observed deaths)
    Q = sum E_{x,t} q_x        (total expected deaths under the table)
    g_x = (x - x_bar) / s_x    (standardised age over the ages in the data)

Every test returns a dict with keys:
    reject (True/False/None), statistic, p_value, df, note
where None / NaN mean "not applicable" (N/A).
"""

from __future__ import annotations

import math
from typing import Dict, Optional

import numpy as np
from scipy import stats

from ._glm import fit_nb, fit_poisson, poisson_loglik


def _na(note: str = "", df=None) -> dict:
    return {"reject": None, "statistic": np.nan, "p_value": np.nan,
            "df": df, "note": note}


# ---------------------------------------------------------------------------
# Kolmogorov-Smirnov critical value (exact port of sfsmisc::KSd, alpha = 5%)
# ---------------------------------------------------------------------------

# Lienert (1975) / Miller (1956) table used by sfsmisc::KSd for n <= 80
_KSD_X = np.array([1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 20, 30, 40, 50, 60, 70, 80],
                  dtype=float)
_KSD_Y = np.array([.975, .84189, .70760, .62394, .56328, .51926, .48342, .45427,
                   .43001, .40925, .33760, .29408, .24170, .21012, .18841, .17231,
                   .15975, .14960])


def _fmm_spline_coef(x, y):
    """Port of R's fmm_spline (Forsythe, Malcolm & Moler), as in splinefun()."""
    n = len(x)
    b = np.zeros(n); c = np.zeros(n); d = np.zeros(n)
    nm1 = n - 1
    d[0] = x[1] - x[0]
    c[1] = (y[1] - y[0]) / d[0]
    for i in range(1, nm1):
        d[i] = x[i + 1] - x[i]
        b[i] = 2.0 * (d[i - 1] + d[i])
        c[i + 1] = (y[i + 1] - y[i]) / d[i]
        c[i] = c[i + 1] - c[i]
    b[0] = -d[0]
    b[nm1] = -d[nm1 - 1]
    c[0] = c[nm1] = 0.0
    if n > 3:
        c[0] = c[2] / (x[3] - x[1]) - c[1] / (x[2] - x[0])
        c[nm1] = c[nm1 - 1] / (x[nm1] - x[nm1 - 2]) - c[nm1 - 2] / (x[nm1 - 1] - x[nm1 - 3])
        c[0] = c[0] * d[0] * d[0] / (x[3] - x[0])
        c[nm1] = -c[nm1] * d[nm1 - 1] * d[nm1 - 1] / (x[nm1] - x[nm1 - 3])
    for i in range(1, n):
        t = d[i - 1] / b[i - 1]
        b[i] = b[i] - t * d[i - 1]
        c[i] = c[i] - t * c[i - 1]
    c[nm1] = c[nm1] / b[nm1]
    for i in range(nm1 - 1, -1, -1):
        c[i] = (c[i] - d[i] * c[i + 1]) / b[i]
    b[nm1] = (y[nm1] - y[nm1 - 1]) / d[nm1 - 1] + d[nm1 - 1] * (c[nm1 - 1] + 2.0 * c[nm1])
    for i in range(nm1):
        b[i] = (y[i + 1] - y[i]) / d[i] - d[i] * (c[i + 1] + 2.0 * c[i])
        d[i] = (c[i + 1] - c[i]) / d[i]
        c[i] = 3.0 * c[i]
    c[nm1] = 3.0 * c[nm1]
    d[nm1] = d[nm1 - 1]
    return b, c, d


_KSD_B, _KSD_C, _KSD_DD = _fmm_spline_coef(_KSD_X, _KSD_Y)


def ks_critical_005(n: float) -> float:
    """sfsmisc::KSd(n): 5% critical value of the KS statistic."""
    if n > 80:
        return 1.358 / (math.sqrt(n) + 0.12 + 0.11 / math.sqrt(n))
    i = int(np.searchsorted(_KSD_X, n, side="right") - 1)
    i = min(max(i, 0), len(_KSD_X) - 1)
    dx = n - _KSD_X[i]
    return float(_KSD_Y[i] + dx * (_KSD_B[i] + dx * (_KSD_C[i] + dx * _KSD_DD[i])))


def ks_critical(n: float, alpha: float) -> float:
    """
    Critical value used for the KS decision.
    alpha = 0.05: identical to sfsmisc::KSd (as in the R package).
    other alpha: Stephens' finite-sample form c_alpha/(sqrt(n)+0.12+0.11/sqrt(n)).
    """
    if abs(alpha - 0.05) < 1e-12:
        return ks_critical_005(n)
    c = stats.kstwobign.ppf(1.0 - alpha)
    return c / (math.sqrt(n) + 0.12 + 0.11 / math.sqrt(n))


# ---------------------------------------------------------------------------
# 1-2. Traditional tests
# ---------------------------------------------------------------------------

def test_ks(d_age: np.ndarray, mu_age: np.ndarray, alpha: float) -> dict:
    """
    KS on the age margins (paper, eq. 2): d_x = sum_t d_{x,t},
    E_x q_x = sum_t E_{x,t} q_x, ages in increasing order.
    """
    D = d_age.sum()
    if D <= 0:
        return _na("No deaths in the sample: KS statistic undefined.")
    F_hat = np.cumsum(d_age) / D
    F0 = np.cumsum(mu_age) / mu_age.sum()
    ks = float(np.max(np.abs(F_hat - F0)))
    crit = ks_critical(D, alpha)
    # approximate p-value (continuous Kolmogorov calibration, Stephens' form)
    sqn = math.sqrt(D)
    p_approx = float(stats.kstwobign.sf(ks * (sqn + 0.12 + 0.11 / sqn)))
    return {"reject": bool(ks > crit), "statistic": ks, "p_value": p_approx,
            "df": None, "critical": crit,
            "note": f"Critical value = {crit:.4f} (p-value approx.)"}


def test_chisq(d: np.ndarray, mu0: np.ndarray, alpha: float,
               df_rule: str = "k-1") -> dict:
    """Pearson chi-squared over all cells (paper, eq. 1)."""
    k = len(d)
    X2 = float(np.sum((d - mu0) ** 2 / np.maximum(mu0, 1e-12)))
    df = k - 1 if df_rule == "k-1" else k
    pv = float(stats.chi2.sf(X2, df))
    n_small = int(np.sum(mu0 < 1.0))
    note = f"df = {df} ({df_rule})"
    if n_small > 0:
        note += f"; {n_small} of {k} cells with expected deaths < 1"
    return {"reject": bool(pv < alpha), "statistic": X2, "p_value": pv,
            "df": df, "note": note}


# ---------------------------------------------------------------------------
# 3-7. Poisson family + Bayesian credible interval
# ---------------------------------------------------------------------------

ZERO_DEATHS_WALD = ("No deaths in the sample (D = 0): Wald tests are not "
                    "applicable (de Melo et al., 2026, Sec. 3.5).")


def poisson_family(d, mu0, g, alpha: float, d_age, mu_age) -> Dict[str, dict]:
    D = float(d.sum())
    Q = float(mu0.sum())
    offset = np.log(np.maximum(mu0, 1e-300))
    out: Dict[str, dict] = {}

    # ---- Wald I (closed form, eq. 8): W = log(D/Q) sqrt(D) ----------------
    if D == 0:
        out["WaldI_P"] = _na(ZERO_DEATHS_WALD, df=1)
    else:
        W = math.log(D / Q) * math.sqrt(D)
        pv = 2.0 * stats.norm.sf(abs(W))
        out["WaldI_P"] = {"reject": bool(pv < alpha), "statistic": W,
                          "p_value": float(pv), "df": 1, "note": ""}

    # ---- LRT I (closed form, eq. 11) --------------------------------------
    lam1 = 2.0 * (Q if D == 0 else (D * math.log(D / Q) - (D - Q)))
    lam1 = max(lam1, 0.0)
    pv = float(stats.chi2.sf(lam1, 1))
    out["LRTI_P"] = {"reject": bool(pv < alpha), "statistic": lam1, "p_value": pv,
                     "df": 1, "note": "D = 0: statistic = 2Q" if D == 0 else ""}

    # ---- Version II: GLM with log mu = offset + b1 + b2 g ------------------
    X = np.column_stack([np.ones_like(g), g])
    if D == 0:
        out["WaldII_P"] = _na(ZERO_DEATHS_WALD, df=2)
        lam2 = 2.0 * Q          # sup loglik = 0, loglik(0) = -Q
        pv = float(stats.chi2.sf(lam2, 2))
        out["LRTII_P"] = {"reject": bool(pv < alpha), "statistic": lam2,
                          "p_value": pv, "df": 2, "note": "D = 0: statistic = 2Q"}
    else:
        fit = fit_poisson(d, offset, X)
        b = fit.beta
        W2 = float(b @ fit.info @ b)                  # eq. 13
        pv = float(stats.chi2.sf(W2, 2))
        out["WaldII_P"] = {"reject": bool(pv < alpha), "statistic": W2,
                           "p_value": pv, "df": 2, "note": "",
                           "beta": b.tolist()}
        ll0 = poisson_loglik(d, mu0)
        lam2 = max(2.0 * (fit.loglik - ll0), 0.0)    # eq. 14
        pv = float(stats.chi2.sf(lam2, 2))
        out["LRTII_P"] = {"reject": bool(pv < alpha), "statistic": lam2,
                          "p_value": pv, "df": 2, "note": ""}

    # ---- Bayesian credible interval (Gamma-Poisson, Sec. 3.2) --------------
    out["BayesCI"] = bayes_ci(d_age, mu_age, D, Q, alpha)
    return out


def bayes_ci(d_age, mu_age, D, Q, alpha) -> dict:
    """
    Empirical-Bayes Gamma(a0, b0) prior by the method of moments on the
    age-specific ratios theta_x = sum_t d_{x,t} / sum_t E_{x,t} q_x (eq. 9).
    Posterior: Gamma(a0 + D, b0 + Q). Reported 'p_value' is the posterior
    tail probability pi = 2 min{P(theta<=1|d), P(theta>=1|d)} (eq. 10),
    which is NOT a frequentist p-value.
    """
    theta_x = d_age / np.maximum(mu_age, 1e-300)
    note_prior = ""
    if len(theta_x) >= 2:
        m = float(np.mean(theta_x))
        v = float(np.var(theta_x, ddof=1))
    else:
        m = v = 0.0
    if m > 0 and v > 0:
        a0, b0 = m * m / v, m / v
    else:
        # degenerate sample (e.g. D = 0): the paper notes the empirical-Bayes
        # calibration needs a separate convention; we use the near-noninformative
        # reference prior a0 = b0 = 0.001, which the EB prior tracks (Sec. 3.2).
        a0 = b0 = 0.001
        note_prior = "; degenerate sample: reference prior a0 = b0 = 0.001 used"
    ap, bp = a0 + D, b0 + Q
    post = stats.gamma(a=ap, scale=1.0 / bp)
    lo, hi = float(post.ppf(alpha / 2)), float(post.ppf(1 - alpha / 2))
    pi = float(2.0 * min(post.cdf(1.0), post.sf(1.0)))
    pct = round(100 * (1 - alpha))
    return {"reject": bool(lo > 1.0 or hi < 1.0), "statistic": np.nan,
            "p_value": min(pi, 1.0), "df": None,
            "ci_lower": lo, "ci_upper": hi, "a0": a0, "b0": b0,
            "note": f"{pct}% CI: [{lo:.4f}, {hi:.4f}]; posterior tail prob."
                    + note_prior}


# ---------------------------------------------------------------------------
# 8-11. Negative Binomial family
# ---------------------------------------------------------------------------

def dispersion_ratio(d, mu0) -> float:
    """Pearson chi2 / df of the intercept-only Poisson model (as in the R package)."""
    D, Q = d.sum(), mu0.sum()
    k = len(d)
    if D <= 0 or k < 2:
        return float("nan")
    mu_hat = mu0 * D / Q
    return float(np.sum((d - mu_hat) ** 2 / mu_hat) / (k - 1))


def nb_family(d, mu0, g, alpha: float, skip_reason: Optional[str] = None) -> Dict[str, dict]:
    names = ("WaldI_NB", "WaldII_NB", "LRTI_NB", "LRTII_NB")
    dfs = (1, 2, 1, 2)
    if skip_reason:
        return {n: _na(skip_reason, df=k) for n, k in zip(names, dfs)}

    D = float(d.sum())
    Q = float(mu0.sum())
    out: Dict[str, dict] = {}
    if D == 0:
        # phi-hat -> infinity: the NB likelihood reduces to the Poisson one
        out["WaldI_NB"] = _na(ZERO_DEATHS_WALD, df=1)
        out["WaldII_NB"] = _na(ZERO_DEATHS_WALD, df=2)
        for n, k in (("LRTI_NB", 1), ("LRTII_NB", 2)):
            pv = float(stats.chi2.sf(2 * Q, k))
            out[n] = {"reject": bool(pv < alpha), "statistic": 2 * Q, "p_value": pv,
                      "df": k, "note": "D = 0: phi -> inf, statistic = 2Q"}
        return out

    offset = np.log(np.maximum(mu0, 1e-300))
    ones = np.ones_like(g)
    f0 = fit_nb(d, offset, None)
    f1 = fit_nb(d, offset, ones[:, None])
    f2 = fit_nb(d, offset, np.column_stack([ones, g]))

    def phi_note(f):
        return "phi at boundary (Poisson limit)" if f.phi_at_boundary else f"phi = {f.phi:.2f}"

    b = f1.beta[0]
    se = 1.0 / math.sqrt(float(f1.info[0, 0]))
    z = b / se
    pv = float(2.0 * stats.norm.sf(abs(z)))
    out["WaldI_NB"] = {"reject": bool(pv < alpha), "statistic": z, "p_value": pv,
                       "df": 1, "note": phi_note(f1), "phi": f1.phi}

    W2 = float(f2.beta @ f2.info @ f2.beta)
    pv = float(stats.chi2.sf(W2, 2))
    out["WaldII_NB"] = {"reject": bool(pv < alpha), "statistic": W2, "p_value": pv,
                        "df": 2, "note": phi_note(f2), "phi": f2.phi,
                        "beta": f2.beta.tolist()}

    lam = max(2.0 * (f1.loglik - f0.loglik), 0.0)
    pv = float(stats.chi2.sf(lam, 1))
    out["LRTI_NB"] = {"reject": bool(pv < alpha), "statistic": lam, "p_value": pv,
                      "df": 1, "note": phi_note(f1)}

    lam = max(2.0 * (f2.loglik - f0.loglik), 0.0)
    pv = float(stats.chi2.sf(lam, 2))
    out["LRTII_NB"] = {"reject": bool(pv < alpha), "statistic": lam, "p_value": pv,
                       "df": 2, "note": phi_note(f2)}
    return out
