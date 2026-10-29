# =============================================================================
# Main exported functions: testAdherence(), printResult(), htmlTable(),
# exportExcel(). Output strings are identical to the Python version.
# =============================================================================

.TEST_ORDER <- c("KS", "ChiSquare",
                 "WaldI_P", "WaldII_P", "LRTI_P", "LRTII_P", "BayesCI",
                 "WaldI_NB", "WaldII_NB", "LRTI_NB", "LRTII_NB")

.DESCRIPTIONS <- c(
  KS = "Kolmogorov-Smirnov",
  ChiSquare = "Chi-Square Goodness-of-Fit",
  WaldI_P = "Wald Type I (Poisson)",
  WaldII_P = "Wald Type II - age slope (Poisson)",
  LRTI_P = "LRT Type I (Poisson)",
  LRTII_P = "LRT Type II - age slope (Poisson)",
  BayesCI = "Bayesian Credible Interval",
  WaldI_NB = "Wald Type I (Negative Binomial)",
  WaldII_NB = "Wald Type II - age slope (Neg. Binomial)",
  LRTI_NB = "LRT Type I (Negative Binomial)",
  LRTII_NB = "LRT Type II - age slope (Neg. Binomial)")

.FAMILIES <- c(KS = "Non-parametric", ChiSquare = "Non-parametric",
               WaldI_P = "Poisson", WaldII_P = "Poisson", LRTI_P = "Poisson",
               LRTII_P = "Poisson", BayesCI = "Bayesian",
               WaldI_NB = "Negative Binomial", WaldII_NB = "Negative Binomial",
               LRTI_NB = "Negative Binomial", LRTII_NB = "Negative Binomial")

.H0 <- c(KS = "CDF match", ChiSquare = "Obs = Exp",
         WaldI_P = "beta1 = 0", WaldII_P = "(beta1,beta2) = 0",
         LRTI_P = "beta1 = 0", LRTII_P = "(beta1,beta2) = 0",
         BayesCI = "theta in CI",
         WaldI_NB = "beta1 = 0", WaldII_NB = "(beta1,beta2) = 0",
         LRTI_NB = "beta1 = 0", LRTII_NB = "(beta1,beta2) = 0")


