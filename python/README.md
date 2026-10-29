# mortalityAdherence (Python)

> **Statistical Validation of Mortality/Annuity Tables for Pension Funds — Python version**

Python version of the R package [`mortalityAdherence`](https://github.com/eduardoflm/mortalityAdherence).
It implements the **11 goodness-of-fit tests** of de Melo, Graziadei & Targino (2026),
ships with **10 built-in mortality tables**, and produces formatted results (console,
HTML and Excel). The same function names as the R package are used.

[![Open In Colab](https://colab.research.google.com/assets/colab-badge.svg)](https://colab.research.google.com/github/eduardoflm/mortalityAdherence/blob/main/python/examples/quickstart.ipynb)

---

## Installation

```bash
pip install "mortalityAdherence @ https://github.com/eduardoflm/mortalityAdherence/archive/refs/heads/main.zip#subdirectory=python"
```

No Git is required. Requirements: Python ≥ 3.9 (numpy, scipy, pandas and openpyxl are
installed automatically). In Google Colab or Jupyter, prefix the command with `!`.

To read old `.xls` files, also run `pip install xlrd`.

---

## Quick start

```python
import mortalityAdherence as ma

# 1. Built-in tables
ma.listTables()

# 2. Pension fund data in LONG format: year, age, exposed, deaths
data = ma.loadFundData("experience.csv")
# Brazilian CSV:  ma.loadFundData("dados.csv", sep=";", dec=",",
#                     col_year="Ano", col_age="Idade",
#                     col_exposed="Expostos", col_deaths="Obitos")

# 3. Run the 11 tests
result = ma.testAdherence(data, table="AT-2000m", alpha=0.05)

# 4. Results
print(result)                     # formatted report
result.summary                    # DataFrame with the 11 tests
ma.exportExcel(result, "results.xlsx")   # Excel: tests, overview, data used
result.to_html("results.html")    # styled HTML table
```

### Data format (long / stacked)

One row per (year, age) cell. Several years are stacked one below the other:

| year | age | exposed | deaths |
|-----:|----:|--------:|-------:|
| 2020 | 40 | 400 | 1 |
| 2020 | 41 | 410 | 1 |
| … | … | … | … |
| 2021 | 40 | 390 | 1 |
| 2021 | 41 | 450 | 2 |

* With a single year, the `year` column is optional.
* Without a `year` column, repeated ages are treated as stacked years (extra cells).
* Years are **not** aggregated: each (year, age) cell enters the tests separately.

### External or adjusted tables

Any DataFrame with columns `age` and `qx` can be tested:

```python
tab = ma.loadTable("AT-2000m")
tab["qx"] = tab["qx"] * 0.90          # 10% deloaded table
result = ma.testAdherence(data, table=tab)

import pandas as pd
external = pd.read_csv("my_table.csv")  # columns: age, qx
result = ma.testAdherence(data, table=external)
```

---

## The 11 tests

| Family | Tests |
|---|---|
| Non-parametric | `KS`, `ChiSquare` |
| Poisson — version I (global deflator) | `WaldI_P`, `LRTI_P` (closed form) |
| Poisson — version II (deflator linear in age) | `WaldII_P`, `LRTII_P` |
| Bayesian (Gamma–Poisson, version I) | `BayesCI` |
| Negative Binomial (overdispersion) | `WaldI_NB`, `WaldII_NB`, `LRTI_NB`, `LRTII_NB` |

### Rules implemented from the paper

* **No deaths in the sample (D = 0):** the Wald tests (versions I and II, Poisson and
  Negative Binomial) are **not applicable** and are reported as `N/A`. The LRT tests
  remain valid (statistic = 2Q) (paper, Sec. 3.5).
* **No overdispersion:** when the dispersion ratio is ≤ 1 the Negative Binomial tests are
  skipped with a message (as in the R package; use `skip_nb_if_no_overdispersion=False`
  to run them anyway).
* **Minimum detectable deflator** (paper, eq. 17) is reported with every result, so a
  non-rejection can be read correctly: in a small fund, "the table fits" and "the fund is
  too small to tell" are different conclusions.
* **Chi-squared degrees of freedom:** `k-1` by default (convention of practice, used in the
  paper); `chisq_df="k"` gives the correct reference distribution for a fixed table
  (paper, Sec. 2.1).
* **KS** is computed on the age margins (paper, eq. 2), with the same 5% critical value as
  the R package (`sfsmisc::KSd`). Remember the paper's result: the KS statistic is invariant
  to the overall level of mortality and should not be used to assess it.
* **Bayesian CI:** empirical-Bayes Gamma prior by the method of moments on the
  age-specific ratios; the value in the `p_value` column is the posterior tail
  probability π (eq. 10), not a frequentist p-value.

---

## Functions

| Function | Description |
|---|---|
| `testAdherence(data, table, alpha=0.05)` | Runs the 11 tests, returns an `AdherenceResult` |
| `listTables()` | Catalogue of the 10 built-in tables |
| `loadTable(name)` | A built-in table as a DataFrame (`age`, `qx`) |
| `loadFundData(file, ...)` | Reads CSV / Excel fund data |
| `printResult(result)` | Formatted console report |
| `htmlTable(result, path=None)` | Styled HTML table |
| `exportExcel(result, path)` | Excel file: tests, overview, data used |
| `mortality_tables` | All 10 tables (ages 0–120) |

snake_case aliases are also available: `test_adherence`, `list_tables`, `load_table`,
`load_fund_data`, `print_result`, `html_table`, `export_excel`.

Built-in tables: AT-2000bm, AT-2000m, AT-49M, AT-55m, AT-83ms, GAM71m, GAM83m,
BR-EMS2010, BR-EMS2015, BR-EMS2021.

---

## Validation

* All statistics were checked against the R package and against R's `stats::glm` and
  `MASS::glm.nb` (Negative Binomial: φ̂, log-likelihood and test statistics agree to
  at least 5 significant digits). See `tests/`.
* `validation/reproduce_table1.py` reproduces Table 1 of the paper (empirical size).

Run the tests with `pip install pytest` and then `pytest` inside this folder.

---

## Citation

> de Melo, E.F.L., Graziadei, H. & Targino, R. (2026). *Annuity Table Validation in
> Pension Funds: A Comparative Power Analysis of Goodness-of-Fit Tests.* SSRN Working Paper.
> https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6668699

```bibtex
@article{deMelo2026,
  author = {de Melo, Eduardo Fraga L. and Graziadei, Helton and Targino, Rodrigo},
  title  = {Annuity Table Validation in Pension Funds: A Comparative Power
            Analysis of Goodness-of-Fit Tests},
  year   = {2026},
  note   = {SSRN Working Paper},
  url    = {https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6668699}
}
```

## License

MIT — see [LICENSE](LICENSE).
