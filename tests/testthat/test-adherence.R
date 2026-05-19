test_that("listTables returns a data.frame with 10 rows", {
  lt <- listTables()
  expect_s3_class(lt, "data.frame")
  expect_equal(nrow(lt), 10L)
  expect_true(all(c("name", "description", "origin", "age_range") %in% names(lt)))
})

test_that("loadTable returns a valid qx data.frame for every built-in table", {
  for (nm in listTables()$name) {
    tab <- loadTable(nm)
    expect_s3_class(tab, "data.frame", info = nm)
    expect_true(all(c("age", "qx") %in% names(tab)), info = nm)
    expect_equal(nrow(tab), 121L, info = nm)         # ages 0-120
    expect_true(all(tab$qx >= 0 & tab$qx <= 1), info = nm)
    expect_equal(tab$age, 0:120, info = nm)
  }
})

test_that("loadTable errors on an unknown name", {
  expect_error(loadTable("NOT-A-TABLE"), regexp = "not a recognised")
})

test_that("testAdherence returns an adherence_result with correct structure", {
  set.seed(1)
  ages  <- 50:75
  tab   <- loadTable("AT-2000m")
  sub   <- tab[tab$age %in% ages, ]
  fund  <- data.frame(
    age     = ages,
    exposed = as.integer(round(rlnorm(length(ages), 5, 0.3))),
    deaths  = NA_integer_
  )
  fund$deaths <- rpois(length(ages), fund$exposed * sub$qx)

  res <- testAdherence(fund, table = "AT-2000m", alpha = 0.05)

  expect_s3_class(res, "adherence_result")
  expect_true(all(c("summary", "details", "data_used", "table_name",
                     "alpha", "n_ages", "total_exposed",
                     "observed_deaths", "expected_deaths", "ae_ratio")
                   %in% names(res)))
  expect_equal(nrow(res$summary), 11L)
  expect_true(all(c("test", "description", "family", "statistic",
                     "p_value", "reject_h0") %in% names(res$summary)))
  expect_equal(res$table_name, "AT-2000m")
  expect_equal(res$alpha, 0.05)
})

test_that("testAdherence rejects H0 when mortality is inflated by 3x", {
  set.seed(42)
  ages  <- 50:80
  tab   <- loadTable("AT-2000m")
  sub   <- tab[tab$age %in% ages, ]
  exposed <- as.integer(rep(5000L, length(ages)))
  deaths  <- rpois(length(ages), exposed * sub$qx * 3)   # 3x mortality

  fund <- data.frame(age = ages, exposed = exposed, deaths = deaths)
  res  <- testAdherence(fund, table = "AT-2000m", alpha = 0.05)

  n_rej <- sum(res$summary$reject_h0 == "Yes", na.rm = TRUE)
  expect_gt(n_rej, 5L)   # at least 6 tests should reject under such a large deviation
})

test_that("testAdherence accepts a custom table as data.frame", {
  set.seed(7)
  ages <- 60:70
  tab  <- loadTable("BR-EMS2021")
  sub  <- tab[tab$age %in% ages, ]

  custom_tab <- data.frame(age = ages, qx = sub$qx * 0.9)   # 10% reduction
  fund <- data.frame(
    age     = ages,
    exposed = rep(1000L, length(ages)),
    deaths  = rpois(length(ages), 1000 * sub$qx)
  )
  expect_no_error(testAdherence(fund, table = custom_tab))
})

test_that("testAdherence errors on missing required columns", {
  bad <- data.frame(age = 60:65, foo = 1:6, bar = 0:5)
  expect_error(testAdherence(bad, table = "AT-2000m"), regexp = "Missing column")
})

test_that("testAdherence errors when too few age groups overlap", {
  fund <- data.frame(age = c(999L, 998L), exposed = c(100, 100), deaths = c(1L, 1L))
  expect_error(testAdherence(fund, table = "AT-2000m"),
               regexp = "Fewer than 3 valid age groups")
})

test_that("printResult runs without error and returns invisibly", {
  set.seed(3)
  ages <- 55:70
  tab  <- loadTable("AT-2000m")
  sub  <- tab[tab$age %in% ages, ]
  fund <- data.frame(age = ages,
                     exposed = rep(500L, length(ages)),
                     deaths  = rpois(length(ages), 500 * sub$qx))
  res  <- testAdherence(fund, table = "AT-2000m")
  expect_invisible(printResult(res))
})

test_that("A/E ratio is computed correctly", {
  ages <- 60:65
  tab  <- loadTable("AT-2000m")
  sub  <- tab[tab$age %in% ages, ]
  fund <- data.frame(age = ages, exposed = rep(1000L, 6),
                     deaths = as.integer(round(1000 * sub$qx)))
  res  <- testAdherence(fund, table = "AT-2000m")
  manual_ae <- sum(fund$deaths) / sum(1000 * sub$qx)
  expect_equal(res$ae_ratio, round(manual_ae, 4))
})
