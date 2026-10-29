# Test suite for mortalityAdherence (R).
# Fixtures in tests/testthat/data are synthetic. python_reference.csv holds the
# results of the Python version on the same data: both versions must agree.

dat <- function(f) read.csv(test_path("data", f))
row <- function(r, t) r$summary[r$summary$test == t, ]
run <- function(f, ...) testAdherence(dat(f), "AT-2000m", quiet = TRUE, ...)

# ---- tables ------------------------------------------------------------------
test_that("built-in tables", {
  lt <- listTables()
  expect_equal(nrow(lt), 10L)
  expect_true(all(c("name", "description", "origin", "age_range") %in% names(lt)))
  for (nm in lt$name) {
    tb <- loadTable(nm)
    expect_equal(names(tb), c("age", "qx"))
    expect_equal(tb$age, 0:120)
    expect_true(all(tb$qx >= 0 & tb$qx <= 1))
  }
  expect_equal(loadTable("AT-2000m")$qx[loadTable("AT-2000m")$age == 65], 0.00994)
  expect_true("AT-2000m" %in% names(mortality_tables))
  expect_error(loadTable("XYZ"), "not a recognised")
})

# ---- KS critical value = sfsmisc::KSd ----------------------------------------
test_that("KS critical value matches sfsmisc::KSd", {
  ref <- c(`1` = .975, `11` = 0.391129564434364, `25` = 0.263827955882536,
           `57` = 0.176699657837339, `80` = 0.1496)
  for (n in names(ref))
    expect_equal(mortalityAdherence:::.ks_crit_005(as.numeric(n)), ref[[n]], tolerance = 1e-12)
  expect_equal(mortalityAdherence:::.ks_crit_005(201), 0.09493048, tolerance = 1e-7)
})

# ---- parity with the Python version ------------------------------------------
test_that("R and Python versions give the same results", {
  py <- dat("python_reference.csv")
  for (f in unique(py$file)) for (sk in c(TRUE, FALSE)) {
    r <- run(f, skip_nb_if_no_overdispersion = sk)$summary
    p <- py[py$file == f & py$skip == sk, ]
    p <- p[match(r$test, p$test), ]
    expect_equal(r$reject_h0, p$reject_h0, info = f)
    expect_equal(r$statistic, p$statistic, tolerance = 1e-6, info = f)
    expect_equal(r$p_value, p$p_value, tolerance = 1e-6, info = f)
  }
})

# ---- Negative Binomial = MASS::glm.nb -------------------------------------------
test_that("Negative Binomial fits match MASS::glm.nb", {
  ref <- list(
    single_year.csv = list(ll = c(-54.255610999372, -50.641683994041, -50.533834697025),
                           th = c(2.471051565254, 8.570443847583, 8.788378796199),
                           z = -2.890329105161, w = 8.588723423417),
    multi_year_deloaded.csv = list(ll = c(-360.004000834179, -350.726179969717, -348.969666110349),
                                   th = c(9.52029533206, 12.347350579988, 13.166495643654),
                                   z = -4.385924487489, w = 22.650526895565))
  for (f in names(ref)) {
    r <- run(f, skip_nb_if_no_overdispersion = FALSE)
    m <- r$data_used
    off <- log(m$expected); ag <- sort(unique(m$age)); g <- (m$age - mean(ag)) / sd(ag)
    fits <- list(mortalityAdherence:::.fit_nb(m$deaths, off, NULL),
                 mortalityAdherence:::.fit_nb(m$deaths, off, matrix(1, nrow(m), 1)),
                 mortalityAdherence:::.fit_nb(m$deaths, off, cbind(1, g)))
    expect_equal(vapply(fits, `[[`, 0, "loglik"), ref[[f]]$ll, tolerance = 1e-8)
    expect_equal(vapply(fits, `[[`, 0, "phi"), ref[[f]]$th, tolerance = 1e-5)
    expect_equal(row(r, "WaldI_NB")$statistic, ref[[f]]$z, tolerance = 1e-6)
    expect_equal(row(r, "WaldII_NB")$statistic, ref[[f]]$w, tolerance = 1e-6)
  }
})

# ---- definitions of the paper ---------------------------------------------------
test_that("KS uses the age margins (eq. 2) and is invariant to a global deflator", {
  r <- run("multi_year_overdispersed.csv")
  a <- aggregate(cbind(deaths, expected) ~ age, data = r$data_used, FUN = sum)
  ks <- max(abs(cumsum(a$deaths) / sum(a$deaths) - cumsum(a$expected) / sum(a$expected)))
  expect_equal(row(r, "KS")$statistic, ks)
  tb <- loadTable("AT-2000m")
  ks2 <- sapply(c(0.5, 1, 2), function(f) {
    t2 <- tb; t2$qx <- pmin(t2$qx * f, 1)
    row(testAdherence(dat("single_year.csv"), t2, quiet = TRUE), "KS")$statistic
  })
  expect_equal(ks2[1], ks2[2]); expect_equal(ks2[3], ks2[2])
})

test_that("Wald I closed form, LRT I and Wald II follow eqs. 8, 11 and 13", {
  r <- run("single_year.csv")
  D <- r$observed_deaths; Q <- r$expected_deaths
  expect_equal(row(r, "WaldI_P")$statistic, log(D / Q) * sqrt(D))
  expect_equal(row(r, "LRTI_P")$statistic, 2 * (D * log(D / Q) - (D - Q)))
  m <- r$data_used; ag <- sort(unique(m$age)); g <- (m$age - mean(ag)) / sd(ag)
  fit <- glm(deaths ~ g, offset = log(expected), family = poisson, data = m,
             control = glm.control(epsilon = 1e-12))
  b <- coef(fit)
  expect_equal(row(r, "WaldII_P")$statistic, drop(t(b) %*% solve(vcov(fit)) %*% b), tolerance = 1e-6)
  expect_equal(row(r, "LRTII_P")$statistic,
               2 * (as.numeric(logLik(fit)) - sum(dpois(m$deaths, m$expected, log = TRUE))),
               tolerance = 1e-6)
})