#' Test the Adherence of a Mortality Table to Pension Fund Data
#'
#' Runs the 11 goodness-of-fit tests of de Melo, Graziadei & Targino (2026)
#' comparing the observed mortality of a pension fund with a reference
#' (fixed) mortality / annuity table.
#'
#' @param data \code{data.frame} with columns \code{age}, \code{exposed},
#'   \code{deaths} and, optionally, \code{year}, in \strong{long format}: one
#'   row per (year, age) cell, with the years stacked one below the other.
#'   Without a \code{year} column, repeated ages are treated as stacked years
#'   (additional cells). Years are never aggregated.
#' @param table Name of a built-in table (see \code{\link{listTables}()}) or a
#'   \code{data.frame} with columns \code{age} and \code{qx} (an external,
#'   loaded or deloaded table).
#' @param alpha Significance level (default 0.05).
#' @param verbose If \code{TRUE}, prints progress information.
#' @param quiet If \code{TRUE}, suppresses the informative messages (they are
#'   kept in \code{result$messages}).
#' @param skip_nb_if_no_overdispersion If \code{TRUE} (default) the Negative
#'   Binomial tests are skipped when the dispersion ratio is <= 1.
#' @param chisq_df Degrees of freedom of the chi-squared test: \code{"k-1"}
#'   (default; convention of practice, used in the paper) or \code{"k"}
#'   (correct reference distribution for a fixed table; paper Sec. 2.1).
#'
#' @return An object of class \code{adherence_result}, a list with:
#' \describe{
#'   \item{\code{summary}}{\code{data.frame}, one row per test: \code{test},
#'     \code{description}, \code{family}, \code{h0}, \code{df},
#'     \code{statistic}, \code{p_value}, \code{reject_h0} ("Yes", "No" or
#'     "N/A") and \code{note}.}
#'   \item{\code{details}}{Full output of each test (e.g. Bayesian CI bounds,
#'     estimated \eqn{\phi} of the NB models).}
#'   \item{\code{data_used}}{The cells analysed, with \code{qx} and
#'     \code{expected} = exposed x qx.}
#'   \item{\code{table_name}, \code{alpha}, \code{n_cells}, \code{n_ages},
#'     \code{n_years}}{Description of the analysis.}
#'   \item{\code{total_exposed}, \code{observed_deaths}, \code{expected_deaths}}{
#'     Totals (\eqn{D} and \eqn{Q}).}
#'   \item{\code{ae_ratio}}{\eqn{D/Q}, the version I deflator estimate.}
#'   \item{\code{dispersion_ratio}}{Pearson \eqn{\chi^2}/df of the
#'     intercept-only Poisson model.}
#'   \item{\code{min_detectable}}{Smallest deflators detectable with 80\% power
#'     by the version I tests (paper, eq. 17).}
#'   \item{\code{messages}}{Informative messages produced by the analysis.}
#' }
#'
#' @details
#' \strong{The 11 tests.}
#' \code{KS} is computed on the age margins (paper, eq. 2) with the 5\%
#' critical value of \code{sfsmisc::KSd}; note that the KS statistic is
#' invariant to the overall level of mortality (Sec. 3.6).
#' \code{ChiSquare} uses all cells (eq. 1).
#' Version I tests (\code{WaldI_P}, \code{LRTI_P}, \code{BayesCI},
#' \code{WaldI_NB}, \code{LRTI_NB}) test a constant deflator,
#' \eqn{H_0: \beta = 0}; version II tests (\code{WaldII_P}, \code{LRTII_P},
#' \code{WaldII_NB}, \code{LRTII_NB}) test a deflator linear in standardised
#' age, \eqn{H_0: \beta_1 = \beta_2 = 0}, with the joint \eqn{\chi^2_2}
#' statistic. Negative Binomial models estimate \eqn{\phi} jointly with
#' \eqn{\beta} (profile likelihood). For \code{BayesCI} the value in
#' \code{p_value} is the posterior tail probability \eqn{\pi} (eq. 10), not a
#' frequentist p-value.
#'
#' \strong{Samples without deaths (D = 0).} The Wald tests (versions I and II,
#' Poisson and Negative Binomial) are not applicable and are reported as
#' "N/A" (paper, Sec. 3.5). The LRT tests remain valid, with statistic 2Q.
#'
#' The same function, with the same results, is available in the Python
#' version of the package.
#'
#' @references de Melo, E.F.L., Graziadei, H. & Targino, R. (2026).
#'   Annuity Table Validation in Pension Funds: A Comparative Power Analysis
#'   of Goodness-of-Fit Tests. SSRN 6668699.
#'
#' @seealso \code{\link{listTables}}, \code{\link{loadTable}},
#'   \code{\link{loadFundData}}, \code{\link{printResult}},
#'   \code{\link{htmlTable}}, \code{\link{exportExcel}}
#'
#' @examples
#' set.seed(42)
#' ages <- 40:80
#' tab  <- loadTable("AT-2000m")
#' qx   <- tab$qx[match(ages, tab$age)]
#' fund <- do.call(rbind, lapply(2021:2023, function(y) {
#'   E <- round(rlnorm(length(ages), 5, 0.4))
#'   data.frame(year = y, age = ages, exposed = E, deaths = rpois(length(ages), E * qx))
#' }))
#' result <- testAdherence(fund, table = "AT-2000m")
#' result
#' result$summary
#'
#' # A deloaded table (10% lower mortality)
#' tab$qx <- tab$qx * 0.90
#' testAdherence(fund, table = tab, quiet = TRUE)
#'
#' # No deaths: Wald tests are reported as N/A
#' zero <- data.frame(age = 40:55, exposed = 800, deaths = 0)
#' testAdherence(zero, "AT-2000m", quiet = TRUE)
#' @export
testAdherence <- function(data, table, alpha = 0.05, verbose = FALSE, quiet = FALSE,
                          skip_nb_if_no_overdispersion = TRUE, chisq_df = "k-1") {
  msgs <- character(0)
  say <- function(txt) {
    msgs <<- c(msgs, txt)
    if (!quiet) message(txt)
  }

  # ---- validation ------------------------------------------------------------
  if (!is.data.frame(data)) stop("'data' must be a data.frame.")
  missing_cols <- setdiff(c("age", "exposed", "deaths"), names(data))
  if (length(missing_cols) > 0)
    stop(paste0("Missing column(s) in 'data': ", paste(missing_cols, collapse = ", "),
                "\nRequired columns: age, exposed, deaths",
                "\nOptional column : year (for multi-year data in long format)"))
  if (!(alpha > 0 && alpha < 1)) stop("'alpha' must be strictly between 0 and 1.")
  if (!chisq_df %in% c("k-1", "k")) stop("'chisq_df' must be 'k-1' or 'k'.")

  cols <- c("age", "exposed", "deaths", if ("year" %in% names(data)) "year")
  df <- as.data.frame(lapply(data[cols], function(v) suppressWarnings(as.numeric(v))))
  na_rows <- !stats::complete.cases(df)
  if (any(na_rows)) {
    df <- df[!na_rows, , drop = FALSE]
    say(sprintf("  [Data] %d row(s) with missing values removed.", sum(na_rows)))
  }
  if (any(df$exposed < 0)) stop("'exposed' cannot contain negative values.")
  if (any(df$deaths < 0)) stop("'deaths' cannot contain negative values.")
  if (any(abs(df$deaths - round(df$deaths)) > 1e-8))
    say("  [Data] 'deaths' contains non-integer values; they were rounded.")
  df$deaths <- round(df$deaths)
  df$age <- as.integer(df$age)

  # ---- data structure ----------------------------------------------------------
  has_year <- "year" %in% names(df)
  repeated <- anyDuplicated(df$age) > 0
  if (has_year) {
    n_years <- length(unique(df$year))
    say(sprintf(paste0("  [Data format] 'year' column detected: %d year(s). ",
                       "Each (year, age) row is an independent cell."), n_years))
    if (anyDuplicated(df[c("year", "age")]) > 0)
      say(paste0("  [Data format] WARNING: some (year, age) pairs appear more than ",
                 "once; each row is still treated as a separate cell."))
  } else if (repeated) {
    n_years <- max(table(df$age))
    say(sprintf(paste0("  [Data format] Repeated ages detected (up to %d rows per age) ",
                       "and no 'year' column: rows are treated as stacked years ",
                       "(independent cells). Tip: add a 'year' column."), n_years))
  } else {
    n_years <- 1L
    say(paste0("  [Data format] Single-year data (each age appears once). For several ",
               "years, stack them in long format, one row per (year, age)."))
  }

  # ---- table ---------------------------------------------------------------------
  if (is.character(table)) {
    if (length(table) != 1L) stop("'table' must be a single table name.")
    table_name <- table
    tab <- loadTable(table)
  } else if (is.data.frame(table)) {
    if (!all(c("age", "qx") %in% names(table)))
      stop("A custom 'table' must have columns 'age' and 'qx'.")
    table_name <- "Custom"
    tab <- data.frame(age = as.integer(table$age), qx = as.numeric(table$qx))
    if (any(tab$qx < 0 | tab$qx > 1, na.rm = TRUE))
      stop("Custom table: 'qx' must lie in [0, 1].")
    if (anyDuplicated(tab$age) > 0) stop("Custom table: each age must appear only once.")
  } else {
    stop("'table' must be a table name or a data.frame with 'age' and 'qx'.")
  }

  # ---- one row = one cell (no aggregation) -------------------------------------------
  lost <- sort(setdiff(unique(df$age), tab$age))
  if (length(lost) > 0)
    say(paste0("  [Data] Ages not found in the table were dropped: [",
               paste(lost, collapse = ", "), "]"))
  merged <- df
  merged$qx <- tab$qx[match(merged$age, tab$age)]
  merged <- merged[!is.na(merged$qx) & merged$exposed > 0 & merged$qx > 0, , drop = FALSE]
  ord <- if (has_year) order(merged$year, merged$age) else order(merged$age)
  merged <- merged[ord, , drop = FALSE]
  rownames(merged) <- NULL
  if (nrow(merged) < 3L)
    stop(paste0("Fewer than 3 valid cells after merging with the mortality table. ",
                "Check that the ages in 'data' overlap with the table."))

  d   <- merged$deaths
  E   <- merged$exposed
  x   <- merged$age
  mu0 <- E * merged$qx
  merged$expected <- mu0
  D <- sum(d); Q <- sum(mu0)

  ages <- sort(unique(x))
  s_x <- if (length(ages) > 1) stats::sd(ages) else 0
  g <- if (s_x > 0) (x - mean(ages)) / s_x else rep(0, length(x))

  d_age  <- as.numeric(tapply(d, x, sum)[as.character(ages)])
  mu_age <- as.numeric(tapply(mu0, x, sum)[as.character(ages)])

  if (verbose) {
    cat(sprintf("mortalityAdherence | Table: %s | %d cell(s) | %d unique age(s) | %d year(s)\n",
                table_name, nrow(merged), length(ages), as.integer(n_years)))
    cat(sprintf("  Exposed: %s | Observed: %.0f | Expected: %.1f | A/E: %.4f\n",
                formatC(sum(E), format = "f", digits = 0, big.mark = ","), D, Q, D / Q))
  }
  if (D == 0)
    say(paste0("  [Zero deaths] D = 0: Wald I and Wald II (Poisson and Negative ",
               "Binomial) are not applicable and are reported as N/A ",
               "(de Melo et al., 2026, Sec. 3.5). LRT tests remain valid."))

  # ---- the 11 tests ----------------------------------------------------------------
  res <- list()
  res$KS <- .test_ks(d_age, mu_age, alpha)
  res$ChiSquare <- .test_chisq(d, mu0, alpha, chisq_df)
  pois <- .poisson_family(d, mu0, g, alpha, d_age, mu_age)
  one_age <- "Only one age in the data: age slope not identifiable."
  if (s_x == 0) {
    pois$WaldII_P <- .na_test(one_age, 2)
    pois$LRTII_P  <- .na_test(one_age, 2)
  }
  res <- c(res, pois)

  disp <- .dispersion_ratio(d, mu0)
  skip <- NULL
  if (D > 0 && skip_nb_if_no_overdispersion && !isTRUE(disp > 1)) {
    say(sprintf(paste0("  [NB tests] No overdispersion detected (dispersion ratio = %.4f ",
                       "<= 1). Negative Binomial tests are not applicable and were skipped; ",
                       "the Poisson-based tests are appropriate for these data."), disp))
    skip <- "Skipped: no overdispersion (dispersion ratio <= 1)"
  }
  nb <- .nb_family(d, mu0, g, alpha, skip)
  if (s_x == 0 && is.null(skip)) {
    nb$WaldII_NB <- .na_test(one_age, 2)
    nb$LRTII_NB  <- .na_test(one_age, 2)
  }
  res <- c(res, nb)[.TEST_ORDER]

  # ---- summary ------------------------------------------------------------------------
  num <- function(nm, f) { v <- res[[nm]][[f]]; if (is.null(v)) NA_real_ else as.numeric(v) }
  rej <- vapply(.TEST_ORDER, function(nm) as.logical(res[[nm]]$reject), logical(1))
  summary_df <- data.frame(
    test        = .TEST_ORDER,
    description = unname(.DESCRIPTIONS[.TEST_ORDER]),
    family      = unname(.FAMILIES[.TEST_ORDER]),
    h0          = unname(.H0[.TEST_ORDER]),
    df          = vapply(.TEST_ORDER, num, numeric(1), f = "df"),
    statistic   = vapply(.TEST_ORDER, num, numeric(1), f = "statistic"),
    p_value     = vapply(.TEST_ORDER, num, numeric(1), f = "p_value"),
    reject_h0   = ifelse(is.na(rej), "N/A", ifelse(rej, "Yes", "No")),
    note        = vapply(.TEST_ORDER, function(nm) res[[nm]]$note, character(1)),
    stringsAsFactors = FALSE, row.names = NULL)

  # minimum detectable deflator, 80% power (paper, eq. 17)
  cc <- (stats::qnorm(1 - alpha / 2) + stats::qnorm(0.80)) / sqrt(Q)

  structure(list(
    summary = summary_df, details = res, data_used = merged,
    table_name = table_name, alpha = alpha, n_cells = nrow(merged),
    n_ages = length(ages), n_years = as.integer(n_years),
    total_exposed = sum(E), observed_deaths = D, expected_deaths = Q,
    ae_ratio = D / Q, dispersion_ratio = disp,
    min_detectable = c(exp(-cc), exp(cc)), messages = msgs),
    class = "adherence_result")
}


