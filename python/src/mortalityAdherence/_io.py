"""Reading pension-fund experience data from CSV or Excel files."""

from __future__ import annotations

import os
from typing import Optional, Union

import pandas as pd


def loadFundData(file: str,
                 col_year: Optional[str] = "year",
                 col_age: str = "age",
                 col_exposed: str = "exposed",
                 col_deaths: str = "deaths",
                 sep: str = ",",
                 dec: str = ".",
                 sheet: Union[int, str] = 0,
                 quiet: bool = False) -> pd.DataFrame:
    """
    Read pension-fund experience data from a .csv, .xlsx or .xls file.

    The data must be in LONG (stacked) format: one row per (year, age) cell.
    For several years, stack the years one below the other; do not spread
    years across columns.

        year  age  exposed  deaths
        2020   40      400       1
        2020   41      410       1
        2021   40      390       1
        2021   41      450       2

    With a single year the 'year' column is optional.

    Parameters
    ----------
    file : path to the file (.csv, .xlsx or .xls)
    col_year : name of the year column (None to ignore it)
    col_age, col_exposed, col_deaths : column names in the file
    sep, dec : CSV field and decimal separators. Brazilian CSV: sep=";", dec=","
    sheet : Excel sheet (index starting at 0, or name)
    quiet : suppress the summary message

    Returns
    -------
    DataFrame with columns [year,] age, exposed, deaths, ready for testAdherence().
    """
    if not os.path.exists(file):
        raise FileNotFoundError(f"File not found: '{file}'")
    ext = os.path.splitext(file)[1].lower()
    if ext == ".csv":
        raw = pd.read_csv(file, sep=sep, decimal=dec)
    elif ext in (".xlsx", ".xlsm", ".xls"):
        try:
            raw = pd.read_excel(file, sheet_name=sheet)
        except ImportError as e:  # pragma: no cover - depends on environment
            hint = "pip install xlrd" if ext == ".xls" else "pip install openpyxl"
            raise ImportError(f"Reading {ext} files needs an extra package: {hint}") from e
    else:
        raise ValueError(f"Unsupported file extension '{ext}'. Use .csv, .xlsx or .xls.")

    raw.columns = [str(c).strip() for c in raw.columns]
    for col in (col_age, col_exposed, col_deaths):
        if col not in raw.columns:
            raise KeyError(f"Column '{col}' not found. Available columns: "
                           f"{', '.join(raw.columns)}")

    has_year = col_year is not None and col_year in raw.columns
    out = pd.DataFrame({
        "age": pd.to_numeric(raw[col_age], errors="coerce"),
        "exposed": pd.to_numeric(raw[col_exposed], errors="coerce"),
        "deaths": pd.to_numeric(raw[col_deaths], errors="coerce"),
    })
    if has_year:
        out.insert(0, "year", pd.to_numeric(raw[col_year], errors="coerce"))

    n_before = len(out)
    out = out.dropna()
    out = out[out["exposed"] > 0].copy()
    n_removed = n_before - len(out)
    out["age"] = out["age"].astype(int)
    if has_year:
        out["year"] = out["year"].astype(int)
        out = out.sort_values(["year", "age"])
    else:
        out = out.sort_values("age")
    out = out.reset_index(drop=True)

    if not quiet:
        n_years = out["year"].nunique() if has_year else None
        msg = (f"Fund data loaded: {len(out)} row(s) | {out['age'].nunique()} unique age(s) | "
               f"{n_years if has_year else 'no year column'} year(s) | "
               f"{int(out['exposed'].sum()):,} exposed | {int(out['deaths'].sum())} deaths")
        if n_removed:
            msg += f" | {n_removed} row(s) removed (zero/missing exposure or missing values)"
        print(msg)
        if not has_year and out["age"].duplicated().any():
            print("  Repeated ages without a year column: each row will be treated as an "
                  "independent (year, age) cell.")
    return out
