# =============================================================================
# SECTION 2 — MAIN EXPORTED FUNCTION: testAdherence()
# =============================================================================

#' Test the Adherence of a Mortality Table to Pension Fund Data
#'
#' Applies all 11 statistical adherence tests to observed pension fund
#' mortality data, comparing against a reference biometric table.
#'
#' @param data \code{data.frame} with the pension fund experience data.
#'   Required columns:
#'   \itemize{
#'     \item \code{age}      — participant age (integer)
#'     \item \code{exposed}  — number of lives exposed to the risk of death
#'     \item \code{deaths}   — number of observed deaths
#'   }
#' @param table Either a \code{character} string naming a built-in table
#'   (see \code{\link{listTables}()}), or a \code{data.frame} with columns
#'   \code{age} and \code{qx} (annual probability of death) for a custom table.
#' @param alpha \code{numeric} — significance level for all tests. Default: \code{0.05}.
#' @param verbose \code{logical} — if \code{TRUE}, prints progress messages.
#'   Default: \code{FALSE}.
#'
#' @return An object of class \code{adherence_result} (a named list) with:
#' \describe{
#'   \item{\code{$summary}}{A \code{data.frame} with one row per test showing
#'     the test name, family, test statistic, p-value, and rejection decision.}
#'   \item{\code{$details}}{Named list with the full output of each individual test.}
#'   \item{\code{$data_used}}{The merged data frame actually used in the analysis.}
#'   \item{\code{$table_name}}{Name of the mortality table tested against.}
#'   \item{\code{$alpha}}{Significance level used.}
#'   \item{\code{$n_ages}}{Number of age groups analysed.}
#'   \item{\code{$total_exposed}}{Total number of exposed lives.}
#'   \item{\code{$observed_deaths}}{Total number of observed deaths.}
#'   \item{\code{$expected_deaths}}{Total expected deaths under the tested table.}
#'   \item{\code{$ae_ratio}}{Actual-to-Expected (A/E) deaths ratio.}
#' }
#'
#' @details
#' \strong{The 11 tests:}
#' \describe{
#'   \item{\code{KS}}{Kolmogorov-Smirnov: compares the empirical cumulative
#'     distribution of observed deaths with the table-implied distribution.
#'     Uses the exact critical value from \code{sfsmisc::KSd()}.}
#'   \item{\code{ChiSquare}}{Chi-Square goodness-of-fit across all age groups.}
#'   \item{\code{WaldI_P}}{Wald Type I under Poisson: tests whether the overall
#'     log-scale adjustment \eqn{\beta_1 = 0}. Closed-form (no GLM required).}
#'   \item{\code{WaldII_P}}{Wald Type II under Poisson: jointly tests intercept
#'     and age-slope \eqn{(\beta_1, \beta_2) = (0,0)} via Poisson GLM.}
#'   \item{\code{LRTI_P}}{Likelihood Ratio Test Type I under Poisson.}
#'   \item{\code{LRTII_P}}{Likelihood Ratio Test Type II under Poisson GLM
#'     (2 degrees of freedom).}
#'   \item{\code{BayesCI}}{Bayesian Credibility Interval: Gamma-Poisson conjugate
#'     prior; rejects if the interval for the global adjustment factor excludes 1.}
#'   \item{\code{WaldI_NB}}{Wald Type I under Negative Binomial — robust to
#'     overdispersion.}
#'   \item{\code{WaldII_NB}}{Wald Type II under Negative Binomial.}
#'   \item{\code{LRTI_NB}}{Likelihood Ratio Test Type I under Negative Binomial.}
#'   \item{\code{LRTII_NB}}{Likelihood Ratio Test Type II under Negative Binomial.}
#' }
#'
#' Type I tests detect \emph{global} over- or under-estimation by the table.
#' Type II tests additionally detect \emph{age-systematic} deviations
#' (e.g. the table underestimates young-age mortality while overestimating
#' old-age mortality). Negative Binomial tests are particularly useful when
#' individual mortality events exhibit clustering or extra-Poisson variation.
#'
#' @seealso \code{\link{listTables}}, \code{\link{loadTable}},
#'   \code{\link{loadFundData}}, \code{\link{printResult}}, \code{\link{htmlTable}}
#'
#' @examples
#' # --- Simulate pension fund data ---
#' set.seed(42)
#' ages     <- 40:80
#' exposed  <- round(rlnorm(length(ages), meanlog = 5, sdlog = 0.4))
#' ref_qx   <- loadTable("AT-2000m")[loadTable("AT-2000m")$age %in% ages, "qx"]
#' obs_deaths <- rpois(length(ages), exposed * ref_qx)
#'
#' fund_data <- data.frame(age = ages, exposed = exposed, deaths = obs_deaths)
#'
#' # --- Test adherence ---
#' result <- testAdherence(fund_data, table = "AT-2000m", alpha = 0.05)
#' print(result)
#'
#' @export
testAdherence <- function(data, table, alpha = 0.05, verbose = FALSE) {

  # --- Input validation ---------------------------------------------------
  if (!is.data.frame(data))
    stop("'data' must be a data.frame.")

  required_cols <- c("age", "exposed", "deaths")
  missing_cols  <- setdiff(required_cols, names(data))
  if (length(missing_cols) > 0)
    stop(paste0(
      "Missing column(s) in 'data': ", paste(missing_cols, collapse = ", "),
      "\nRequired columns: age, exposed, deaths"
    ))

  if (any(data$exposed < 0, na.rm = TRUE))
    stop("'exposed' cannot contain negative values.")
  if (any(data$deaths  < 0, na.rm = TRUE))
    stop("'deaths' cannot contain negative values.")
  if (alpha <= 0 || alpha >= 1)
    stop("'alpha' must be strictly between 0 and 1.")

  # --- Load the mortality table -------------------------------------------
  table_name <- "Custom"
  if (is.character(table)) {
    if (length(table) != 1L)
      stop("'table' must be a single table name. Use listTables() to see options.")
    table_name <- table
    table_df   <- loadTable(table)
  } else if (is.data.frame(table)) {
    if (!all(c("age", "qx") %in% names(table)))
      stop("When 'table' is a data.frame it must have columns 'age' and 'qx'.")
    table_df <- table
  } else {
    stop("'table' must be a character name or a data.frame with columns 'age' and 'qx'.")
  }

  # --- Merge data with table ----------------------------------------------
  data$age      <- as.integer(data$age)
  table_df$age  <- as.integer(table_df$age)

  merged <- merge(data, table_df[, c("age", "qx")], by = "age", all.x = FALSE)
  merged <- merged[merged$exposed > 0, ]
  merged <- merged[order(merged$age), ]

  if (nrow(merged) < 3L)
    stop(paste0(
      "Fewer than 3 valid age groups after merging with the mortality table. ",
      "Check that the ages in 'data' overlap with the table's age range."
    ))

  # --- Prepare variables --------------------------------------------------
  deaths   <- as.integer(merged$deaths)
  exposed  <- merged$exposed
  qx       <- merged$qx
  expected <- exposed * qx                              # mu_x = E_x * q_x
  total_E  <- sum(expected)
  log_off  <- log(pmax(expected, 1e-12))
  ages     <- merged$age
  z_age    <- as.numeric(scale(ages))                   # standardised age covariate

  if (verbose) {
    cat(sprintf(
      "mortalityAdherence | Table: %s | Ages: %d-%d | Exposed: %d | ",
      table_name, min(ages), max(ages), as.integer(sum(exposed))
    ))
    cat(sprintf("Observed: %d | Expected: %.1f | A/E: %.4f\n",
                sum(deaths), total_E, sum(deaths) / pmax(total_E, 1e-12)))
    cat("  Running non-parametric tests...\n")
  }

  # --- Run all 11 tests ---------------------------------------------------
  res_ks    <- .test_ks(deaths, expected, alpha)
  res_chisq <- .test_chisq(deaths, expected, alpha)

  if (verbose) cat("  Running Poisson family tests...\n")
  res_pois  <- .test_poisson_family(deaths, log_off, expected, z_age, alpha)

  if (verbose) cat("  Running Negative Binomial family tests...\n")
  res_nb    <- .test_nb_family(deaths, log_off, z_age, alpha)

  # Compute dispersion ratio for reporting (Pearson chi2 / df under Poisson)
  fit_pois_disp <- tryCatch(
    stats::glm(deaths ~ 1 + offset(log_off), family = stats::poisson),
    error = function(e) NULL
  )
  dispersion_ratio <- if (!is.null(fit_pois_disp))
    round(sum(stats::residuals(fit_pois_disp, type = "pearson")^2) /
          stats::df.residual(fit_pois_disp), 4)
  else NA_real_

  # --- Assemble results ---------------------------------------------------
  all_tests <- c(
    list(KS = res_ks, ChiSquare = res_chisq),
    res_pois,
    res_nb
  )

  TEST_NAMES <- c(
    "KS", "ChiSquare",
    "WaldI_P", "WaldII_P", "LRTI_P", "LRTII_P", "BayesCI",
    "WaldI_NB", "WaldII_NB", "LRTI_NB", "LRTII_NB"
  )
  DESCRIPTIONS <- c(
    "Kolmogorov-Smirnov",
    "Chi-Square Goodness-of-Fit",
    "Wald Type I (Poisson)",
    "Wald Type II — age slope (Poisson)",
    "LRT Type I (Poisson)",
    "LRT Type II — age slope (Poisson)",
    "Bayesian Credibility Interval",
    "Wald Type I (Negative Binomial)",
    "Wald Type II — age slope (Neg. Binomial)",
    "LRT Type I (Negative Binomial)",
    "LRT Type II — age slope (Neg. Binomial)"
  )
  FAMILIES <- c(
    "Non-parametric", "Non-parametric",
    "Poisson", "Poisson", "Poisson", "Poisson", "Bayesian",
    "Negative Binomial", "Negative Binomial",
    "Negative Binomial", "Negative Binomial"
  )
  H0_LABELS <- c(
    "CDF match",  "Obs = Exp",
    "beta1 = 0", "(beta1,beta2) = 0",
    "beta1 = 0", "(beta1,beta2) = 0",
    "theta in CI",
    "beta1 = 0", "(beta1,beta2) = 0",
    "beta1 = 0", "(beta1,beta2) = 0"
  )
  DF_LABELS <- c(NA, "n-1", "1", "2", "1", "2", NA, "1", "2", "1", "2")

  reject_vec <- sapply(TEST_NAMES, function(nm) {
    r <- all_tests[[nm]]$reject
    if (is.null(r) || length(r) == 0) return(NA)
    as.logical(r)
  })
  stat_vec <- sapply(TEST_NAMES, function(nm) all_tests[[nm]]$statistic)
  pval_vec <- sapply(TEST_NAMES, function(nm) {
    pv <- all_tests[[nm]]$p_value
    if (is.null(pv)) NA_real_ else pv
  })

  # Build notes column (KS critical value, BayesCI interval)
  notes <- rep(NA_character_, length(TEST_NAMES))
  notes[TEST_NAMES == "KS"] <- sprintf(
    "Critical value = %.4f", res_ks$critical)
  notes[TEST_NAMES == "BayesCI"] <- sprintf(
    "95%% CI: [%.4f, %.4f]",
    all_tests$BayesCI$ci_lower, all_tests$BayesCI$ci_upper)

  summary_df <- data.frame(
    test        = TEST_NAMES,
    description = DESCRIPTIONS,
    family      = FAMILIES,
    h0          = H0_LABELS,
    df          = DF_LABELS,
    statistic   = round(stat_vec, 4),
    p_value     = round(pval_vec, 6),
    reject_h0   = ifelse(is.na(reject_vec), "Error",
                         ifelse(reject_vec, "Yes", "No")),
    note        = notes,
    stringsAsFactors = FALSE
  )

  result <- list(
    summary          = summary_df,
    details          = all_tests,
    data_used        = merged,
    table_name       = table_name,
    alpha            = alpha,
    n_ages           = nrow(merged),
    total_exposed    = as.integer(sum(exposed)),
    observed_deaths  = sum(deaths),
    expected_deaths  = round(total_E, 2),
    ae_ratio         = round(sum(deaths) / pmax(total_E, 1e-12), 4),
    dispersion_ratio = dispersion_ratio
  )
  class(result) <- "adherence_result"
  result
}