# =============================================================================
# Reporting
# =============================================================================

.fmt_stat <- function(v) if (is.na(v)) "--" else sprintf("%.4f", v)
.fmt_p <- function(v) if (is.na(v)) "--" else if (v < 1e-6) "<0.000001" else sprintf("%.6f", v)
.fmt_int <- function(v) formatC(v, format = "f", digits = 0, big.mark = ",")

.verdict <- function(x) {
  s <- x$summary
  n_rej <- sum(s$reject_h0 == "Yes")
  n_tot <- sum(s$reject_h0 %in% c("Yes", "No"))
  v <- if (n_rej == 0) "[OK] GOOD ADHERENCE: the table fits the fund data well."
       else if (n_rej <= 3) "[!!] PARTIAL ADHERENCE: some tests failed. Review critical age groups."
       else "[XX] POOR ADHERENCE: consider a different table or an adjustment factor."
  sprintf("%d of %d applicable tests reject H0 at the %.0f%% significance level.\n  %s",
          n_rej, n_tot, x$alpha * 100, v)
}

.format_result <- function(x, show_notes = TRUE) {
  W <- 100
  lo <- x$min_detectable[1]; hi <- x$min_detectable[2]
  L <- c("", strrep("=", W),
         "  mortalityAdherence :: Biometric Table Adherence Test",
         strrep("=", W),
         sprintf("  Mortality table    : %s", x$table_name),
         sprintf("  Significance level : %.1f%%", x$alpha * 100),
         sprintf("  Cells (rows)       : %d", x$n_cells),
         sprintf("  Unique ages        : %d", x$n_ages),
         sprintf("  Years              : %d", x$n_years),
         sprintf("  Total exposed      : %s", .fmt_int(x$total_exposed)),
         sprintf("  Observed deaths (D): %s", .fmt_int(x$observed_deaths)),
         sprintf("  Expected deaths (Q): %s",
                 formatC(x$expected_deaths, format = "f", digits = 2, big.mark = ",")),
         sprintf("  A/E ratio (D/Q)    : %.4f  (%+.1f%%)", x$ae_ratio, (x$ae_ratio - 1) * 100))
  if (!is.na(x$dispersion_ratio)) {
    tag <- if (x$dispersion_ratio <= 1) "no overdispersion, NB tests not applicable"
           else "overdispersion present, NB tests applied"
    L <- c(L, sprintf("  Dispersion ratio   : %.4f -- %s", x$dispersion_ratio, tag))
  }
  L <- c(L, sprintf("  Min. detectable    : theta < %.2f or theta > %.2f (80%% power, version I tests)",
                    lo, hi),
         strrep("-", W),
         sprintf("  %-11s  %-41s  %10s  %10s  Decision", "Test", "Description",
                 "Statistic", "P-value"),
         strrep("-", W))
  prev <- ""
  s <- x$summary
  for (i in seq_len(nrow(s))) {
    if (s$family[i] != prev) { L <- c(L, sprintf("  [ %s ]", s$family[i])); prev <- s$family[i] }
    dec <- switch(s$reject_h0[i], Yes = "[ REJECT ]", No = "[  pass  ]", "[  N/A   ]")
    L <- c(L, sprintf("  %-11s  %-41s  %10s  %10s  %s", s$test[i], s$description[i],
                      .fmt_stat(s$statistic[i]), .fmt_p(s$p_value[i]), dec))
    if (show_notes && nzchar(s$note[i])) L <- c(L, sprintf("  %-11s    -> %s", "", s$note[i]))
  }
  L <- c(L, strrep("=", W), paste0("  ", .verdict(x)))
  if (x$observed_deaths == 0)
    L <- c(L, "  Note: no deaths in the sample -- Wald tests are not applicable (paper, Sec. 3.5).")
  if (any(s$reject_h0 == "No"))
    L <- c(L, sprintf(paste0("  Note: a non-rejection only rules out deflators outside ",
                             "[%.2f, %.2f] (80%% power); smaller departures may go ",
                             "undetected (paper, eq. 17)."), lo, hi))
  L <- c(L, "  Reference: de Melo, Graziadei & Targino (2026), SSRN 6668699.", "")
  paste(L, collapse = "\n")
}


