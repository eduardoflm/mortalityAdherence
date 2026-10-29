#' mortalityAdherence: Statistical Validation of Mortality/Annuity Tables for Pension Funds
#'
#' @description
#' Implements the 11 goodness-of-fit tests of de Melo, Graziadei & Targino
#' (2026), "Annuity Table Validation in Pension Funds: A Comparative Power
#' Analysis of Goodness-of-Fit Tests", SSRN 6668699
#' (\url{https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6668699}).
#'
#' \describe{
#'   \item{Non-parametric}{\code{KS}, \code{ChiSquare}}
#'   \item{Poisson, version I (global deflator)}{\code{WaldI_P}, \code{LRTI_P}}
#'   \item{Poisson, version II (deflator linear in age)}{\code{WaldII_P}, \code{LRTII_P}}
#'   \item{Bayesian (Gamma-Poisson, version I)}{\code{BayesCI}}
#'   \item{Negative Binomial}{\code{WaldI_NB}, \code{WaldII_NB}, \code{LRTI_NB}, \code{LRTII_NB}}
#' }
#'
#' @section Main workflow:
#' \enumerate{
#'   \item \code{\link{listTables}()} -- the 10 built-in mortality tables
#'   \item \code{\link{loadTable}()} -- one built-in table as \code{data.frame(age, qx)}
#'   \item \code{\link{loadFundData}()} -- read pension fund data from CSV/Excel
#'   \item \code{\link{testAdherence}()} -- run the 11 tests
#'   \item \code{print()}, \code{\link{htmlTable}()}, \code{\link{exportExcel}()} -- results
#' }
#'
#' The Python version of the package (same functions, same results) is in the
#' \code{python/} folder of the GitHub repository.
#'
#' @keywords internal
"_PACKAGE"


# =============================================================================
# Internal statistical routines. Notation follows the paper:
#   cells C = {(x,t): E_{x,t} > 0}, D = sum d, Q = sum E q,
#   g_x = (x - mean(ages)) / sd(ages), ages = distinct ages in the data.
# Every test returns list(reject, statistic, p_value, df, note);
# reject = NA means "not applicable" (N/A).
# The same algorithms are used in the Python version of the package.
# =============================================================================

.na_test <- function(note = "", df = NA_real_) {
  list(reject = NA, statistic = NA_real_, p_value = NA_real_, df = df, note = note)
}

.ZERO_DEATHS_WALD <- paste0(
  "No deaths in the sample (D = 0): Wald tests are not applicable ",
  "(de Melo et al., 2026, Sec. 3.5).")

.xlogy <- function(x, y) ifelse(x == 0, 0, x * log(y))


# ---- Kolmogorov-Smirnov -----------------------------------------------------

# Identical to sfsmisc::KSd(n): 5% critical value of the KS statistic
.ks_crit_005 <- function(n) {
  if (n > 80) return(1.358 / (sqrt(n) + 0.12 + 0.11 / sqrt(n)))
  stats::splinefun(c(1:9, 10, 15, 10 * 2:8),
                   c(.975, .84189, .70760, .62394, .56328,
                     .51926, .48342, .45427, .43001, .40925,
                     .33760, .29408, .24170, .21012,
                     .18841, .17231, .15975, .14960))(n)
}

# Upper tail of the Kolmogorov distribution, P(K > x)
.kolm_sf <- function(x) {
  if (x <= 0) return(1)
  k <- 1:100
  if (x < 1) {
    cdf <- sqrt(2 * pi) / x * sum(exp(-(2 * k - 1)^2 * pi^2 / (8 * x^2)))
    return(min(max(1 - cdf, 0), 1))
  }
  min(max(2 * sum((-1)^(k - 1) * exp(-2 * k^2 * x^2)), 0), 1)
}

.ks_crit <- function(n, alpha) {
  if (abs(alpha - 0.05) < 1e-12) return(.ks_crit_005(n))
  c_alpha <- stats::uniroot(function(z) .kolm_sf(z) - alpha, c(0.2, 10),
                            tol = 1e-12)$root
  c_alpha / (sqrt(n) + 0.12 + 0.11 / sqrt(n))
}

