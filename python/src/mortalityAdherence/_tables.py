"""Built-in mortality tables and table loading."""

from __future__ import annotations

from importlib import resources

import pandas as pd

_CATALOGUE = pd.DataFrame({
    "name": ["AT-2000bm", "AT-2000m", "AT-49M", "AT-55m", "AT-83ms",
             "GAM71m", "GAM83m", "BR-EMS2010", "BR-EMS2015", "BR-EMS2021"],
    "description": [
        "American Table 2000 - Male Beneficiaries (SOA)",
        "American Table 2000 - Male (SOA)",
        "American Table 1949 - Male",
        "American Table 1955 - Male",
        "American Table 1983 - Male (smoothed)",
        "Group Annuity Mortality 1971 - Male (SOA)",
        "Group Annuity Mortality 1983 - Male (SOA)",
        "Brazilian Mortality Experience 2010 (BR-EMS)",
        "Brazilian Mortality Experience 2015 (BR-EMS)",
        "Brazilian Mortality Experience 2021 (BR-EMS)",
    ],
    "origin": ["USA - Society of Actuaries"] * 7 + ["Brazil - SUSEP / insurance market"] * 3,
    "age_range": ["0 - 120"] * 10,
})


def _read_builtin() -> pd.DataFrame:
    with resources.files("mortalityAdherence").joinpath(
            "data/mortality_tables.csv").open("r", encoding="utf-8") as fh:
        df = pd.read_csv(fh)
    df["age"] = df["age"].astype(int)
    return df


mortality_tables: pd.DataFrame = _read_builtin()
"""All 10 built-in tables: column 'age' (0-120) plus one q_x column per table."""


def listTables() -> pd.DataFrame:
    """
    List the 10 built-in mortality tables.

    Returns
    -------
    pandas.DataFrame with columns name, description, origin, age_range.
    The 'name' column is what you pass to loadTable() or testAdherence().

    Example
    -------
    >>> import mortalityAdherence as ma
    >>> ma.listTables()
    """
    return _CATALOGUE.copy()


def loadTable(name: str) -> pd.DataFrame:
    """
    Load one built-in mortality table as a DataFrame with columns 'age' and 'qx'.

    Parameters
    ----------
    name : str
        One of listTables()['name'], e.g. "AT-2000m" or "BR-EMS2021".

    Notes
    -----
    The result can be modified (e.g. multiplied by a loading factor) and passed
    to testAdherence(table=...). Any external table works the same way, as long
    as it is a DataFrame with columns 'age' and 'qx'.

    Example
    -------
    >>> tab = ma.loadTable("AT-2000m")
    >>> tab["qx"] = tab["qx"] * 0.90      # 10% deloaded table
    """
    valid = list(_CATALOGUE["name"])
    if name not in valid:
        raise ValueError(f"'{name}' is not a recognised table name.\n"
                         f"Available tables: {', '.join(valid)}")
    return pd.DataFrame({"age": mortality_tables["age"].to_numpy(),
                         "qx": mortality_tables[name].to_numpy()})
