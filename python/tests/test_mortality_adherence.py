"""
Test suite for mortalityAdherence (Python).

Reference values in tests/data/r_reference.json were produced with
R 4.4 + MASS::glm.nb + the R package mortalityAdherence, on synthetic data.
Run with:  pytest   (from the 'python' folder)
"""
import json
import math
from pathlib import Path

import numpy as np
import pandas as pd
import pytest

import mortalityAdherence as ma
from mortalityAdherence import _glm, _tests

DATA = Path(__file__).parent / "data"
REF = json.loads((DATA / "r_reference.json").read_text())


def run(file, **kw):
    kw.setdefault("quiet", True)
    return ma.testAdherence(pd.read_csv(DATA / file), "AT-2000m", **kw)


def row(res, test):
    return res.summary.set_index("test").loc[test]


# --------------------------------------------------------------------------- tables
def test_list_tables():
    lt = ma.listTables()
    assert len(lt) == 10
    assert {"name", "description", "origin", "age_range"} <= set(lt.columns)


@pytest.mark.parametrize("name", list(ma.listTables()["name"]))
def test_load_table(name):
    t = ma.loadTable(name)
    assert list(t.columns) == ["age", "qx"]
    assert t["age"].tolist() == list(range(121))
    assert t["qx"].between(0, 1).all()
    assert t["qx"].iloc[-1] == 1.0


def test_table_values_match_r_package():
    t = ma.loadTable("AT-2000m").set_index("age")["qx"]
    assert t[40] == pytest.approx(0.000953)
    assert t[65] == pytest.approx(0.009940)
    assert ma.loadTable("BR-EMS2021").set_index("age")["qx"][65] == pytest.approx(0.01045)


def test_unknown_table():
    with pytest.raises(ValueError, match="not a recognised"):
        ma.loadTable("XYZ")


# --------------------------------------------------------------------------- KS critical
def test_ksd_matches_sfsmisc():
    r_vals = {1: .975, 11: 0.391129564434364, 25: 0.263827955882536,
              33: 0.230801563292280, 57: 0.176699657837339, 80: 0.1496}
    for n, v in r_vals.items():
        assert _tests.ks_critical_005(n) == pytest.approx(v, abs=1e-12)
    assert _tests.ks_critical_005(201) == pytest.approx(0.09493, abs=1e-5)


# --------------------------------------------------------------------------- R parity
@pytest.mark.parametrize("file", ["single_year.csv", "multi_year_overdispersed.csv",
                                  "multi_year_deloaded.csv"])
def test_poisson_family_matches_r(file):
    ref = REF[file]
    res = run(file)
    assert row(res, "ChiSquare")["statistic"] == pytest.approx(ref["chisq"], abs=1e-4)
    assert row(res, "ChiSquare")["p_value"] == pytest.approx(ref["chisq_p"], abs=1e-5)
    assert row(res, "WaldI_P")["statistic"] == pytest.approx(ref["waldI"], abs=1e-8)
    assert row(res, "LRTI_P")["statistic"] == pytest.approx(ref["lrtI"], abs=1e-4)
    assert row(res, "WaldII_P")["statistic"] == pytest.approx(ref["waldII"], rel=1e-6)
    assert row(res, "WaldII_P")["p_value"] == pytest.approx(ref["waldII_p"], abs=1e-8)
    assert row(res, "LRTII_P")["statistic"] == pytest.approx(ref["lrtII_dev"], abs=1e-6)
    assert res.dispersion_ratio == pytest.approx(ref["disp"], abs=1e-4)


def test_single_year_ks_and_bayes_match_r():
    ref = REF["single_year.csv"]
    res = run("single_year.csv")
    assert row(res, "KS")["statistic"] == pytest.approx(ref["ks"], abs=1e-4)
    assert res.details["BayesCI"]["ci_lower"] == pytest.approx(ref["bayes_lo"], abs=1e-4)
    assert res.details["BayesCI"]["ci_upper"] == pytest.approx(ref["bayes_hi"], abs=1e-4)


@pytest.mark.parametrize("file", ["single_year.csv", "multi_year_overdispersed.csv",
                                  "multi_year_deloaded.csv"])