# KS on the age margins (paper, eq. 2)
.test_ks <- function(d_age, mu_age, alpha) {
  D <- sum(d_age)
  if (D <= 0) return(.na_test("No deaths in the sample: KS statistic undefined."))
  ks <- max(abs(cumsum(d_age) / D - cumsum(mu_age) / sum(mu_age)))
  crit <- .ks_crit(D, alpha)
  sqn <- sqrt(D)
  p_approx <- .kolm_sf(ks * (sqn + 0.12 + 0.11 / sqn))
  list(reject = ks > crit, statistic = ks, p_value = p_approx, df = NA_real_,
       critical = crit,
       note = sprintf("Critical value = %.4f (p-value approx.)", crit))
}


# ---- Chi-squared (paper, eq. 1) -----------------------------------------------

.test_chisq <- function(d, mu0, alpha, df_rule = "k-1") {
  k <- length(d)
  X2 <- sum((d - mu0)^2 / pmax(mu0, 1e-12))
  df <- if (df_rule == "k-1") k - 1 else k
  pv <- stats::pchisq(X2, df, lower.tail = FALSE)
  n_small <- sum(mu0 < 1)
  note <- sprintf("df = %d (%s)", as.integer(df), df_rule)
  if (n_small > 0)
    note <- paste0(note, sprintf("; %d of %d cells with expected deaths < 1", n_small, k))
  list(reject = pv < alpha, statistic = X2, p_value = pv, df = df, note = note)
}


# ---- Poisson GLM with offset (Newton-Raphson with step halving) ----------------

.pois_ll <- function(d, mu) sum(.xlogy(d, pmax(mu, 1e-300)) - mu - lgamma(d + 1))

.fit_pois <- function(d, off, X, maxit = 100, tol = 1e-10) {
  beta <- rep(0, ncol(X))
  D <- sum(d); Q <- sum(exp(off))
  if (D > 0 && all(X[, 1] == 1)) beta[1] <- log(D / Q)
  ll <- function(b) .pois_ll(d, exp(off + drop(X %*% b)))
  cur <- ll(beta)
  for (it in seq_len(maxit)) {
    mu <- exp(off + drop(X %*% beta))
    score <- drop(crossprod(X, d - mu))
    info <- crossprod(X, mu * X)
    step <- tryCatch(solve(info, score), error = function(e) NULL)
    if (is.null(step)) break
    t <- 1
    repeat {
      new <- beta + t * step; val <- ll(new)
      if (val >= cur - 1e-12 || t < 1e-8) break
      t <- t / 2
    }
    delta <- abs(val - cur); beta <- new; cur <- val
    if (delta < tol * (abs(cur) + tol)) break
  }
  mu <- exp(off + drop(X %*% beta))
  list(beta = beta, mu = mu, loglik = cur, info = crossprod(X, mu * X))
}


# ---- Negative Binomial (NB2) by profile likelihood -----------------------------

.nb_ll <- function(d, mu, phi) {
  mu <- pmax(mu, 1e-300)
  sum(lgamma(d + phi) - lgamma(phi) - lgamma(d + 1) +
        .xlogy(d, mu / (phi + mu)) + phi * log(phi / (phi + mu)))
}

.nb_beta_given_phi <- function(d, off, X, phi, beta0, maxit = 100, tol = 1e-11) {
  beta <- beta0
  ll <- function(b) .nb_ll(d, exp(off + drop(X %*% b)), phi)
  cur <- ll(beta)
  for (it in seq_len(maxit)) {
    mu <- exp(off + drop(X %*% beta))
    score <- drop(crossprod(X, (d - mu) / (1 + mu / phi)))
    h <- phi * mu * (d + phi) / (phi + mu)^2
    info <- crossprod(X, h * X)
    step <- tryCatch(solve(info, score), error = function(e) NULL)
    if (is.null(step)) break
    t <- 1
    repeat {
      new <- beta + t * step; val <- ll(new)
      if (val >= cur - 1e-12 || t < 1e-8) break
      t <- t / 2
    }
    delta <- abs(val - cur); beta <- new; cur <- val
    if (delta < tol * (abs(cur) + tol)) break
  }
  list(beta = beta, loglik = cur)
}