# =============================================================================
# SECTION 3 — PRINT / DISPLAY
# =============================================================================

#' Print Adherence Test Results
#'
#' Displays a formatted summary of all 11 statistical tests to the console.
#'
#' @param x An object of class \code{adherence_result} returned by
#'   \code{\link{testAdherence}()}.
#' @param show_notes \code{logical} — whether to print additional notes
#'   (KS critical value, Bayesian CI bounds). Default: \code{TRUE}.
#' @param ... Currently unused.
#'
#' @return Invisibly returns \code{x}.
#'
#' @examples
#' \dontrun{
#' result <- testAdherence(fund_data, table = "AT-2000m")
#' printResult(result)
#' }
#'
#' @export
printResult <- function(x, show_notes = TRUE, ...) {
  if (!inherits(x, "adherence_result"))
    stop("'x' must be an 'adherence_result' object returned by testAdherence().")

  w <- 72L  # console width

  # --- Header block -------------------------------------------------------
  cat("\n", strrep("=", w), "\n", sep = "")
  cat("  mortalityAdherence :: Biometric Table Adherence Test\n")
  cat(strrep("=", w), "\n", sep = "")
  cat(sprintf("  Mortality table   : %s\n",   x$table_name))
  cat(sprintf("  Significance level: %.1f%%\n", x$alpha * 100))
  cat(sprintf("  Age groups        : %d\n",   x$n_ages))
  cat(sprintf("  Total exposed     : %s\n",
              format(x$total_exposed,   big.mark = ",")))
  cat(sprintf("  Observed deaths   : %s\n",
              format(x$observed_deaths, big.mark = ",")))
  cat(sprintf("  Expected deaths   : %.2f\n", x$expected_deaths))
  cat(sprintf("  A/E ratio         : %.4f  (%+.1f%%)\n",
              x$ae_ratio, (x$ae_ratio - 1) * 100))
  if (!is.null(x$dispersion_ratio) && !is.na(x$dispersion_ratio)) {
    nb_note <- if (x$dispersion_ratio <= 1)
      sprintf("%.4f -- no overdispersion, NB tests not applicable", x$dispersion_ratio)
    else
      sprintf("%.4f -- overdispersion present, NB tests applied", x$dispersion_ratio)
    cat(sprintf("  Dispersion ratio  : %s\n", nb_note))
  }
  cat(strrep("-", w), "\n", sep = "")

  # --- Results table ------------------------------------------------------
  df <- x$summary

  # Format columns for display
  stat_fmt <- ifelse(is.na(df$statistic), "      --",
                     sprintf("%8.4f", df$statistic))
  pval_fmt <- ifelse(is.na(df$p_value),  "   --    ",
                     sprintf("%.6f", df$p_value))
  dec_fmt  <- ifelse(df$reject_h0 == "Yes",   "[ REJECT ]",
              ifelse(df$reject_h0 == "No",    "[  pass  ]",
                                              "[   N/A  ]"))

  # Group separator tracking
  prev_family <- ""
  cat(sprintf("\n  %-11s  %-40s  %8s  %9s  %s\n",
              "Test", "Description", "Statistic", "P-value", "Decision"))
  cat(strrep("-", w), "\n", sep = "")

  for (i in seq_len(nrow(df))) {
    fam <- df$family[i]
    if (fam != prev_family) {
      cat(sprintf("  [ %s ]\n", fam))
      prev_family <- fam
    }
    note_str <- if (show_notes && !is.na(df$note[i]))
      sprintf("    -> %s", df$note[i]) else ""
    cat(sprintf("  %-11s  %-40s  %s  %s  %s%s\n",
                df$test[i], df$description[i],
                stat_fmt[i], pval_fmt[i], dec_fmt[i], note_str))
  }

  cat(strrep("=", w), "\n", sep = "")

  # --- Verdict block ------------------------------------------------------
  n_rej <- sum(df$reject_h0 == "Yes", na.rm = TRUE)
  n_tot <- sum(df$reject_h0 %in% c("Yes", "No"), na.rm = TRUE)
  cat(sprintf(
    "\n  %d of %d tests reject H0 at the %.0f%% significance level.\n",
    n_rej, n_tot, x$alpha * 100
  ))
  verdict <- ifelse(n_rej == 0L,
    "  [OK] GOOD ADHERENCE: the table fits the fund data well.",
    ifelse(n_rej <= 3L,
    "  [!!] PARTIAL ADHERENCE: some tests failed. Review critical age groups.",
    "  [XX] POOR ADHERENCE: consider a different table or an adjustment factor."
  ))
  cat(verdict, "\n\n", sep = "")

  invisible(x)
}


