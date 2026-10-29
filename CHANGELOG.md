# Changelog

All notable changes to `mortalityAdherence` will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

---

## [0.2.0] — 2026-10-29

Aligned with the revised paper (de Melo, Graziadei & Targino, 2026, SSRN 6668699)
and with the Python version of the package, which now gives identical results.

### Fixed

- **Samples without deaths (D = 0):** Wald I and Wald II (Poisson and Negative
  Binomial) are now reported as `N/A`, as the paper prescribes (Sec. 3.5).
  Before, Wald I returned -Inf and rejected the table, and LRT I returned 0
  instead of 2Q.
- **KS with several years:** the statistic is now computed on the age margins
  (paper, eq. 2). Before, it accumulated the cells in (year, age) order, which
  could reject a correct table.
- **Bayesian CI with several years:** prior hyperparameters now come from the
  age-specific ratios (paper, eq. 9) instead of the cell ratios.
- **KS critical value** now follows `alpha`; for 5% it is still `sfsmisc::KSd`.
- **Negative Binomial fits** no longer fail when the estimated phi tends to
  infinity: phi is estimated by profile likelihood and the Poisson limit is
  reported explicitly.
- `print(result)` now shows the formatted report (the S3 method was not registered).
- Tests that are not applicable are reported as `N/A` instead of `Error`.

### Added

- Statistic of the Wald II tests (joint chi-squared with 2 df) in the summary.
- Posterior tail probability of the Bayesian CI (paper, eq. 10) in `p_value`.
- Minimum detectable deflator (paper, eq. 17) reported with every result.
- Arguments `quiet`, `skip_nb_if_no_overdispersion` and `chisq_df` ("k-1" or "k").
- `exportExcel()` (sheets Tests, Overview, Data used); `htmlTable(x, path)`.
- `result$messages`, `result$min_detectable`; full-precision statistics.
- Test suite comparing against `MASS::glm.nb` and against the Python version.

### Changed

- No mandatory dependencies besides base R: `MASS`, `car`, `sfsmisc` and
  `kableExtra` were removed from Imports. Installation is lighter and no longer
  asks to update dozens of packages.
- Built-in table descriptions: AT-2000bm is the AT-2000 *basic* table.
- The `df` column of the summary is numeric.

---

## [0.1.0] — 2026-05-18

### Added

- `testAdherence()` — runs all 11 statistical adherence tests against a
  biometric mortality table.
- `listTables()` — catalogue of 10 built-in mortality tables.
- `loadTable()` — retrieves any built-in table as a tidy `data.frame(age, qx)`.
- `loadFundData()` — reads CSV or Excel pension fund experience files.
- `printResult()` — formatted console output with grouped-by-family layout.
- `htmlTable()` — styled `kableExtra` HTML table for reports and Shiny.
- `mortality_tables` dataset — 10 tables, ages 0–120 (AT-2000bm, AT-2000m,
  AT-49M, AT-55m, AT-83ms, GAM71m, GAM83m, BR-EMS2010, BR-EMS2015, BR-EMS2021).
- Built-in vignette *Getting Started with mortalityAdherence*.
- GitHub Actions workflows for `R CMD CHECK` and `test-coverage`.
- Full `testthat` test suite covering data loading, test execution, and
  edge cases.