#' Print Adherence Test Results
#'
#' Prints the formatted report of an \code{adherence_result}: header with
#' \eqn{D}, \eqn{Q}, A/E ratio, dispersion ratio and minimum detectable
#' deflator, the 11 tests grouped by family, and the verdict.
#' \code{print(result)} does the same.
#'
#' @param x An \code{adherence_result} returned by \code{\link{testAdherence}()}.
#' @param show_notes Print the note under each test (default \code{TRUE}).
#' @param ... Not used.
#' @return \code{x}, invisibly.
#' @examples
#' zero <- data.frame(age = 40:55, exposed = 800, deaths = 0)
#' r <- testAdherence(zero, "AT-2000m", quiet = TRUE)
#' printResult(r, show_notes = FALSE)
#' @export
printResult <- function(x, show_notes = TRUE, ...) {
  if (!inherits(x, "adherence_result"))
    stop("'x' must be an 'adherence_result' returned by testAdherence().")
  cat(.format_result(x, show_notes = show_notes), "\n", sep = "")
  invisible(x)
}

#' @rdname printResult
#' @export
print.adherence_result <- function(x, ...) printResult(x, ...)


.esc <- function(s) {
  s <- gsub("&", "&amp;", s, fixed = TRUE)
  s <- gsub("<", "&lt;", s, fixed = TRUE)
  s <- gsub(">", "&gt;", s, fixed = TRUE)
  s <- gsub("\"", "&quot;", s, fixed = TRUE)
  gsub("'", "&#x27;", s, fixed = TRUE)
}

