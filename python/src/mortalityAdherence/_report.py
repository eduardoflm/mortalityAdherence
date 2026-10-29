"""Console, HTML and Excel reporting of an AdherenceResult."""

from __future__ import annotations

import html as _html
import math

import pandas as pd

W = 100


def _fmt_stat(v) -> str:
    return "--" if v is None or (isinstance(v, float) and math.isnan(v)) else f"{v:.4f}"


def _fmt_p(v) -> str:
    if v is None or (isinstance(v, float) and math.isnan(v)):
        return "--"
    return "<0.000001" if v < 1e-6 else f"{v:.6f}"


def _decision(r: str) -> str:
    return {"Yes": "[ REJECT ]", "No": "[  pass  ]"}.get(r, "[  N/A   ]")


def verdict(result) -> str:
    s = result.summary
    n_rej = int((s["reject_h0"] == "Yes").sum())
    n_tot = int(s["reject_h0"].isin(["Yes", "No"]).sum())
    if n_rej == 0:
        v = "[OK] GOOD ADHERENCE: the table fits the fund data well."
    elif n_rej <= 3:
        v = "[!!] PARTIAL ADHERENCE: some tests failed. Review critical age groups."
    else:
        v = "[XX] POOR ADHERENCE: consider a different table or an adjustment factor."
    return (f"{n_rej} of {n_tot} applicable tests reject H0 at the "
            f"{result.alpha * 100:.0f}% significance level.\n  {v}")


def format_result(result, show_notes: bool = True) -> str:
    x = result
    lines = ["", "=" * W,
             "  mortalityAdherence :: Biometric Table Adherence Test",
             "=" * W,
             f"  Mortality table    : {x.table_name}",
             f"  Significance level : {x.alpha * 100:.1f}%",
             f"  Cells (rows)       : {x.n_cells}",
             f"  Unique ages        : {x.n_ages}",
             f"  Years              : {x.n_years}",
             f"  Total exposed      : {x.total_exposed:,.0f}",
             f"  Observed deaths (D): {x.observed_deaths:,.0f}",
             f"  Expected deaths (Q): {x.expected_deaths:,.2f}",
             f"  A/E ratio (D/Q)    : {x.ae_ratio:.4f}  ({(x.ae_ratio - 1) * 100:+.1f}%)"]
    if not math.isnan(x.dispersion_ratio):
        tag = ("no overdispersion, NB tests not applicable"
               if x.dispersion_ratio <= 1 else "overdispersion present, NB tests applied")
        lines.append(f"  Dispersion ratio   : {x.dispersion_ratio:.4f} -- {tag}")
    lo, hi = x.min_detectable
    lines.append(f"  Min. detectable    : theta < {lo:.2f} or theta > {hi:.2f} "
                 "(80% power, version I tests)")
    lines.append("-" * W)
    lines.append(f"  {'Test':<11}  {'Description':<41}  {'Statistic':>10}  "
                 f"{'P-value':>10}  Decision")
    lines.append("-" * W)
    prev = None
    for _, r in x.summary.iterrows():
        if r["family"] != prev:
            lines.append(f"  [ {r['family']} ]")
            prev = r["family"]
        lines.append(f"  {r['test']:<11}  {r['description']:<41}  {_fmt_stat(r['statistic']):>10}  "
                     f"{_fmt_p(r['p_value']):>10}  {_decision(r['reject_h0'])}")
        if show_notes and r["note"]:
            lines.append(f"  {'':<11}    -> {r['note']}")
    lines.append("=" * W)
    lines.append("  " + verdict(x))
    if x.observed_deaths == 0:
        lines.append("  Note: no deaths in the sample -- Wald tests are not applicable (paper, Sec. 3.5).")
    if (x.summary["reject_h0"] == "No").any():
        lines.append(f"  Note: a non-rejection only rules out deflators outside "
                     f"[{lo:.2f}, {hi:.2f}] (80% power); smaller departures may go "
                     "undetected (paper, eq. 17).")
    lines.append("  Reference: de Melo, Graziadei & Targino (2026), SSRN 6668699.")
    lines.append("")
    return "\n".join(lines)


def printResult(result, show_notes: bool = True) -> None:
    """Print the formatted report of an AdherenceResult."""
    print(format_result(result, show_notes=show_notes))


_CSS = """
<style>
.ma-wrap{font-family:system-ui,-apple-system,Segoe UI,Roboto,sans-serif;max-width:1100px;color:#1d2433}
.ma-wrap h2{font-size:1.15rem;margin:0 0 .4rem}
.ma-meta{display:flex;flex-wrap:wrap;gap:.4rem 1.4rem;font-size:.85rem;color:#4a5468;margin:.2rem 0 .8rem}
.ma-meta b{color:#1d2433}
.ma-tab{border-collapse:collapse;width:100%;font-size:.85rem}
.ma-tab th{background:#1f3a5f;color:#fff;text-align:left;padding:.45rem .6rem;font-weight:600}
.ma-tab td{padding:.4rem .6rem;border-bottom:1px solid #e3e7ee;vertical-align:top}
.ma-tab td.num{text-align:right;font-variant-numeric:tabular-nums}
.ma-fam td{background:#f2f5f9;font-weight:600;color:#1f3a5f}
.ma-rej td{background:#fdecec}.ma-rej td.dec{color:#b3261e;font-weight:700}
.ma-ok td.dec{color:#1b7f3b;font-weight:700}
.ma-na td{color:#8a93a4}
.ma-note{font-size:.78rem;color:#6b7486}
.ma-verdict{margin-top:.8rem;padding:.6rem .8rem;border-radius:6px;background:#eef3fa;font-size:.9rem}
.ma-ref{font-size:.75rem;color:#6b7486;margin-top:.6rem}
</style>
"""