def test_negative_binomial_matches_mass(file):
    ref = REF[file]
    res = run(file, skip_nb_if_no_overdispersion=False)
    m = res.data_used
    d = m["deaths"].to_numpy(float)
    off = np.log(m["expected"].to_numpy())
    ages = np.unique(m["age"])
    g = (m["age"].to_numpy() - ages.mean()) / ages.std(ddof=1)
    ones = np.ones_like(d)
    fits = [_glm.fit_nb(d, off, None), _glm.fit_nb(d, off, ones[:, None]),
            _glm.fit_nb(d, off, np.column_stack([ones, g]))]
    for f, th, ll in zip(fits, ref["nb_theta"], ref["nb_ll"]):
        assert f.phi == pytest.approx(th, rel=1e-5)
        assert f.loglik == pytest.approx(ll, abs=1e-6)
    assert row(res, "WaldI_NB")["statistic"] == pytest.approx(ref["nb_zI"], abs=1e-5)
    assert row(res, "WaldII_NB")["statistic"] == pytest.approx(ref["nb_WII"], rel=1e-5)
    lrt1 = 2 * (ref["nb_ll"][1] - ref["nb_ll"][0])
    lrt2 = 2 * (ref["nb_ll"][2] - ref["nb_ll"][0])
    assert row(res, "LRTI_NB")["statistic"] == pytest.approx(lrt1, abs=1e-5)
    assert row(res, "LRTII_NB")["statistic"] == pytest.approx(lrt2, abs=1e-5)


# --------------------------------------------------------------------------- paper definitions
def test_ks_uses_age_margins_for_multi_year_data():
    """Paper eq. (2): KS on d_x = sum_t d_{x,t} and E_x q_x, ordered by age."""
    res = run("multi_year_overdispersed.csv")
    m = res.data_used.groupby("age")[["deaths", "expected"]].sum().sort_index()
    F = np.cumsum(m["deaths"]) / m["deaths"].sum()
    F0 = np.cumsum(m["expected"]) / m["expected"].sum()
    assert row(res, "KS")["statistic"] == pytest.approx(np.max(np.abs(F - F0)), abs=1e-12)


def test_ks_invariant_to_global_deflator():
    """Paper Sec. 3.6: KS does not depend on a multiplicative factor on the table."""
    data = pd.read_csv(DATA / "single_year.csv")
    t = ma.loadTable("AT-2000m")
    ks = []
    for f in (0.5, 1.0, 2.0):
        tt = t.copy(); tt["qx"] = np.minimum(tt["qx"] * f, 1)
        ks.append(row(ma.testAdherence(data, tt, quiet=True), "KS")["statistic"])
    assert ks[0] == pytest.approx(ks[1]) and ks[2] == pytest.approx(ks[1])


def test_wald_I_closed_form_equals_glm():
    res = run("single_year.csv")
    m = res.data_used
    d = m["deaths"].to_numpy(float); off = np.log(m["expected"].to_numpy())
    f = _glm.fit_poisson(d, off, np.ones((len(d), 1)))
    z = f.beta[0] * math.sqrt(f.info[0, 0])
    assert row(res, "WaldI_P")["statistic"] == pytest.approx(z, abs=1e-8)


def test_bayes_hyperparameters_by_age():
    res = run("multi_year_overdispersed.csv")
    m = res.data_used.groupby("age")[["deaths", "expected"]].sum()
    th = m["deaths"] / m["expected"]
    mm, v = th.mean(), th.var(ddof=1)
    assert res.details["BayesCI"]["a0"] == pytest.approx(mm * mm / v)
    assert res.details["BayesCI"]["b0"] == pytest.approx(mm / v)


def test_chisq_df_option():
    r1 = run("single_year.csv")
    r2 = run("single_year.csv", chisq_df="k")
    assert row(r1, "ChiSquare")["df"] == 50 and row(r2, "ChiSquare")["df"] == 51
    assert row(r2, "ChiSquare")["p_value"] > row(r1, "ChiSquare")["p_value"]


def test_min_detectable_deflator_eq17():
    res = run("single_year.csv")
    c = 2.8016 / math.sqrt(res.expected_deaths)
    assert res.min_detectable[0] == pytest.approx(math.exp(-c), rel=1e-3)
    assert res.min_detectable[1] == pytest.approx(math.exp(c), rel=1e-3)


# --------------------------------------------------------------------------- zero deaths rule
@pytest.fixture
def zero_deaths():
    ages = np.arange(40, 56)
    return pd.DataFrame({"year": 2024, "age": ages, "exposed": 800, "deaths": 0})


def test_zero_deaths_wald_not_applicable(zero_deaths):
    res = ma.testAdherence(zero_deaths, "AT-2000m", quiet=True,
                           skip_nb_if_no_overdispersion=False)
    for t in ("WaldI_P", "WaldII_P", "WaldI_NB", "WaldII_NB"):
        assert row(res, t)["reject_h0"] == "N/A"
        assert "D = 0" in row(res, t)["note"]
    Q = res.expected_deaths
    for t in ("LRTI_P", "LRTII_P", "LRTI_NB", "LRTII_NB"):
        assert row(res, t)["statistic"] == pytest.approx(2 * Q)
        assert row(res, t)["reject_h0"] in ("Yes", "No")
    assert any("Zero deaths" in m for m in res.messages)


