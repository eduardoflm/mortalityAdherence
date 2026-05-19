#' mortalityAdherence: Biometric Table Adherence Testing for Pension Funds
#'
#' @description
#' The \pkg{mortalityAdherence} package provides actuaries with a complete
#' toolkit for testing whether a biometric mortality table is statistically
#' adherent to observed pension fund experience data.
#'
#' It implements 11 statistical tests organised in four families:
#'
#' \describe{
#'   \item{Non-parametric}{
#'     \code{KS} (Kolmogorov-Smirnov),
#'     \code{ChiSquare}
#'   }
#'   \item{Poisson — closed-form (Type I)}{
#'     \code{WaldI_P}, \code{LRTI_P}
#'   }
#'   \item{Poisson — GLM with age slope (Type II) + Bayesian}{
#'     \code{WaldII_P}, \code{LRTII_P}, \code{BayesCI}
#'   }
#'   \item{Negative Binomial (overdispersion-robust)}{
#'     \code{WaldI_NB}, \code{WaldII_NB}, \code{LRTI_NB}, \code{LRTII_NB}
#'   }
#' }
#'
#' @section Main workflow:
#' \enumerate{
#'   \item \code{\link{listTables}()} — view the 10 built-in mortality tables
#'   \item \code{\link{loadTable}()} — retrieve a built-in table as a data frame
#'   \item \code{\link{loadFundData}()} — import pension fund data from CSV/Excel
#'   \item \code{\link{testAdherence}()} — run all 11 tests
#'   \item \code{\link{printResult}()} — display a formatted summary
#'   \item \code{\link{htmlTable}()} — render an HTML table for reports/Shiny
#' }
#'
#' @section Built-in tables:
#' AT-2000bm, AT-2000m, AT-49M, AT-55m, AT-83ms,
#' GAM71m, GAM83m, BR-EMS2010, BR-EMS2015, BR-EMS2021.
#'
#' @docType package
#' @name mortalityAdherence-package
#' @aliases mortalityAdherence
"_PACKAGE"


# =============================================================================
# SECTION 1 — INTERNAL STATISTICAL TEST FUNCTIONS
# =============================================================================
# Naming convention: .test_*  for single-test functions
# All functions return a named list with fields:
#   reject     : logical (TRUE = reject H0)
#   statistic  : numeric test statistic (NA when not applicable)
#   p_value    : numeric p-value         (NA when not applicable)
#   ... extra fields depend on the test
# =============================================================================


# --- 1.1  Kolmogorov-Smirnov -------------------------------------------------

#' @noRd
.test_ks <- function(deaths, expected, alpha) {
  N <- sum(deaths)
  if (N <= 0L) {
    return(list(reject = NA, statistic = NA_real_, p_value = NA_real_,
                critical = NA_real_))
  }
  Q      <- sum(expected)
  px_cum <- cumsum(expected / Q)
  D_stat <- max(abs(cumsum(deaths) / N - px_cum))
  D_crit <- sfsmisc::KSd(n = N)
  list(
    reject    = D_stat > D_crit,
    statistic = round(D_stat, 6),
    p_value   = NA_real_,
    critical  = round(D_crit, 6)
  )
}


# --- 1.2  Chi-Square ---------------------------------------------------------

#' @noRd
.test_chisq <- function(deaths, expected, alpha) {
  X2 <- sum((deaths - expected)^2 / pmax(expected, 1e-12))
  df <- length(deaths) - 1L
  pv <- stats::pchisq(X2, df = df, lower.tail = FALSE)
  list(
    reject    = pv < alpha,
    statistic = round(X2, 4),
    p_value   = round(pv, 6),
    df        = df
  )
}


# --- 1.3  Poisson family (Wald I/II, LRT I/II, Bayesian CI) -----------------
# Type I (intercept only) uses closed-form expressions — no GLM needed.
# Type II (intercept + age slope) shares a single GLM fit for both Wald and LRT.