.CSS <- paste0("\n<style>\n",
  ".ma-wrap{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:1100px;color:#1d2433}\n",
  ".ma-wrap h2{font-size:1.15rem;margin:0 0 .4rem}\n",
  ".ma-meta{display:flex;flex-wrap:wrap;gap:.4rem 1.4rem;font-size:.85rem;color:#4a5468;margin:.2rem 0 .8rem}\n",
  ".ma-meta b{color:#1d2433}\n",
  ".ma-tab{border-collapse:collapse;width:100%;font-size:.85rem}\n",
  ".ma-tab th{background:#1f3a5f;color:#fff;text-align:left;padding:.45rem .6rem;font-weight:600}\n",
  ".ma-tab td{padding:.4rem .6rem;border-bottom:1px solid #e3e7ee;vertical-align:top}\n",
  ".ma-tab td.num{text-align:right;font-variant-numeric:tabular-nums}\n",
  ".ma-fam td{background:#f2f5f9;font-weight:600;color:#1f3a5f}\n",
  ".ma-rej td{background:#fdecec}.ma-rej td.dec{color:#b3261e;font-weight:700}\n",
  ".ma-ok td.dec{color:#1b7f3b;font-weight:700}\n",
  ".ma-na td{color:#8a93a4}\n",
  ".ma-note{font-size:.78rem;color:#6b7486}\n",
  ".ma-verdict{margin-top:.8rem;padding:.6rem .8rem;border-radius:6px;background:#eef3fa;font-size:.9rem}\n",
  ".ma-ref{font-size:.75rem;color:#6b7486;margin-top:.6rem}\n",
  "</style>\n")