def test_zero_deaths_default_settings(zero_deaths):
    res = ma.testAdherence(zero_deaths, "AT-2000m", quiet=True)
    assert row(res, "WaldI_P")["reject_h0"] == "N/A"
    assert row(res, "KS")["reject_h0"] == "N/A"
    assert "Wald tests are not applicable" in str(res)


# --------------------------------------------------------------------------- data handling
def test_repeated_ages_without_year_are_cells():
    d = pd.read_csv(DATA / "multi_year_overdispersed.csv")
    with_year = ma.testAdherence(d, "AT-2000m", quiet=True)
    no_year = ma.testAdherence(d.drop(columns="year"), "AT-2000m", quiet=True)
    assert no_year.n_cells == with_year.n_cells == len(d)
    assert no_year.n_years == 5
    a = with_year.summary["statistic"].to_numpy(float)
    b = no_year.summary["statistic"].to_numpy(float)
    assert np.allclose(a, b, equal_nan=True)


def test_single_year_detected():
    res = run("single_year.csv")
    assert res.n_years == 1 and res.n_cells == res.n_ages == 51


def test_custom_table_and_loading_factor():
    data = pd.read_csv(DATA / "multi_year_deloaded.csv")
    t = ma.loadTable("AT-2000m"); t["qx"] *= 0.86
    res = ma.testAdherence(data, t, quiet=True)
    assert res.table_name == "Custom"
    assert abs(res.ae_ratio - 1) < 0.05


def test_input_errors():
    with pytest.raises(KeyError, match="Missing column"):
        ma.testAdherence(pd.DataFrame({"age": [1], "foo": [2]}), "AT-2000m")
    with pytest.raises(ValueError, match="negative"):
        ma.testAdherence(pd.DataFrame({"age": [60, 61, 62], "exposed": [-1, 2, 3],
                                       "deaths": [0, 0, 0]}), "AT-2000m")
    with pytest.raises(ValueError, match="Fewer than 3"):
        ma.testAdherence(pd.DataFrame({"age": [500, 501], "exposed": [1, 1],
                                       "deaths": [0, 0]}), "AT-2000m", quiet=True)
    with pytest.raises(KeyError, match="'age' and 'qx'"):
        ma.testAdherence(pd.read_csv(DATA / "single_year.csv"), pd.DataFrame({"x": [1]}))


def test_load_fund_data_brazilian_csv_and_excel(tmp_path):
    d = pd.read_csv(DATA / "multi_year_overdispersed.csv")
    br = d.rename(columns={"year": "Ano", "age": "Idade", "exposed": "Expostos",
                           "deaths": "Obitos"})
    p = tmp_path / "fundo.csv"
    br.to_csv(p, sep=";", decimal=",", index=False)
    x = ma.loadFundData(str(p), col_year="Ano", col_age="Idade", col_exposed="Expostos",
                        col_deaths="Obitos", sep=";", dec=",", quiet=True)
    assert list(x.columns) == ["year", "age", "exposed", "deaths"] and len(x) == len(d)
    px = tmp_path / "fundo.xlsx"
    d.to_excel(px, index=False)
    y = ma.loadFundData(str(px), quiet=True)
    assert len(y) == len(d) and y["deaths"].sum() == d["deaths"].sum()


# --------------------------------------------------------------------------- outputs
def test_outputs(tmp_path):
    res = run("multi_year_deloaded.csv")
    text = str(res)
    assert "mortalityAdherence" in text and "WaldII_NB" in text
    html = res.to_html(str(tmp_path / "r.html"))
    assert "<table" in html and (tmp_path / "r.html").exists()
    res.to_excel(str(tmp_path / "r.xlsx"))
    sheets = pd.read_excel(tmp_path / "r.xlsx", sheet_name=None)
    assert set(sheets) == {"Tests", "Overview", "Data used"}
    assert len(sheets["Tests"]) == 11


def test_snake_case_aliases():
    assert ma.test_adherence is ma.testAdherence
    assert ma.load_table("AT-2000m").shape == (121, 2)


# --------------------------------------------------------------------------- size (quick)
def test_size_close_to_nominal_quick():
    """Short version of the paper's Table 1 (N = 4,500): Wald I and LRT I size near 5%."""
    rng = np.random.default_rng(7)
    ages = np.arange(40, 91).astype(float)
    qx = 4.87e-5 * np.exp(8.87e-2 * ages)
    g = (ages - ages.mean()) / ages.std(ddof=1)
    rej = np.zeros(2)
    reps = 400
    for _ in range(reps):
        E = np.maximum(np.round(rng.normal(4500 / 51, 4500 / 153, 51)), 1)
        mu0 = E * qx
        d = rng.poisson(mu0).astype(float)
        p = _tests.poisson_family(d, mu0, g, 0.05, d, mu0)
        rej += [p["WaldI_P"]["reject"], p["LRTI_P"]["reject"]]
    assert np.all((rej / reps > 0.02) & (rej / reps < 0.09))