test_that("Bayesian prior uses age-specific ratios (eq. 9) and reports pi (eq. 10)", {
  r <- run("multi_year_overdispersed.csv")
  a <- aggregate(cbind(deaths, expected) ~ age, data = r$data_used, FUN = sum)
  th <- a$deaths / a$expected
  expect_equal(r$details$BayesCI$a0, mean(th)^2 / var(th))
  expect_equal(r$details$BayesCI$b0, mean(th) / var(th))
  ap <- r$details$BayesCI$a0 + r$observed_deaths; bp <- r$details$BayesCI$b0 + r$expected_deaths
  expect_equal(row(r, "BayesCI")$p_value, 2 * min(pgamma(1, ap, bp), pgamma(1, ap, bp, lower.tail = FALSE)))
})

test_that("chi-squared degrees of freedom option", {
  expect_equal(row(run("single_year.csv"), "ChiSquare")$df, 50)
  expect_equal(row(run("single_year.csv", chisq_df = "k"), "ChiSquare")$df, 51)
})

test_that("minimum detectable deflator (eq. 17)", {
  r <- run("single_year.csv")
  cc <- (qnorm(0.975) + qnorm(0.8)) / sqrt(r$expected_deaths)
  expect_equal(r$min_detectable, c(exp(-cc), exp(cc)))
})

# ---- rule for samples without deaths (Sec. 3.5) -------------------------------------
test_that("D = 0: Wald tests are N/A, LRT statistics equal 2Q", {
  zero <- data.frame(year = 2024, age = 40:55, exposed = 800, deaths = 0)
  r <- testAdherence(zero, "AT-2000m", quiet = TRUE, skip_nb_if_no_overdispersion = FALSE)
  for (t in c("WaldI_P", "WaldII_P", "WaldI_NB", "WaldII_NB")) {
    expect_equal(row(r, t)$reject_h0, "N/A")
    expect_match(row(r, t)$note, "D = 0", fixed = TRUE)
  }
  for (t in c("LRTI_P", "LRTII_P", "LRTI_NB", "LRTII_NB"))
    expect_equal(row(r, t)$statistic, 2 * r$expected_deaths)
  expect_true(any(grepl("Zero deaths", r$messages)))
  expect_match(paste(capture.output(print(r)), collapse = "\n"),
               "Wald tests are not applicable", fixed = TRUE)
})

# ---- data handling -----------------------------------------------------------------
test_that("repeated ages without a year column are treated as stacked years", {
  d <- dat("multi_year_overdispersed.csv")
  a <- testAdherence(d, "AT-2000m", quiet = TRUE)
  b <- testAdherence(d[, c("age", "exposed", "deaths")], "AT-2000m", quiet = TRUE)
  expect_equal(a$n_cells, nrow(d)); expect_equal(b$n_years, 5L)
  expect_equal(a$summary$statistic, b$summary$statistic)
})

test_that("messages, custom tables and input errors", {
  expect_message(testAdherence(dat("single_year.csv"), "AT-2000m"), "year' column detected: 1 year")
  expect_message(testAdherence(dat("single_year.csv")[, -1], "AT-2000m"), "Single-year data")
  tb <- loadTable("AT-2000m"); tb$qx <- tb$qx * 0.86
  r <- testAdherence(dat("multi_year_deloaded.csv"), tb, quiet = TRUE)
  expect_equal(r$table_name, "Custom"); expect_lt(abs(r$ae_ratio - 1), 0.05)
  expect_error(testAdherence(data.frame(age = 1, foo = 2), "AT-2000m"), "Missing column")
  expect_error(testAdherence(data.frame(age = 60:62, exposed = c(-1, 2, 3), deaths = 0),
                             "AT-2000m", quiet = TRUE), "negative")
  expect_error(testAdherence(data.frame(age = 500:501, exposed = 1, deaths = 0),
                             "AT-2000m", quiet = TRUE), "Fewer than 3")
})

test_that("loadFundData reads Brazilian CSV", {
  d <- dat("multi_year_overdispersed.csv")
  names(d) <- c("Ano", "Idade", "Expostos", "Obitos")
  f <- tempfile(fileext = ".csv")
  write.csv2(d, f, row.names = FALSE)
  x <- loadFundData(f, col_year = "Ano", col_age = "Idade", col_exposed = "Expostos",
                    col_deaths = "Obitos", sep = ";", dec = ",", quiet = TRUE)
  expect_equal(names(x), c("year", "age", "exposed", "deaths"))
  expect_equal(nrow(x), nrow(d))
})

# ---- outputs ---------------------------------------------------------------------
test_that("print, HTML and Excel outputs", {
  r <- run("multi_year_deloaded.csv")
  out <- capture.output(print(r))
  expect_true(any(grepl("mortalityAdherence :: Biometric Table Adherence Test", out, fixed = TRUE)))
  f <- tempfile(fileext = ".html")
  htmlTable(r, path = f)
  expect_true(file.exists(f))
  expect_match(paste(readLines(f), collapse = ""), "<table", fixed = TRUE)
  skip_if_not_installed("writexl")
  x <- tempfile(fileext = ".xlsx")
  exportExcel(r, x)
  expect_true(file.exists(x))
})
