# =============================================================================
# SECTION 4 — TABLE CATALOGUE & DATA LOADING
# =============================================================================

# Internal catalogue of built-in tables
.BUILT_IN_TABLES <- data.frame(
  name = c(
    "AT-2000bm", "AT-2000m", "AT-49M", "AT-55m", "AT-83ms",
    "GAM71m", "GAM83m", "BR-EMS2010", "BR-EMS2015", "BR-EMS2021"
  ),
  description = c(
    "American Table 2000 — Male Beneficiaries (SOA)",
    "American Table 2000 — Male (SOA)",
    "American Table 1949 — Male",
    "American Table 1955 — Male",
    "American Table 1983 — Male (smoothed)",
    "Group Annuity Mortality 1971 — Male (SOA)",
    "Group Annuity Mortality 1983 — Male (SOA)",
    "Brazilian Mortality Experience 2010 (BR-EMS)",
    "Brazilian Mortality Experience 2015 (BR-EMS)",
    "Brazilian Mortality Experience 2021 (BR-EMS)"
  ),
  origin = c(
    rep("USA — Society of Actuaries", 7),
    rep("Brazil — FenaPrevi / SUSEP", 3)
  ),
  age_range = rep("0 – 120", 10),
  stringsAsFactors = FALSE
)


#' List Available Built-in Mortality Tables
#'
#' Returns a data frame describing the 10 biometric mortality tables
#' built into the \pkg{mortalityAdherence} package.
#'
#' @return A \code{data.frame} with columns:
#' \describe{
#'   \item{\code{name}}{Table identifier to pass to \code{\link{loadTable}()}.}
#'   \item{\code{description}}{Full descriptive name.}
#'   \item{\code{origin}}{Country and source organisation.}
#'   \item{\code{age_range}}{Age range covered.}
#' }
#'
#' @examples
#' listTables()
#'
#' @export
listTables <- function() {
  .BUILT_IN_TABLES
}


#' Load a Built-in Mortality Table
#'
#' Retrieves one of the 10 mortality tables included in the package as a
#' tidy data frame with columns \code{age} and \code{qx}.
#'
#' @param name \code{character} — name of the table.
#'   Use \code{\link{listTables}()} to see all available options.
#'
#' @return A \code{data.frame} with columns:
#' \describe{
#'   \item{\code{age}}{Integer age (0 to 120).}
#'   \item{\code{qx}}{Annual probability of death \eqn{q_x}.}
#' }
#'
#' @examples
#' # Load the AT-2000m table
#' tab <- loadTable("AT-2000m")
#' head(tab)
#'
#' # Plot the mortality curve
#' plot(tab$age, tab$qx, type = "l", log = "y",
#'      main = "AT-2000m Mortality Curve",
#'      xlab = "Age", ylab = expression(q[x]))
#'
#' @export
loadTable <- function(name) {
  valid <- .BUILT_IN_TABLES$name
  if (!name %in% valid)
    stop(sprintf(
      "'%s' is not a recognised table name.\nAvailable tables: %s\n",
      name, paste(valid, collapse = ", ")
    ))

  mt <- get("mortality_tables", envir = asNamespace("mortalityAdherence"))

  # Column names may have hyphens normalised to dots by R internals
  # Try exact name first, then dot-substituted version
  col_idx <- which(names(mt) == name)
  if (length(col_idx) == 0L) {
    name_dots <- gsub("-", ".", name, fixed = TRUE)
    col_idx   <- which(names(mt) == name_dots)
  }
  if (length(col_idx) == 0L)
    stop(sprintf(
      "Internal error: column '%s' not found in mortality_tables.\nAvailable columns: %s",
      name, paste(names(mt), collapse = ", ")
    ))

  data.frame(
    age = mt$age,
    qx  = mt[[col_idx]],
    stringsAsFactors = FALSE
  )
}


