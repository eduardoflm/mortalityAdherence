"""Main entry point: testAdherence()."""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Dict, List, Optional, Union

import numpy as np
import pandas as pd
from scipy import stats

from . import _tests as T
from ._tables import listTables, loadTable

TEST_ORDER = ["KS", "ChiSquare",
              "WaldI_P", "WaldII_P", "LRTI_P", "LRTII_P", "BayesCI",
              "WaldI_NB", "WaldII_NB", "LRTI_NB", "LRTII_NB"]

DESCRIPTIONS = {
    "KS": "Kolmogorov-Smirnov",
    "ChiSquare": "Chi-Square Goodness-of-Fit",
    "WaldI_P": "Wald Type I (Poisson)",
    "WaldII_P": "Wald Type II - age slope (Poisson)",
    "LRTI_P": "LRT Type I (Poisson)",
    "LRTII_P": "LRT Type II - age slope (Poisson)",
    "BayesCI": "Bayesian Credible Interval",
    "WaldI_NB": "Wald Type I (Negative Binomial)",
    "WaldII_NB": "Wald Type II - age slope (Neg. Binomial)",
    "LRTI_NB": "LRT Type I (Negative Binomial)",
    "LRTII_NB": "LRT Type II - age slope (Neg. Binomial)",
}
FAMILIES = {"KS": "Non-parametric", "ChiSquare": "Non-parametric",
            "WaldI_P": "Poisson", "WaldII_P": "Poisson", "LRTI_P": "Poisson",
            "LRTII_P": "Poisson", "BayesCI": "Bayesian",
            "WaldI_NB": "Negative Binomial", "WaldII_NB": "Negative Binomial",
            "LRTI_NB": "Negative Binomial", "LRTII_NB": "Negative Binomial"}
H0 = {"KS": "CDF match", "ChiSquare": "Obs = Exp",
      "WaldI_P": "beta1 = 0", "WaldII_P": "(beta1,beta2) = 0",
      "LRTI_P": "beta1 = 0", "LRTII_P": "(beta1,beta2) = 0",
      "BayesCI": "theta in CI",
      "WaldI_NB": "beta1 = 0", "WaldII_NB": "(beta1,beta2) = 0",
      "LRTI_NB": "beta1 = 0", "LRTII_NB": "(beta1,beta2) = 0"}


@dataclass
class AdherenceResult:
    """
    Result of testAdherence(). Main attributes:

    summary          DataFrame, one row per test (statistic, p_value, reject_h0, note)
    details          dict with the full output of each test
    data_used        cells actually analysed (after merging with the table)
    table_name, alpha, n_cells, n_ages, n_years
    total_exposed, observed_deaths (D), expected_deaths (Q)
    ae_ratio         D / Q  (= the version I deflator estimate theta-hat)
    dispersion_ratio Pearson chi2/df of the intercept-only Poisson model
    min_detectable   (theta_low, theta_high): smallest deflators detectable with
                     80% power by the version I tests (paper, eq. 17)
    messages         informative messages produced during the analysis

    Methods: print / str(), to_html(path=None), to_excel(path)
    """
    summary: pd.DataFrame
    details: Dict[str, dict]
    data_used: pd.DataFrame
    table_name: str
    alpha: float
    n_cells: int
    n_ages: int
    n_years: int
    total_exposed: float
    observed_deaths: float
    expected_deaths: float
    ae_ratio: float
    dispersion_ratio: float
    min_detectable: tuple
    messages: List[str] = field(default_factory=list)

    def __str__(self) -> str:  # console report
        from ._report import format_result
        return format_result(self)

    def __repr__(self) -> str:
        return self.__str__()

    def _repr_html_(self) -> str:  # Jupyter / Colab
        from ._report import html_table
        return html_table(self, full_page=False)

    def to_html(self, path: Optional[str] = None) -> str:
        """Styled HTML table (returned as text; also written to `path` if given)."""
        from ._report import html_table
        html = html_table(self, full_page=True)
        if path:
            with open(path, "w", encoding="utf-8") as fh:
                fh.write(html)
        return html

    def to_excel(self, path: str) -> None:
        """Write summary, header metrics and the data used to an .xlsx file."""
        from ._report import write_excel
        write_excel(self, path)


def _say(msgs: List[str], text: str, quiet: bool) -> None:
    msgs.append(text)
    if not quiet:
        print(text)