# Joint MLE of (beta, phi): beta profiled for each phi, then the profile
# log-likelihood is maximised over log(phi) (grid + Brent).
# X = NULL is the H0 model (beta = 0, only phi re-estimated; paper eq. 12).
.fit_nb <- function(d, off, X = NULL) {
  lo_b <- log(1e-6); hi_b <- log(1e10)
  p <- if (is.null(X)) 0L else ncol(X)
  start <- if (p > 0) .fit_pois(d, off, X)$beta else numeric(0)
  prof <- function(lphi) {
    phi <- exp(lphi)
    if (p == 0) list(beta = numeric(0), loglik = .nb_ll(d, exp(off), phi))
    else .nb_beta_given_phi(d, off, X, phi, start)
  }
  grid <- seq(lo_b, hi_b, length.out = 49)
  vals <- vapply(grid, function(g) prof(g)$loglik, numeric(1))
  i <- which.max(vals)
  lo <- grid[max(i - 1, 1)]; hi <- grid[min(i + 1, length(grid))]
  opt <- stats::optimize(function(g) -prof(g)$loglik, c(lo, hi), tol = 1e-9)
  best <- if (-opt$objective >= vals[i]) opt$minimum else grid[i]
  # The profile is flat as phi -> infinity (no overdispersion): report the
  # Poisson limit deterministically, at the upper bound phi = 1e10.
  if (best > log(1e8)) best <- hi_b
  fit <- prof(best)
  phi <- exp(best)
  mu <- if (p > 0) exp(off + drop(X %*% fit$beta)) else exp(off)
  info <- if (p > 0) crossprod(X, (mu / (1 + mu / phi)) * X) else NULL
  list(beta = fit$beta, phi = phi, mu = mu, loglik = fit$loglik, info = info,
       phi_at_boundary = best >= hi_b)
}


# ---- Poisson family + Bayesian CI ---------------------------------------------

.poisson_family <- function(d, mu0, g, alpha, d_age, mu_age) {
  D <- sum(d); Q <- sum(mu0)
  off <- log(pmax(mu0, 1e-300))
  out <- list()

  # Wald I (eq. 8): log(D/Q) sqrt(D); not applicable when D = 0 (Sec. 3.5)
  if (D == 0) {
    out$WaldI_P <- .na_test(.ZERO_DEATHS_WALD, 1)
  } else {
    W <- log(D / Q) * sqrt(D)
    pv <- 2 * stats::pnorm(abs(W), lower.tail = FALSE)
    out$WaldI_P <- list(reject = pv < alpha, statistic = W, p_value = pv, df = 1, note = "")
  }

  # LRT I (eq. 11); D = 0 gives 2Q
  lam1 <- max(2 * (if (D == 0) Q else D * log(D / Q) - (D - Q)), 0)
  pv <- stats::pchisq(lam1, 1, lower.tail = FALSE)
  out$LRTI_P <- list(reject = pv < alpha, statistic = lam1, p_value = pv, df = 1,
                     note = if (D == 0) "D = 0: statistic = 2Q" else "")

  # Version II (eqs. 13-14)
  if (D == 0) {
    out$WaldII_P <- .na_test(.ZERO_DEATHS_WALD, 2)
    pv <- stats::pchisq(2 * Q, 2, lower.tail = FALSE)
    out$LRTII_P <- list(reject = pv < alpha, statistic = 2 * Q, p_value = pv, df = 2,
                        note = "D = 0: statistic = 2Q")
  } else {
    fit <- .fit_pois(d, off, cbind(1, g))
    b <- fit$beta
    W2 <- drop(t(b) %*% fit$info %*% b)
    pv <- stats::pchisq(W2, 2, lower.tail = FALSE)
    out$WaldII_P <- list(reject = pv < alpha, statistic = W2, p_value = pv, df = 2,
                         note = "", beta = b)
    lam2 <- max(2 * (fit$loglik - .pois_ll(d, mu0)), 0)
    pv <- stats::pchisq(lam2, 2, lower.tail = FALSE)
    out$LRTII_P <- list(reject = pv < alpha, statistic = lam2, p_value = pv, df = 2,
                        note = "")
  }

  out$BayesCI <- .bayes_ci(d_age, mu_age, D, Q, alpha)
  out[c("WaldI_P", "WaldII_P", "LRTI_P", "LRTII_P", "BayesCI")]
}