def html_table(result, full_page: bool = True) -> str:
    x = result
    e = _html.escape
    lo, hi = x.min_detectable
    meta = [("Table", x.table_name), ("alpha", f"{x.alpha:.2f}"), ("Cells", x.n_cells),
            ("Ages", x.n_ages), ("Years", x.n_years), ("Exposed", f"{x.total_exposed:,.0f}"),
            ("Observed D", f"{x.observed_deaths:,.0f}"), ("Expected Q", f"{x.expected_deaths:,.1f}"),
            ("A/E", f"{x.ae_ratio:.4f}"),
            ("Dispersion", "--" if math.isnan(x.dispersion_ratio) else f"{x.dispersion_ratio:.3f}"),
            ("Min. detectable", f"&theta;&lt;{lo:.2f} or &gt;{hi:.2f}")]
    parts = [_CSS, '<div class="ma-wrap"><h2>Mortality table adherence tests</h2>',
             '<div class="ma-meta">' +
             "".join(f"<span>{k}: <b>{v}</b></span>" for k, v in meta) + "</div>",
             '<table class="ma-tab"><thead><tr><th>Test</th><th>Description</th><th>H0</th>'
             '<th>df</th><th>Statistic</th><th>P-value</th><th>Decision</th></tr></thead><tbody>']
    prev = None
    for _, r in x.summary.iterrows():
        if r["family"] != prev:
            parts.append(f'<tr class="ma-fam"><td colspan="7">{e(r["family"])}</td></tr>')
            prev = r["family"]
        cls = {"Yes": "ma-rej", "No": "ma-ok"}.get(r["reject_h0"], "ma-na")
        dec = {"Yes": "REJECT", "No": "Pass"}.get(r["reject_h0"], "N/A")
        note = f'<div class="ma-note">{e(r["note"])}</div>' if r["note"] else ""
        dfv = "" if pd.isna(r["df"]) else str(int(r["df"]))
        parts.append(
            f'<tr class="{cls}"><td><b>{e(r["test"])}</b></td><td>{e(r["description"])}{note}</td>'
            f'<td>{e(r["h0"])}</td><td class="num">{dfv}</td>'
            f'<td class="num">{_fmt_stat(r["statistic"])}</td>'
            f'<td class="num">{e(_fmt_p(r["p_value"]))}</td><td class="dec">{dec}</td></tr>')
    parts.append("</tbody></table>")
    parts.append(f'<div class="ma-verdict">{e(verdict(x)).replace(chr(10), "<br>")}</div>')
    parts.append('<div class="ma-ref">de Melo, E.F.L., Graziadei, H. &amp; Targino, R. (2026). '
                 'Annuity Table Validation in Pension Funds: A Comparative Power Analysis of '
                 'Goodness-of-Fit Tests. SSRN 6668699.</div></div>')
    body = "\n".join(parts)
    if not full_page:
        return body
    return ('<!doctype html><html><head><meta charset="utf-8">'
            '<meta name="viewport" content="width=device-width,initial-scale=1">'
            f'<title>Adherence tests - {e(x.table_name)}</title></head>'
            f'<body style="margin:24px">{body}</body></html>')


def htmlTable(result, path: str = None) -> str:
    """Return (and optionally save) a styled HTML table of the results."""
    return result.to_html(path)


def exportExcel(result, path: str) -> str:
    """Write the results to an .xlsx file (sheets: Tests, Overview, Data used)."""
    write_excel(result, path)
    return path


def write_excel(result, path: str) -> None:
    x = result
    lo, hi = x.min_detectable
    header = pd.DataFrame({
        "item": ["Mortality table", "alpha", "Cells", "Unique ages", "Years",
                 "Total exposed", "Observed deaths (D)", "Expected deaths (Q)",
                 "A/E ratio (D/Q)", "Dispersion ratio",
                 "Min. detectable theta (low)", "Min. detectable theta (high)", "Verdict"],
        "value": [x.table_name, x.alpha, x.n_cells, x.n_ages, x.n_years,
                  x.total_exposed, x.observed_deaths, x.expected_deaths,
                  x.ae_ratio, x.dispersion_ratio, lo, hi, verdict(x).replace("\n  ", " ")],
    })
    with pd.ExcelWriter(path, engine="openpyxl") as xw:
        x.summary.to_excel(xw, sheet_name="Tests", index=False)
        header.to_excel(xw, sheet_name="Overview", index=False)
        x.data_used.to_excel(xw, sheet_name="Data used", index=False)
        for ws in xw.book.worksheets:
            for col in ws.columns:
                width = max(len(str(c.value)) if c.value is not None else 0 for c in col)
                ws.column_dimensions[col[0].column_letter].width = min(max(10, width + 2), 60)