def testAdherence(data: pd.DataFrame,
                  table: Union[str, pd.DataFrame],
                  alpha: float = 0.05,
                  verbose: bool = False,
                  quiet: bool = False,
                  skip_nb_if_no_overdispersion: bool = True,
                  chisq_df: str = "k-1") -> AdherenceResult:
    """
    Run the 11 adherence tests of de Melo, Graziadei & Targino (2026).

    Parameters
    ----------
    data : DataFrame with columns age, exposed, deaths (and optionally year),
        in long format: one row per (year, age) cell. Several years must be
        stacked one below the other. Without a 'year' column, repeated ages are
        treated as additional cells (multi-year data).
    table : name of a built-in table (see listTables()) or a DataFrame with
        columns 'age' and 'qx' (external, loaded or deloaded table).
    alpha : significance level (default 0.05).
    verbose : print progress information.
    quiet : suppress all informative messages (they remain in result.messages).
    skip_nb_if_no_overdispersion : if True (default, as in the R package), the
        Negative Binomial tests are skipped when the dispersion ratio is <= 1.
    chisq_df : "k-1" (default; convention of practice, used in the paper) or
        "k" (correct reference distribution for a fixed table; paper Sec. 2.1).

    Returns
    -------
    AdherenceResult — print it, or use result.summary, result.to_excel(...),
    result.to_html(...).

    Rule for samples without deaths (paper, Sec. 3.5): when D = 0 the Wald
    tests (I and II, Poisson and Negative Binomial) are not applicable and are
    reported as N/A. The LRT tests remain valid (statistic = 2Q).
    """
    msgs: List[str] = []

    # ---- validation ----------------------------------------------------------
    if not isinstance(data, pd.DataFrame):
        raise TypeError("'data' must be a pandas DataFrame.")
    missing = [c for c in ("age", "exposed", "deaths") if c not in data.columns]
    if missing:
        raise KeyError("Missing column(s) in 'data': " + ", ".join(missing) +
                       "\nRequired columns: age, exposed, deaths"
                       "\nOptional column : year (for multi-year data in long format)")
    if not (0 < alpha < 1):
        raise ValueError("'alpha' must be strictly between 0 and 1.")
    if chisq_df not in ("k-1", "k"):
        raise ValueError("'chisq_df' must be 'k-1' or 'k'.")

    cols = ["age", "exposed", "deaths"] + (["year"] if "year" in data.columns else [])
    df = data[cols].copy()
    for c in cols:
        df[c] = pd.to_numeric(df[c], errors="coerce")
    n_na = int(df.isna().any(axis=1).sum())
    if n_na:
        df = df.dropna()
        _say(msgs, f"  [Data] {n_na} row(s) with missing values removed.", quiet)
    if (df["exposed"] < 0).any():
        raise ValueError("'exposed' cannot contain negative values.")
    if (df["deaths"] < 0).any():
        raise ValueError("'deaths' cannot contain negative values.")
    if not np.allclose(df["deaths"], np.round(df["deaths"])):
        _say(msgs, "  [Data] 'deaths' contains non-integer values; they were rounded.", quiet)
    df["deaths"] = np.round(df["deaths"])
    df["age"] = df["age"].astype(int)

    # ---- data structure (single year vs stacked years) ------------------------
    has_year = "year" in df.columns
    repeated = df["age"].duplicated().any()
    if has_year:
        n_years = int(df["year"].nunique())
        _say(msgs, f"  [Data format] 'year' column detected: {n_years} year(s). "
                   "Each (year, age) row is an independent cell.", quiet)
        if df.duplicated(["year", "age"]).any():
            _say(msgs, "  [Data format] WARNING: some (year, age) pairs appear more than "
                       "once; each row is still treated as a separate cell.", quiet)
    elif repeated:
        n_years = int(df["age"].value_counts().max())
        _say(msgs, f"  [Data format] Repeated ages detected (up to {n_years} rows per age) "
                   "and no 'year' column: rows are treated as stacked years "
                   "(independent cells). Tip: add a 'year' column.", quiet)
    else:
        n_years = 1
        _say(msgs, "  [Data format] Single-year data (each age appears once). For several "
                   "years, stack them in long format, one row per (year, age).", quiet)

    # ---- table ---------------------------------------------------------------
    if isinstance(table, str):
        table_name = table
        tab = loadTable(table)
    elif isinstance(table, pd.DataFrame):
        if not {"age", "qx"}.issubset(table.columns):
            raise KeyError("A custom 'table' must have columns 'age' and 'qx'.")
        table_name = "Custom"
        tab = table[["age", "qx"]].copy()
        tab["age"] = pd.to_numeric(tab["age"]).astype(int)
        tab["qx"] = pd.to_numeric(tab["qx"])
        if ((tab["qx"] < 0) | (tab["qx"] > 1)).any():
            raise ValueError("Custom table: 'qx' must lie in [0, 1].")
        if tab["age"].duplicated().any():
            raise ValueError("Custom table: each age must appear only once.")
    else:
        raise TypeError("'table' must be a table name or a DataFrame with 'age' and 'qx'.")

    # ---- merge: one row = one cell, no aggregation ------------------------------
    df["_row"] = np.arange(len(df))
    merged = df.merge(tab, on="age", how="inner").sort_values("_row")
    lost = sorted(set(df["age"]) - set(tab["age"]))
    if lost:
        _say(msgs, f"  [Data] Ages not found in the table were dropped: {lost}", quiet)
    merged = merged[(merged["exposed"] > 0) & (merged["qx"] > 0)]
    sort_cols = ["year", "age"] if has_year else ["age"]
    merged = merged.sort_values(sort_cols, kind="stable").drop(columns="_row").reset_index(drop=True)
    if len(merged) < 3:
        raise ValueError("Fewer than 3 valid cells after merging with the mortality table. "
                         "Check that the ages in 'data' overlap with the table.")

    d = merged["deaths"].to_numpy(float)
    E = merged["exposed"].to_numpy(float)
    q = merged["qx"].to_numpy(float)
    x = merged["age"].to_numpy(float)
    mu0 = E * q
    merged["expected"] = mu0
    D, Q = float(d.sum()), float(mu0.sum())

    ages = np.unique(x)
    s_x = float(np.std(ages, ddof=1)) if len(ages) > 1 else 0.0
    g = (x - ages.mean()) / s_x if s_x > 0 else np.zeros_like(x)

    by_age = merged.groupby("age", sort=True)[["deaths", "expected"]].sum()
    d_age = by_age["deaths"].to_numpy(float)
    mu_age = by_age["expected"].to_numpy(float)

    if verbose:
        print(f"mortalityAdherence | Table: {table_name} | {len(merged)} cell(s) | "
              f"{len(ages)} unique age(s) | {n_years} year(s)")
        print(f"  Exposed: {E.sum():,.0f} | Observed: {D:.0f} | Expected: {Q:.1f} | "
              f"A/E: {D / Q:.4f}")

    if D == 0:
        _say(msgs, "  [Zero deaths] D = 0: Wald I and Wald II (Poisson and Negative "
                   "Binomial) are not applicable and are reported as N/A "
                   "(de Melo et al., 2026, Sec. 3.5). LRT tests remain valid.", quiet)

    # ---- the 11 tests ------------------------------------------------------------
    res: Dict[str, dict] = {}
    res["KS"] = T.test_ks(d_age, mu_age, alpha)
    res["ChiSquare"] = T.test_chisq(d, mu0, alpha, chisq_df)
    if s_x > 0:
        res.update(T.poisson_family(d, mu0, g, alpha, d_age, mu_age))
    else:
        # one single age: version II not identifiable
        tmp = T.poisson_family(d, mu0, np.zeros_like(d), alpha, d_age, mu_age)
        tmp["WaldII_P"] = T._na("Only one age in the data: age slope not identifiable.", 2)
        tmp["LRTII_P"] = T._na("Only one age in the data: age slope not identifiable.", 2)
        res.update(tmp)

    disp = T.dispersion_ratio(d, mu0)
    skip = None
    if D > 0 and skip_nb_if_no_overdispersion and not (disp > 1):
        _say(msgs, f"  [NB tests] No overdispersion detected (dispersion ratio = {disp:.4f} "
                   "<= 1). Negative Binomial tests are not applicable and were skipped; "
                   "the Poisson-based tests are appropriate for these data.", quiet)
        skip = "Skipped: no overdispersion (dispersion ratio <= 1)"
    nb = T.nb_family(d, mu0, g if s_x > 0 else np.zeros_like(d), alpha, skip)
    if s_x == 0 and not skip:
        nb["WaldII_NB"] = T._na("Only one age in the data: age slope not identifiable.", 2)
        nb["LRTII_NB"] = T._na("Only one age in the data: age slope not identifiable.", 2)
    res.update(nb)

    # ---- summary table -----------------------------------------------------------
    rows = []
    for name in TEST_ORDER:
        r = res[name]
        rej = r["reject"]
        rows.append({
            "test": name,
            "description": DESCRIPTIONS[name],
            "family": FAMILIES[name],
            "h0": H0[name],
            "df": r.get("df"),
            "statistic": r["statistic"],
            "p_value": r["p_value"],
            "reject_h0": "N/A" if rej is None else ("Yes" if rej else "No"),
            "note": r.get("note", ""),
        })
    summary = pd.DataFrame(rows)

    # minimum detectable deflator, 80% power (paper, eq. 17)
    c = (stats.norm.ppf(1 - alpha / 2) + stats.norm.ppf(0.80)) / math.sqrt(Q)
    mdd = (math.exp(-c), math.exp(c))

    return AdherenceResult(
        summary=summary, details=res, data_used=merged, table_name=table_name,
        alpha=alpha, n_cells=len(merged), n_ages=len(ages), n_years=n_years,
        total_exposed=float(E.sum()), observed_deaths=D, expected_deaths=Q,
        ae_ratio=D / Q, dispersion_ratio=disp, min_detectable=mdd, messages=msgs)