#' @noRd
.test_poisson_family <- function(deaths, log_offset, expected, z_age, alpha) {

  D <- sum(deaths)
  Q <- sum(expected)
  ctrl <- stats::glm.control(maxit = 50, epsilon = 1e-8)

  # ---- Wald Type I  (closed-form) ----------------------------------------
  beta_hat <- log(D / pmax(Q, 1e-12))
  se_hat   <- 1 / sqrt(pmax(D, 1))        # delta method: se(log D) = 1/sqrt(D)
  z_stat   <- beta_hat / se_hat
  pv_w1    <- 2 * stats::pnorm(abs(z_stat), lower.tail = FALSE)
  wald_I <- list(reject    = pv_w1 < alpha,
                 statistic = round(z_stat, 4),
                 p_value   = round(pv_w1, 6))

  # ---- LRT Type I  (closed-form) -----------------------------------------
  lrt1_stat <- if (D <= 0) 0 else
    max(2 * (D * log(pmax(D / Q, 1e-12)) - (D - Q)), 0)
  pv_l1 <- stats::pchisq(lrt1_stat, df = 1L, lower.tail = FALSE)
  lrt_I <- list(reject    = pv_l1 < alpha,
                statistic = round(lrt1_stat, 4),
                p_value   = round(pv_l1, 6))

  # ---- GLM Poisson — shared for Wald II and LRT II -----------------------
  fit_full <- tryCatch(
    stats::glm(deaths ~ z_age, offset = log_offset,
               family = stats::poisson, control = ctrl),
    error = function(e) NULL
  )
  fit_null <- tryCatch(
    stats::glm(deaths ~ 0,    offset = log_offset,
               family = stats::poisson, control = ctrl),
    error = function(e) NULL
  )

  # ---- Wald Type II  (GLM-based) -----------------------------------------
  pv_w2 <- tryCatch(
    car::linearHypothesis(
      fit_full,
      c("(Intercept) = 0", "z_age = 0")
    )$`Pr(>Chisq)`[2],
    error = function(e) NA_real_
  )
  wald_II <- list(reject    = !is.na(pv_w2) && pv_w2 < alpha,
                  statistic = NA_real_,
                  p_value   = round(pv_w2, 6))

  # ---- LRT Type II  (GLM-based) ------------------------------------------
  lrt2_stat <- if (!is.null(fit_null) && !is.null(fit_full))
    max(stats::deviance(fit_null) - stats::deviance(fit_full), 0)
  else NA_real_
  pv_l2 <- if (!is.na(lrt2_stat))
    stats::pchisq(lrt2_stat, df = 2L, lower.tail = FALSE)
  else NA_real_
  lrt_II <- list(reject    = !is.na(pv_l2) && pv_l2 < alpha,
                 statistic = round(lrt2_stat, 4),
                 p_value   = round(pv_l2, 6))

  # ---- Bayesian Credibility Interval  (Gamma-Poisson conjugate) ----------
  # Prior: moment-matched Gamma from per-age ratios d_x / mu_x
  theta   <- deaths / pmax(expected, 1e-12)
  m       <- mean(theta)
  v       <- stats::var(theta)
  alpha0  <- m^2 / pmax(v, 1e-12)
  beta0   <- m   / pmax(v, 1e-12)
  alpha_p <- alpha0 + D
  beta_p  <- beta0  + Q
  ci_lo   <- stats::qgamma(alpha / 2,       alpha_p, beta_p)
  ci_hi   <- stats::qgamma(1 - alpha / 2,   alpha_p, beta_p)
  bayes_ci <- list(reject    = (ci_lo > 1) | (ci_hi < 1),
                   statistic = NA_real_,
                   p_value   = NA_real_,
                   ci_lower  = round(ci_lo, 4),
                   ci_upper  = round(ci_hi, 4))

  list(WaldI_P  = wald_I,
       WaldII_P = wald_II,
       LRTI_P   = lrt_I,
       LRTII_P  = lrt_II,
       BayesCI  = bayes_ci)
}


# --- 1.4  Negative Binomial family (Wald I/II, LRT I/II) --------------------