.html_table <- function(x, full_page = TRUE) {
  lo <- x$min_detectable[1]; hi <- x$min_detectable[2]
  meta <- list(c("Table", x$table_name), c("alpha", sprintf("%.2f", x$alpha)),
               c("Cells", x$n_cells), c("Ages", x$n_ages), c("Years", x$n_years),
               c("Exposed", .fmt_int(x$total_exposed)),
               c("Observed D", .fmt_int(x$observed_deaths)),
               c("Expected Q", formatC(x$expected_deaths, format = "f", digits = 1, big.mark = ",")),
               c("A/E", sprintf("%.4f", x$ae_ratio)),
               c("Dispersion", if (is.na(x$dispersion_ratio)) "--" else sprintf("%.3f", x$dispersion_ratio)),
               c("Min. detectable", sprintf("&theta;&lt;%.2f or &gt;%.2f", lo, hi)))
  parts <- c(.CSS, '<div class="ma-wrap"><h2>Mortality table adherence tests</h2>',
             paste0('<div class="ma-meta">',
                    paste0(vapply(meta, function(m) sprintf("<span>%s: <b>%s</b></span>", m[1], m[2]),
                                  character(1)), collapse = ""), "</div>"),
             paste0('<table class="ma-tab"><thead><tr><th>Test</th><th>Description</th><th>H0</th>',
                    '<th>df</th><th>Statistic</th><th>P-value</th><th>Decision</th></tr></thead><tbody>'))
  prev <- ""
  s <- x$summary
  for (i in seq_len(nrow(s))) {
    if (s$family[i] != prev) {
      parts <- c(parts, sprintf('<tr class="ma-fam"><td colspan="7">%s</td></tr>', .esc(s$family[i])))
      prev <- s$family[i]
    }
    cls <- switch(s$reject_h0[i], Yes = "ma-rej", No = "ma-ok", "ma-na")
    dec <- switch(s$reject_h0[i], Yes = "REJECT", No = "Pass", "N/A")
    note <- if (nzchar(s$note[i])) sprintf('<div class="ma-note">%s</div>', .esc(s$note[i])) else ""
    dfv <- if (is.na(s$df[i])) "" else sprintf("%d", as.integer(s$df[i]))
    parts <- c(parts, paste0(
      sprintf('<tr class="%s"><td><b>%s</b></td><td>%s%s</td>', cls, .esc(s$test[i]),
              .esc(s$description[i]), note),
      sprintf('<td>%s</td><td class="num">%s</td>', .esc(s$h0[i]), dfv),
      sprintf('<td class="num">%s</td>', .fmt_stat(s$statistic[i])),
      sprintf('<td class="num">%s</td><td class="dec">%s</td></tr>', .esc(.fmt_p(s$p_value[i])), dec)))
  }
  parts <- c(parts, "</tbody></table>",
             sprintf('<div class="ma-verdict">%s</div>', gsub("\n", "<br>", .esc(.verdict(x)), fixed = TRUE)),
             paste0('<div class="ma-ref">de Melo, E.F.L., Graziadei, H. &amp; Targino, R. (2026). ',
                    'Annuity Table Validation in Pension Funds: A Comparative Power Analysis of ',
                    'Goodness-of-Fit Tests. SSRN 6668699.</div></div>'))
  body <- paste(parts, collapse = "\n")
  if (!full_page) return(body)
  paste0('<!doctype html><html><head><meta charset="utf-8">',
         '<meta name="viewport" content="width=device-width,initial-scale=1">',
         sprintf("<title>Adherence tests - %s</title></head>", .esc(x$table_name)),
         sprintf('<body style="margin:24px">%s</body></html>', body))
}