# Empirical-Bayes Gamma prior from the age-specific ratios (Sec. 3.2, eq. 9).
# p_value = posterior tail probability pi (eq. 10), not a frequentist p-value.
.bayes_ci <- function(d_age, mu_age, D, Q, alpha) {
  th <- d_age / pmax(mu_age, 1e-300)
  m <- if (length(th) >= 2) mean(th) else 0
  v <- if (length(th) >= 2) stats::var(th) else 0
  note_prior <- ""
  if (m > 0 && v > 0) {
    a0 <- m^2 / v; b0 <- m / v
  } else {
    # degenerate sample (e.g. D = 0): near-noninformative reference prior,
    # which the empirical-Bayes prior tracks (paper, Sec. 3.2)
    a0 <- b0 <- 0.001
    note_prior <- "; degenerate sample: reference prior a0 = b0 = 0.001 used"
  }
  ap <- a0 + D; bp <- b0 + Q
  lo <- stats::qgamma(alpha / 2, ap, bp)
  hi <- stats::qgamma(1 - alpha / 2, ap, bp)
  pi_tail <- min(2 * min(stats::pgamma(1, ap, bp),
                         stats::pgamma(1, ap, bp, lower.tail = FALSE)), 1)
  list(reject = (lo > 1) || (hi < 1), statistic = NA_real_, p_value = pi_tail,
       df = NA_real_, ci_lower = lo, ci_upper = hi, a0 = a0, b0 = b0,
       note = paste0(sprintf("%d%% CI: [%.4f, %.4f]; posterior tail prob.",
                             as.integer(round(100 * (1 - alpha))), lo, hi), note_prior))
}


# ---- Negative Binomial family -----------------------------------------------

# Pearson chi2 / df of the intercept-only Poisson model
.dispersion_ratio <- function(d, mu0) {
  D <- sum(d); k <- length(d)
  if (D <= 0 || k < 2) return(NA_real_)
  mu_hat <- mu0 * D / sum(mu0)
  sum((d - mu_hat)^2 / mu_hat) / (k - 1)
}

.nb_family <- function(d, mu0, g, alpha, skip_reason = NULL) {
  nms <- c("WaldI_NB", "WaldII_NB", "LRTI_NB", "LRTII_NB")
  dfs <- c(1, 2, 1, 2)
  if (!is.null(skip_reason))
    return(stats::setNames(lapply(dfs, function(k) .na_test(skip_reason, k)), nms))

  D <- sum(d); Q <- sum(mu0)
  out <- list()
  if (D == 0) {   # phi-hat -> infinity: NB likelihood reduces to the Poisson one
    out$WaldI_NB  <- .na_test(.ZERO_DEATHS_WALD, 1)
    out$WaldII_NB <- .na_test(.ZERO_DEATHS_WALD, 2)
    for (k in 1:2) {
      pv <- stats::pchisq(2 * Q, k, lower.tail = FALSE)
      out[[c("LRTI_NB", "LRTII_NB")[k]]] <- list(
        reject = pv < alpha, statistic = 2 * Q, p_value = pv, df = k,
        note = "D = 0: phi -> inf, statistic = 2Q")
    }
    return(out[nms])
  }

  off <- log(pmax(mu0, 1e-300))
  f0 <- .fit_nb(d, off, NULL)
  f1 <- .fit_nb(d, off, matrix(1, length(d), 1))
  f2 <- .fit_nb(d, off, cbind(1, g))
  phi_note <- function(f) if (f$phi_at_boundary) "phi at boundary (Poisson limit)"
                          else sprintf("phi = %.2f", f$phi)

  z <- f1$beta[1] * sqrt(f1$info[1, 1])
  pv <- 2 * stats::pnorm(abs(z), lower.tail = FALSE)
  out$WaldI_NB <- list(reject = pv < alpha, statistic = z, p_value = pv, df = 1,
                       note = phi_note(f1), phi = f1$phi)

  W2 <- drop(t(f2$beta) %*% f2$info %*% f2$beta)
  pv <- stats::pchisq(W2, 2, lower.tail = FALSE)
  out$WaldII_NB <- list(reject = pv < alpha, statistic = W2, p_value = pv, df = 2,
                        note = phi_note(f2), phi = f2$phi, beta = f2$beta)

  lam <- max(2 * (f1$loglik - f0$loglik), 0)
  pv <- stats::pchisq(lam, 1, lower.tail = FALSE)
  out$LRTI_NB <- list(reject = pv < alpha, statistic = lam, p_value = pv, df = 1,
                      note = phi_note(f1))

  lam <- max(2 * (f2$loglik - f0$loglik), 0)
  pv <- stats::pchisq(lam, 2, lower.tail = FALSE)
  out$LRTII_NB <- list(reject = pv < alpha, statistic = lam, p_value = pv, df = 2,
                       note = phi_note(f2))
  out[nms]
}
