# Changelog — mortalityAdherence (Python)

## 0.2.0 — 2026-10-29

Version numbers of the R and Python packages are now kept in sync.

- `exportExcel(result, path)` function (same name as in the R package).
- Negative Binomial: when phi-hat tends to infinity (no overdispersion) the Poisson
  limit is reported deterministically ("phi at boundary").
- `df` column of the summary is an integer column.
- AT-2000bm described as the AT-2000 basic table.

## 0.1.0 — 2026-10-29

First Python release, mirroring the R package `mortalityAdherence`.

- `testAdherence()`, `listTables()`, `loadTable()`, `loadFundData()`, `printResult()`,
  `htmlTable()` and the `mortality_tables` dataset (10 tables, ages 0-120).
- 11 tests: KS, Chi-Square, Wald I/II and LRT I/II under Poisson and Negative Binomial
  likelihoods, and the Gamma-Poisson Bayesian credible interval.
- Rule for samples without deaths (D = 0): Wald tests (Poisson and NB) reported as N/A;
  LRT tests use the limit statistic 2Q.
- Minimum detectable deflator (paper, eq. 17) reported with every result.
- Option `chisq_df = "k-1"` (default) or `"k"`.
- Results export to Excel (`result.to_excel`) and HTML (`result.to_html`).
- Validated against R (stats::glm, MASS::glm.nb, sfsmisc::KSd) and against Table 1 of the paper.
