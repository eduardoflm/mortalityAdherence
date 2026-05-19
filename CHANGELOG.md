# Changelog

All notable changes to `mortalityAdherence` will be documented in this file.

The format follows [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