#' Load Pension Fund Mortality Data from a File
#'
#' Reads a CSV or Excel file containing pension fund experience data and
#' returns a data frame in the format expected by \code{\link{testAdherence}()}.
#'
#' @param file \code{character} — path to the file. Supported formats:
#'   \code{.csv}, \code{.xlsx}, \code{.xls}.
#' @param col_year \code{character} — name of the year column, if present.
#'   Default: \code{"year"}. Set to \code{NULL} to ignore a year column.
#' @param col_age \code{character} — name of the age column.
#'   Default: \code{"age"}.
#' @param col_exposed \code{character} — name of the exposed lives column.
#'   Default: \code{"exposed"}.
#' @param col_deaths \code{character} — name of the observed deaths column.
#'   Default: \code{"deaths"}.
#' @param sep \code{character} — field separator for CSV files.
#'   Default: \code{","}.
#' @param dec \code{character} — decimal separator for CSV files.
#'   Default: \code{"."}.
#' @param sheet \code{integer} or \code{character} — sheet to read from Excel
#'   files. Default: \code{1}.
#' @param ... Additional arguments passed to \code{utils::read.csv()} or
#'   \code{readxl::read_excel()}.
#'
#' @return A \code{data.frame} with columns \code{year} (if found),
#'   \code{age}, \code{exposed}, and \code{deaths}. Each row is one
#'   cell (year-age combination). Rows with zero or missing exposure
#'   are removed automatically.
#'
#' @details
#' \strong{Expected data format — long (stacked) format:}
#'
#' Each row must represent one year-age cell. For multi-year data, stack
#' the years vertically — do \strong{not} spread years across columns.
#'
#' Correct long format:
#' \preformatted{
#'   year  age  exposed  deaths
#'   2020   40      400       1
#'   2020   41      410       1
#'   2021   40      390       1
#'   2021   41      450       2
#' }
#'
#' If your data has only one year, a year column is optional:
#' \preformatted{
#'   age  exposed  deaths
#'    40      400       1
#'    41      410       1
#' }
#'
#' \strong{Why long format matters:} each (year, age) cell is treated as an
#' independent observation in the statistical tests, increasing test power
#' proportionally to the number of years.
#'
#' Reading Excel files requires the \pkg{readxl} package:
#' \code{install.packages("readxl")}.
#'
#' @examples
#' \dontrun{
#' # Multi-year CSV with year column
#' data <- loadFundData("experience.csv")
#'
#' # Single-year CSV — year column optional
#' data <- loadFundData("experience_2023.csv")
#'
#' # Brazilian-format CSV (semicolon separator, comma decimal)
#' data <- loadFundData("experiencia.csv", sep = ";", dec = ",",
#'                       col_year    = "Ano",
#'                       col_age     = "Idade",
#'                       col_exposed = "Expostos",
#'                       col_deaths  = "Obitos")
#'
#' # Excel file, no year column
#' data <- loadFundData("fund.xlsx",
#'                       col_year    = NULL,
#'                       col_age     = "FxEtaria",
#'                       col_exposed = "ExpostoRisco",
#'                       col_deaths  = "Mortes",
#'                       sheet       = "Mortalidade")
#' }
#'
#' @export
loadFundData <- function(file,
                          col_year    = "year",
                          col_age     = "age",
                          col_exposed = "exposed",
                          col_deaths  = "deaths",
                          sep         = ",",
                          dec         = ".",
                          sheet       = 1L,
                          ...) {
  if (!file.exists(file))
    stop(sprintf("File not found: '%s'", file))

  ext <- tolower(tools::file_ext(file))

  if (ext == "csv") {
    raw <- utils::read.csv(file, sep = sep, dec = dec,
                           stringsAsFactors = FALSE, ...)
  } else if (ext %in% c("xlsx", "xls")) {
    if (!requireNamespace("readxl", quietly = TRUE))
      stop(paste0(
        "Package 'readxl' is required to read Excel files.\n",
        "Install it with: install.packages('readxl')"
      ))
    raw <- as.data.frame(readxl::read_excel(file, sheet = sheet, ...))
  } else {
    stop(sprintf(
      "Unsupported file extension '%s'. Use .csv, .xlsx, or .xls.", ext
    ))
  }

  # Verify required columns exist
  for (col in c(col_age, col_exposed, col_deaths)) {
    if (!col %in% names(raw))
      stop(sprintf(
        "Column '%s' not found. Available columns: %s",
        col, paste(names(raw), collapse = ", ")
      ))
  }

  # Detect year column
  has_year <- !is.null(col_year) && col_year %in% names(raw)

  if (has_year) {
    out <- data.frame(
      year    = as.integer(raw[[col_year]]),
      age     = as.integer(raw[[col_age]]),
      exposed = as.numeric(raw[[col_exposed]]),
      deaths  = as.integer(raw[[col_deaths]]),
      stringsAsFactors = FALSE
    )
  } else {
    out <- data.frame(
      age     = as.integer(raw[[col_age]]),
      exposed = as.numeric(raw[[col_exposed]]),
      deaths  = as.integer(raw[[col_deaths]]),
      stringsAsFactors = FALSE
    )
    # Warn if ages repeat but no year column was found
    if (anyDuplicated(out$age) > 0L) {
      message(paste0(
        "  [loadFundData] Repeated ages detected but no year column found",
        if (!is.null(col_year))
          sprintf(" (looked for '%s').", col_year)
        else ".",
        "\n  Each row will be treated as an independent cell.",
        "\n  To make the structure explicit, add a year column and pass",
        " col_year = 'your_year_column'."
      ))
    }
  }

  # Remove invalid rows
  n_before <- nrow(out)
  out <- out[!is.na(out$age) & out$exposed > 0 & !is.na(out$deaths), ]
  n_removed <- n_before - nrow(out)

  # Sort by year (if present) then age
  if (has_year) {
    out <- out[order(out$year, out$age), ]
  } else {
    out <- out[order(out$age), ]
  }

  n_years <- if (has_year) length(unique(out$year)) else
             if (anyDuplicated(out$age) > 0L) max(tabulate(out$age)) else 1L

  message(sprintf(
    "Fund data loaded: %d row(s) | %d unique age(s) | %s year(s) | %s exposed | %d deaths%s",
    nrow(out),
    length(unique(out$age)),
    if (has_year) as.character(n_years) else "unknown (no year column)",
    format(as.integer(sum(out$exposed)), big.mark = ","),
    sum(out$deaths),
    if (n_removed > 0)
      sprintf(" | %d row(s) removed (zero/missing exposure)", n_removed)
    else ""
  ))

  if (!has_year && n_years == 1L) {
    message(paste0(
      "  [loadFundData] Single-year format detected.\n",
      "  For multi-year data, use long format: one row per (year, age) cell,\n",
      "  with a 'year' column — stacking all years vertically."
    ))
  }

  out
}
