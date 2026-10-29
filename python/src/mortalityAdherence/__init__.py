"""
mortalityAdherence — Biometric (mortality / annuity) table adherence testing
for pension funds. Python version of the R package of the same name.

Implements the 11 tests of:
    de Melo, E.F.L., Graziadei, H. & Targino, R. (2026).
    Annuity Table Validation in Pension Funds: A Comparative Power Analysis
    of Goodness-of-Fit Tests. SSRN 6668699.
    https://papers.ssrn.com/sol3/papers.cfm?abstract_id=6668699

Quick start
-----------
>>> import mortalityAdherence as ma
>>> ma.listTables()
>>> data = ma.loadFundData("my_fund.csv")            # year, age, exposed, deaths
>>> result = ma.testAdherence(data, table="AT-2000m")
>>> print(result)
>>> result.to_excel("results.xlsx")

Function names follow the R package (camelCase); snake_case aliases are
also provided (test_adherence, list_tables, load_table, load_fund_data, ...).
"""

from ._adherence import AdherenceResult, testAdherence
from ._io import loadFundData
from ._report import htmlTable, printResult
from ._tables import listTables, loadTable, mortality_tables

__version__ = "0.1.0"

# snake_case aliases (Python convention)
test_adherence = testAdherence
list_tables = listTables
load_table = loadTable
load_fund_data = loadFundData
print_result = printResult
html_table = htmlTable

__all__ = [
    "testAdherence", "listTables", "loadTable", "loadFundData", "printResult",
    "htmlTable", "mortality_tables", "AdherenceResult",
    "test_adherence", "list_tables", "load_table", "load_fund_data",
    "print_result", "html_table", "__version__",
]