#' Styled HTML Table of the Results
#'
#' Builds a styled HTML table of the 11 tests (rejections in red, passes in
#' green), with the header metrics and the verdict. No extra packages needed.
#'
#' @param x An \code{adherence_result} returned by \code{\link{testAdherence}()}.
#' @param path Optional file path; if given, the full HTML page is written there.
#' @param full_page If \code{TRUE} (default) a complete HTML page is returned;
#'   if \code{FALSE}, only the table fragment.
#' @return The HTML as a character string (invisibly when \code{path} is given).
#'   Inside an R Markdown / Quarto document the table is rendered directly.
#' @examples
#' zero <- data.frame(age = 40:55, exposed = 800, deaths = 0)
#' r <- testAdherence(zero, "AT-2000m", quiet = TRUE)
#' f <- tempfile(fileext = ".html")
#' htmlTable(r, path = f)
#' @export
htmlTable <- function(x, path = NULL, full_page = TRUE) {
  if (!inherits(x, "adherence_result"))
    stop("'x' must be an 'adherence_result' returned by testAdherence().")
  if (isTRUE(getOption("knitr.in.progress")) && is.null(path) &&
      requireNamespace("htmltools", quietly = TRUE))
    return(htmltools::HTML(.html_table(x, full_page = FALSE)))
  out <- .html_table(x, full_page = full_page)
  if (!is.null(path)) {
    writeLines(out, path, useBytes = TRUE)
    return(invisible(out))
  }
  out
}