#' @noRd
.test_nb_family <- function(deaths, log_offset, z_age, alpha) {

  na_res <- list(reject = NA, statistic = NA_real_, p_value = NA_real_)

  # --- Test for overdispersion before fitting NB models ---
  # Fit a Poisson GLM and compute the dispersion ratio: sum(pearson^2) / df
  # If dispersion <= 1, data are NOT overdispersed; NB is not appropriate.
  fit_pois <- tryCatch(
    stats::glm(deaths ~ 1 + offset(log_offset), family = stats::poisson),
    error = function(e) NULL
  )

  if (is.null(fit_pois)) {
    message("  [NB tests] Could not fit baseline Poisson model. NB tests skipped.")
    return(list(WaldI_NB  = na_res, WaldII_NB = na_res,
                LRTI_NB   = na_res, LRTII_NB  = na_res))
  }

  pearson_chi2 <- sum(stats::residuals(fit_pois, type = "pearson")^2)
  df_resid     <- stats::df.residual(fit_pois)
  dispersion   <- pearson_chi2 / df_resid

  if (dispersion <= 1) {
    message(sprintf(paste0(
      "  [NB tests] No overdispersion detected (dispersion ratio = %.4f <= 1.0).\n",
      "  Negative Binomial tests are not applicable and have been skipped.\n",
      "  The Poisson-based tests are appropriate for these data."
    ), dispersion))
    return(list(WaldI_NB  = na_res, WaldII_NB = na_res,
                LRTI_NB   = na_res, LRTII_NB  = na_res))
  }

  # Overdispersion confirmed — proceed with NB fitting
  ctrl <- stats::glm.control(maxit = 200, epsilon = 1e-7)

  fit0  <- tryCatch(MASS::glm.nb(deaths ~ 0 + offset(log_offset), control = ctrl),
                    error = function(e) NULL, warning = function(w) NULL)
  fit1a <- tryCatch(MASS::glm.nb(deaths ~ 1 + offset(log_offset), control = ctrl),
                    error = function(e) NULL, warning = function(w) NULL)
  fit1b <- tryCatch(MASS::glm.nb(deaths ~ z_age + offset(log_offset), control = ctrl),
                    error = function(e) NULL, warning = function(w) NULL)

  # ---- Wald Type I NB -----------------------------------------------------
  if (!is.null(fit1a)) {
    sm <- tryCatch(stats::coef(summary(fit1a))[1L, ], error = function(e) NULL)
    if (!is.null(sm) && !anyNA(sm[c("Estimate", "Std. Error")])) {
      z_val  <- sm["Estimate"] / sm["Std. Error"]
      pv     <- 2 * stats::pnorm(abs(z_val), lower.tail = FALSE)
      wald_I <- list(reject    = !is.na(pv) && pv < alpha,
                     statistic = round(as.numeric(z_val), 4),
                     p_value   = round(as.numeric(pv), 6))
    } else { wald_I <- na_res }
  } else { wald_I <- na_res }

  # ---- LRT Type I NB ------------------------------------------------------
  if (!is.null(fit0) && !is.null(fit1a)) {
    lam <- tryCatch(
      max(2 * (as.numeric(stats::logLik(fit1a)) - as.numeric(stats::logLik(fit0))), 0),
      error = function(e) NA_real_
    )
    if (!is.na(lam)) {
      pv    <- stats::pchisq(lam, df = 1L, lower.tail = FALSE)
      lrt_I <- list(reject = pv < alpha, statistic = round(lam, 4), p_value = round(pv, 6))
    } else { lrt_I <- na_res }
  } else { lrt_I <- na_res }

  # ---- Wald Type II NB ----------------------------------------------------
  if (!is.null(fit1b)) {
    pv <- tryCatch(
      car::linearHypothesis(fit1b, c("(Intercept) = 0", "z_age = 0"))$`Pr(>Chisq)`[2],
      error = function(e) NA_real_, warning = function(w) NA_real_
    )
    wald_II <- list(reject    = !is.na(pv) && pv < alpha,
                    statistic = NA_real_,
                    p_value   = round(as.numeric(pv), 6))
  } else { wald_II <- na_res }

  # ---- LRT Type II NB -----------------------------------------------------
  if (!is.null(fit0) && !is.null(fit1b)) {
    lam <- tryCatch(
      max(2 * (as.numeric(stats::logLik(fit1b)) - as.numeric(stats::logLik(fit0))), 0),
      error = function(e) NA_real_
    )
    if (!is.na(lam)) {
      pv     <- stats::pchisq(lam, df = 2L, lower.tail = FALSE)
      lrt_II <- list(reject = pv < alpha, statistic = round(lam, 4), p_value = round(pv, 6))
    } else { lrt_II <- na_res }
  } else { lrt_II <- na_res }

  list(WaldI_NB  = wald_I,
       WaldII_NB = wald_II,
       LRTI_NB   = lrt_I,
       LRTII_NB  = lrt_II)
}