#' @export
print.adherence_result <- function(x, ...) {
  printResult(x, ...)
}


#' Render an HTML Table of Adherence Test Results
#'
#' Produces a styled HTML table suitable for R Markdown reports and Shiny apps.
#' Rows that reject H\eqn{_0} are highlighted in red; rows that pass are
#' highlighted in green.
#'
#' @param x An object of class \code{adherence_result} returned by
#'   \code{\link{testAdherence}()}.
#' @param ... Additional arguments passed to \code{kableExtra::kable_styling()}.
#'
#' @return A \code{knitr_kable} object (HTML table ready for rendering).
#'
#' @details
#' Requires the packages \pkg{knitr} and \pkg{kableExtra}. Install them with:
#' \code{install.packages(c("knitr", "kableExtra"))}.
#'
#' @examples
#' \dontrun{
#' result <- testAdherence(fund_data, table = "AT-2000m")
#' htmlTable(result)   # inside an R Markdown chunk
#' }
#'
#' @export
htmlTable <- function(x, ...) {
  if (!inherits(x, "adherence_result"))
    stop("'x' must be an 'adherence_result' object returned by testAdherence().")
  if (!requireNamespace("knitr",      quietly = TRUE) ||
      !requireNamespace("kableExtra", quietly = TRUE))
    stop("Please install: install.packages(c('knitr', 'kableExtra'))")

  df <- x$summary
  out <- data.frame(
    Test        = df$test,
    Description = df$description,
    Family      = df$family,
    H0          = df$h0,
    df          = df$df,
    Statistic   = ifelse(is.na(df$statistic), "--",
                         sprintf("%.4f", df$statistic)),
    P.value     = ifelse(is.na(df$p_value),  "--",
                         sprintf("%.6f", df$p_value)),
    Decision    = ifelse(df$reject_h0 == "Yes", "[REJECT]",
                  ifelse(df$reject_h0 == "No",  "[ pass ]", "[ Error]")),
    Note        = ifelse(is.na(df$note), "", df$note),
    check.names = FALSE,
    stringsAsFactors = FALSE
  )

  caption <- sprintf(
    paste0("Adherence Tests -- Table: <strong>%s</strong> ",
           "| alpha = %.2f | Ages: %d",
           " | Exposed: %s | Observed: %d | Expected: %.1f | A/E: %.4f"),
    x$table_name, x$alpha, x$n_ages,
    format(x$total_exposed, big.mark = ","),
    x$observed_deaths, x$expected_deaths, x$ae_ratio
  )

  reject_rows <- which(df$reject_h0 == "Yes")
  pass_rows   <- which(df$reject_h0 == "No")

  tab <- knitr::kable(
    out, format = "html",
    align   = c("l", "l", "l", "l", "c", "r", "r", "c", "l"),
    caption = caption,
    escape  = FALSE
  )
  tab <- kableExtra::kable_styling(
    tab,
    bootstrap_options = c("striped", "hover", "condensed", "bordered"),
    full_width = TRUE, ...
  )
  if (length(reject_rows) > 0)
    tab <- kableExtra::row_spec(tab, reject_rows,
                                background = "#fde8e8", bold = TRUE,
                                color = "#b71c1c")
  if (length(pass_rows)   > 0)
    tab <- kableExtra::row_spec(tab, pass_rows,
                                background = "#e8f5e9", color = "#1b5e20")
  tab <- kableExtra::column_spec(tab, 8, bold = TRUE)
  tab
}