#' Export the Results to Excel
#'
#' Writes an \code{.xlsx} file with three sheets: \code{Tests} (the 11 tests),
#' \code{Overview} (totals, A/E, dispersion, minimum detectable deflator and
#' verdict) and \code{Data used} (the cells analysed). Requires the
#' \pkg{writexl} package (\code{install.packages("writexl")}).
#'
#' @param x An \code{adherence_result} returned by \code{\link{testAdherence}()}.
#' @param path Path of the \code{.xlsx} file to create.
#' @return \code{path}, invisibly.
#' @examples
#' \donttest{
#' if (requireNamespace("writexl", quietly = TRUE)) {
#'   zero <- data.frame(age = 40:55, exposed = 800, deaths = 0)
#'   r <- testAdherence(zero, "AT-2000m", quiet = TRUE)
#'   exportExcel(r, tempfile(fileext = ".xlsx"))
#' }
#' }
#' @export
exportExcel <- function(x, path) {
  if (!inherits(x, "adherence_result"))
    stop("'x' must be an 'adherence_result' returned by testAdherence().")
  if (!requireNamespace("writexl", quietly = TRUE))
    stop("Package 'writexl' is required: install.packages('writexl')")
  overview <- data.frame(
    item = c("Mortality table", "alpha", "Cells", "Unique ages", "Years",
             "Total exposed", "Observed deaths (D)", "Expected deaths (Q)",
             "A/E ratio (D/Q)", "Dispersion ratio",
             "Min. detectable theta (low)", "Min. detectable theta (high)", "Verdict"),
    value = c(x$table_name, x$alpha, x$n_cells, x$n_ages, x$n_years,
              x$total_exposed, x$observed_deaths, x$expected_deaths,
              x$ae_ratio, x$dispersion_ratio, x$min_detectable[1], x$min_detectable[2],
              gsub("\n  ", " ", .verdict(x), fixed = TRUE)),
    stringsAsFactors = FALSE)
  writexl::write_xlsx(list(Tests = x$summary, Overview = overview,
                           `Data used` = x$data_used), path)
  invisible(path)
}
