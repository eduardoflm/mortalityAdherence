## mortalityAdherence — Full demonstration script
## Run this file interactively to explore all package features.
##
##   source(system.file("extdata", "demo.R", package = "mortalityAdherence"))

library(mortalityAdherence)

cat("\n", strrep("=", 65), "\n", sep = "")
cat("  mortalityAdherence — Full Demonstration\n")
cat(strrep("=", 65), "\n\n", sep = "")


# ── 1. Catalogue ──────────────────────────────────────────────────────────────
cat("[ 1 ] Available built-in mortality tables\n")
cat(strrep("-", 65), "\n", sep = "")
print(listTables())


# ── 2. Load a single table ────────────────────────────────────────────────────
cat("\n[ 2 ] AT-2000m table (first 10 rows)\n")
cat(strrep("-", 65), "\n", sep = "")
at2000m <- loadTable("AT-2000m")
print(head(at2000m, 10))


# ── 3. Simulate pension fund data ─────────────────────────────────────────────
cat("\n[ 3 ] Simulated pension fund data\n")
cat(strrep("-", 65), "\n", sep = "")

set.seed(123)
ages    <- 40:80
exposed <- round(rlnorm(length(ages), meanlog = log(250), sdlog = 0.5))
ref_qx  <- at2000m[at2000m$age %in% ages, "qx"]
mu_true <- exposed * ref_qx

# Fund A: perfectly adherent to AT-2000m
deaths_A <- rpois(length(ages), mu_true)

# Fund B: 25% excess mortality (fails adherence)
deaths_B <- rpois(length(ages), mu_true * 1.25)

fund_A <- data.frame(age = ages, exposed = exposed, deaths = deaths_A)
fund_B <- data.frame(age = ages, exposed = exposed, deaths = deaths_B)

cat(sprintf("Fund A: %d exposed | %d deaths | Expected %.1f  (A/E ~ %.3f)\n",
            sum(exposed), sum(deaths_A), sum(mu_true),
            sum(deaths_A) / sum(mu_true)))
cat(sprintf("Fund B: %d exposed | %d deaths | Expected %.1f  (A/E ~ %.3f)\n",
            sum(exposed), sum(deaths_B), sum(mu_true),
            sum(deaths_B) / sum(mu_true)))


# ── 4. Test Fund A vs AT-2000m ────────────────────────────────────────────────
cat("\n[ 4 ] Fund A × AT-2000m  (should NOT reject)\n")
cat(strrep("=", 65), "\n", sep = "")
res_A <- testAdherence(fund_A, table = "AT-2000m", alpha = 0.05, verbose = TRUE)
printResult(res_A)


# ── 5. Test Fund B vs AT-2000m ────────────────────────────────────────────────
cat("\n[ 5 ] Fund B × AT-2000m  (should REJECT — 25% excess mortality)\n")
cat(strrep("=", 65), "\n", sep = "")
res_B <- testAdherence(fund_B, table = "AT-2000m", alpha = 0.05, verbose = TRUE)
printResult(res_B)


# ── 6. Test Fund A vs BR-EMS2021 ─────────────────────────────────────────────
cat("\n[ 6 ] Fund A × BR-EMS2021  (different table)\n")
cat(strrep("=", 65), "\n", sep = "")
res_C <- testAdherence(fund_A, table = "BR-EMS2021", alpha = 0.05)
printResult(res_C)


# ── 7. Custom table (adjustment factor) ──────────────────────────────────────
cat("\n[ 7 ] Fund A × AT-2000m with 0.90 longevity factor\n")
cat(strrep("=", 65), "\n", sep = "")

adjusted_table <- at2000m
adjusted_table$qx <- adjusted_table$qx * 0.90

res_D <- testAdherence(fund_A, table = adjusted_table, alpha = 0.05)
printResult(res_D)


# ── 8. Programmatic access ────────────────────────────────────────────────────
cat("\n[ 8 ] Accessing results programmatically\n")
cat(strrep("-", 65), "\n", sep = "")

cat("Fund A — p-values and decisions:\n")
print(res_A$summary[, c("test", "p_value", "reject_h0")])

cat(sprintf("\nFund A — A/E ratio   : %.4f\n", res_A$ae_ratio))
cat(sprintf("Fund B — A/E ratio   : %.4f\n", res_B$ae_ratio))
cat(sprintf("Fund A — Tests rejecting H0: %d / 11\n",
            sum(res_A$summary$reject_h0 == "Yes", na.rm = TRUE)))
cat(sprintf("Fund B — Tests rejecting H0: %d / 11\n",
            sum(res_B$summary$reject_h0 == "Yes", na.rm = TRUE)))

cat("\n", strrep("=", 65), "\n", sep = "")
cat("  Demonstration complete.\n")
cat(strrep("=", 65), "\n\n", sep = "")
