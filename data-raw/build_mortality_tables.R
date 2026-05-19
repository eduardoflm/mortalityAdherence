## data-raw/build_mortality_tables.R
##
## Reproduces the `mortality_tables` dataset from the original XLS source file.
## Run this script once (from the package root) whenever the source data changes:
##
##   source("data-raw/build_mortality_tables.R")
##
## Requires: readxl, usethis
## Place the original Teste_Tabuas.xls in data-raw/ before running.

library(readxl)
library(usethis)

# Read the 'Tabuas' sheet from the source workbook
raw <- readxl::read_excel(
  path  = "data-raw/Teste_Tabuas.xls",
  sheet = "Tabuas"
)

# Rename 'Idade' to 'age' for consistency with the package API
names(raw)[names(raw) == "Idade"] <- "age"
raw$age <- as.integer(raw$age)

# Coerce all qx columns to numeric
for (col in setdiff(names(raw), "age")) {
  raw[[col]] <- as.numeric(raw[[col]])
}

mortality_tables <- as.data.frame(raw)

# Persist as lazy-loaded package data
usethis::use_data(mortality_tables, overwrite = TRUE, compress = "xz")

cat(sprintf(
  "mortality_tables saved: %d ages x %d tables\n",
  nrow(mortality_tables),
  ncol(mortality_tables) - 1L
))
