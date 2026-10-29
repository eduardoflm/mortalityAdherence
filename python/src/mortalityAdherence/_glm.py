"""
Maximum-likelihood fitting for the GLM-with-offset models of the paper.

Model (paper, eq. 3):

    d_{x,t} ~ G(mu_{x,t}),   log mu_{x,t} = log(E_{x,t} q_x) + X beta

where G is Poisson or Negative Binomial (NB2, Var = mu + mu^2/phi) and
log(E q) is a fixed, known offset. Only beta (and phi for the NB) are
estimated.

All fitting is done here, with numpy/scipy only, so that results do not
depend on the version of any third-party statistics library. The routines
were validated against R (stats::glm and MASS::glm.nb); see tests/.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Optional

import numpy as np
from scipy import optimize, special

# phi is optimised on the log scale inside these bounds. phi -> infinity is
# the Poisson limit; reaching the upper bound is reported as "phi at boundary".
_LOG_PHI_MIN = np.log(1e-6)
_LOG_PHI_MAX = np.log(1e10)
_LOG_PHI_FLAT = np.log(1e8)   # above this, phi-hat is taken as the Poisson limit


# ---------------------------------------------------------------------------
# Poisson
# ---------------------------------------------------------------------------

@dataclass
class PoissonFit:
    beta: np.ndarray        # MLE of beta
    mu: np.ndarray          # fitted means
    loglik: float           # full log-likelihood (with -log d! constants)
    info: np.ndarray        # expected Fisher information at beta-hat
    converged: bool


def poisson_loglik(d: np.ndarray, mu: np.ndarray) -> float:
    """Full Poisson log-likelihood, sum(d log mu - mu - log d!)."""
    mu = np.maximum(mu, 1e-300)
    return float(np.sum(special.xlogy(d, mu) - mu - special.gammaln(d + 1.0)))


def fit_poisson(d: np.ndarray, offset: np.ndarray, X: np.ndarray,
                maxit: int = 100, tol: float = 1e-10) -> PoissonFit:
    """Newton-Raphson (= IRLS for the canonical log link) with step halving."""
    with np.errstate(over="ignore", invalid="ignore", divide="ignore"):
        return _fit_poisson(d, offset, X, maxit, tol)


def _fit_poisson(d, offset, X, maxit, tol):
    p = X.shape[1]
    beta = np.zeros(p)
    # good start for the intercept: log(D/Q)
    D, Q = d.sum(), np.exp(offset).sum()
    if D > 0 and p >= 1 and np.allclose(X[:, 0], 1.0):
        beta[0] = np.log(D / Q)

    def ll(b):
        return poisson_loglik(d, np.exp(offset + X @ b))

    cur = ll(beta)
    converged = False
    for _ in range(maxit):
        mu = np.exp(offset + X @ beta)
        score = X.T @ (d - mu)
        info = X.T @ (mu[:, None] * X)
        try:
            step = np.linalg.solve(info, score)
        except np.linalg.LinAlgError:
            break
        t = 1.0
        while True:
            new = beta + t * step
            val = ll(new)
            if val >= cur - 1e-12 or t < 1e-8:
                break
            t /= 2.0
        delta = abs(val - cur)
        beta, cur = new, val
        if delta < tol * (abs(cur) + tol):
            converged = True
            break
    mu = np.exp(offset + X @ beta)
    info = X.T @ (mu[:, None] * X)
    return PoissonFit(beta=beta, mu=mu, loglik=cur, info=info,
                      converged=converged)


# ---------------------------------------------------------------------------
# Negative Binomial (NB2)
# ---------------------------------------------------------------------------

@dataclass
class NBFit:
    beta: np.ndarray            # MLE of beta (empty array for the H0 model)
    phi: float                  # MLE of phi (MASS::glm.nb calls it theta)
    mu: np.ndarray
    loglik: float               # full log-likelihood (matches logLik(glm.nb))
    info: Optional[np.ndarray]  # expected Fisher information for beta at phi-hat
    phi_at_boundary: bool       # True when phi-hat -> infinity (Poisson limit)


def nb_loglik(d: np.ndarray, mu: np.ndarray, phi: float) -> float:
    """Full NB2 log-likelihood (paper, eq. 6), including -log d!."""
    mu = np.maximum(mu, 1e-300)
    return float(np.sum(
        special.gammaln(d + phi) - special.gammaln(phi) - special.gammaln(d + 1.0)
        + special.xlogy(d, mu / (phi + mu))
        + phi * np.log(phi / (phi + mu))
    ))


def _nb_beta_given_phi(d, offset, X, phi, beta0, maxit=100, tol=1e-11):
    """For fixed phi the NB2 log-likelihood is concave in beta: Newton."""
    beta = beta0.copy()

    def ll(b):
        return nb_loglik(d, np.exp(offset + X @ b), phi)

    cur = ll(beta)
    for _ in range(maxit):
        mu = np.exp(offset + X @ beta)
        w = mu / (1.0 + mu / phi)
        score = X.T @ ((d - mu) / (1.0 + mu / phi))
        # observed information (positive definite, concave problem)
        h = phi * mu * (d + phi) / (phi + mu) ** 2
        info = X.T @ (h[:, None] * X)
        try:
            step = np.linalg.solve(info, score)
        except np.linalg.LinAlgError:
            step = np.linalg.lstsq(X.T @ (w[:, None] * X), score, rcond=None)[0]
        t = 1.0
        while True:
            new = beta + t * step
            val = ll(new)
            if val >= cur - 1e-12 or t < 1e-8:
                break
            t /= 2.0
        delta = abs(val - cur)
        beta, cur = new, val
        if delta < tol * (abs(cur) + tol):
            break
    return beta, cur


def fit_nb(d: np.ndarray, offset: np.ndarray, X: Optional[np.ndarray]) -> NBFit:
    with np.errstate(over="ignore", invalid="ignore", divide="ignore"):
        return _fit_nb(d, offset, X)


def _fit_nb(d, offset, X):
    """
    Joint MLE of (beta, phi) by profiling phi out:
    for each phi, beta(phi) maximises the (concave) log-likelihood; the
    profile log-likelihood is then maximised over log(phi) with Brent's method.

    X = None (or a 0-column matrix) gives the H0 model, where beta = 0 and
    only phi is estimated (paper, eq. 12: phi re-estimated under H0).
    """
    n = d.shape[0]
    if X is None:
        X = np.zeros((n, 0))
    p = X.shape[1]

    start = np.zeros(p)
    if p > 0:
        pf = fit_poisson(d, offset, X)
        start = pf.beta

    cache = {}

    def neg_profile(log_phi):
        phi = float(np.exp(log_phi))
        if p == 0:
            val = nb_loglik(d, np.exp(offset), phi)
            cache[log_phi] = (np.zeros(0), val)
        else:
            b, val = _nb_beta_given_phi(d, offset, X, phi, start)
            cache[log_phi] = (b, val)
        return -val

    # coarse grid first (the profile is usually unimodal, but be safe)
    grid = np.linspace(_LOG_PHI_MIN, _LOG_PHI_MAX, 49)
    vals = np.array([neg_profile(g) for g in grid])
    i = int(np.argmin(vals))
    lo = grid[max(i - 1, 0)]
    hi = grid[min(i + 1, len(grid) - 1)]
    res = optimize.minimize_scalar(neg_profile, bounds=(lo, hi), method="bounded",
                                   options={"xatol": 1e-9, "maxiter": 500})
    best = res.x if res.fun <= vals[i] else grid[i]
    # The profile is flat as phi -> infinity (no overdispersion): report the
    # Poisson limit deterministically, at the upper bound phi = 1e10.
    if best > _LOG_PHI_FLAT:
        best = _LOG_PHI_MAX
    beta, val = cache.get(best, (None, None))
    if beta is None:
        neg_profile(best)
        beta, val = cache[best]

    phi = float(np.exp(best))
    mu = np.exp(offset + X @ beta) if p > 0 else np.exp(offset)
    info = None
    if p > 0:
        w = mu / (1.0 + mu / phi)
        info = X.T @ (w[:, None] * X)      # expected information (paper, Sec. 3.1)
    at_boundary = best >= _LOG_PHI_MAX
    return NBFit(beta=beta, phi=phi, mu=mu, loglik=val, info=info,
                 phi_at_boundary=bool(at_boundary))
