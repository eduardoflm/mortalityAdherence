# =============================================================================
# Table catalogue and data loading (identical to the Python version)
# =============================================================================

.BUILT_IN_TABLES <- data.frame(
  name = c("AT-2000bm", "AT-2000m", "AT-49M", "AT-55m", "AT-83ms",
           "GAM71m", "GAM83m", "BR-EMS2010", "BR-EMS2015", "BR-EMS2021"),
  description = c(
    "American Table 2000 - Male Basic (SOA)",
    "American Table 2000 - Male (SOA)",
    "American Table 1949 - Male",
    "American Table 1955 - Male",
    "American Table 1983 - Male (smoothed)",
    "Group Annuity Mortality 1971 - Male (SOA)",
    "Group Annuity Mortality 1983 - Male (SOA)",
    "Brazilian Insurance Mortality Experience 2010 (BR-EMS)",
    "Brazilian Insurance Mortality Experience 2015 (BR-EMS)",
    "Brazilian Insurance Mortality Experience 2021 (BR-EMS)"),
  origin = c(rep("USA - Society of Actuaries", 7),
             rep("Brazil - SUSEP / insurance market", 3)),
  age_range = rep("0 - 120", 10),
  stringsAsFactors = FALSE
)


#' List Available Built-in Mortality Tables
#'
#' Returns a data frame describing the 10 mortality tables built into the
#' package.
#'
#' @return A \code{data.frame} with columns \code{name} (to pass to
#'   \code{\link{loadTable}()} or \code{\link{testAdherence}()}),
#'   \code{description}, \code{origin} and \code{age_range}.
#' @examples
#' listTables()
#' @export
listTables <- function() {
  .BUILT_IN_TABLES
}


#' Load a Built-in Mortality Table
#'
#' Returns one of the 10 built-in tables as a \code{data.frame} with columns
#' \code{age} (0 to 120) and \code{qx} (annual probability of death).
#'
#' @param name Name of the table; see \code{\link{listTables}()}.
#' @return A \code{data.frame} with columns \code{age} and \code{qx}.
#' @details The result can be modified (e.g. multiplied by a loading factor)
#'   and passed to \code{testAdherence(table = ...)}. Any external table works
#'   the same way, as long as it is a \code{data.frame} with columns
#'   \code{age} and \code{qx}.
#' @examples
#' tab <- loadTable("AT-2000m")
#' head(tab)
#' tab$qx <- tab$qx * 0.90   # a 10% deloaded table
#' plot(tab$age, tab$qx, type = "l", log = "y", xlab = "Age", ylab = "q(x)")
#' @export
loadTable <- function(name) {
  valid <- .BUILT_IN_TABLES$name
  if (!(is.character(name) && length(name) == 1L && name %in% valid))
    stop(sprintf("'%s' is not a recognised table name.\nAvailable tables: %s",
                 paste(name, collapse = ","), paste(valid, collapse = ", ")))
  mt <- get("mortality_tables", envir = asNamespace("mortalityAdherence"))
  col <- if (name %in% names(mt)) name else gsub("-", ".", name, fixed = TRUE)
  data.frame(age = as.integer(mt$age), qx = as.numeric(mt[[col]]))
}


#' Load Pension Fund Mortality Data from a File
#'
#' Reads a \code{.csv}, \code{.xlsx} or \code{.xls} file with pension fund
#' experience data and returns a \code{data.frame} ready for
#' \code{\link{testAdherence}()}.
#'
#' @param file Path to the file.
#' @param col_year Name of the year column (\code{NULL} to ignore it).
#' @param col_age,col_exposed,col_deaths Names of the age, exposed and deaths
#'   columns in the file.
#' @param sep,dec Field and decimal separators for CSV files. Brazilian CSV:
#'   \code{sep = ";", dec = ","}.
#' @param sheet Excel sheet (number, starting at 1, or name).
#' @param quiet Suppress the summary message.
#' @param ... Passed to \code{utils::read.csv()} or \code{readxl::read_excel()}.
#'
#' @return A \code{data.frame} with columns \code{year} (if found), \code{age},
#'   \code{exposed} and \code{deaths}; rows with missing values or zero
#'   exposure are removed.
#'
#' @details
#' The data must be in \strong{long (stacked) format}: one row per
#' (year, age) cell, with several years stacked one below the other (never
#' one column per year):
#' \preformatted{
#'   year  age  exposed  deaths
#'   2020   40      400       1
#'   2020   41      410       1
#'   2021   40      390       1
#'   2021   41      450       2
#' }
#' With a single year the \code{year} column is optional. Excel files need the
#' \pkg{readxl} package.
#'
#' @examples
#' \dontrun{
#' data <- loadFundData("experience.csv")
#' data <- loadFundData("experiencia.csv", sep = ";", dec = ",",
#'                      col_year = "Ano", col_age = "Idade",
#'                      col_exposed = "Expostos", col_deaths = "Obitos")
#' data <- loadFundData("fund.xlsx", sheet = "Mortalidade")
#' }
#' @export
loadFundData <- function(file, col_year = "year", col_age = "age",
                         col_exposed = "exposed", col_deaths = "deaths",
                         sep = ",", dec = ".", sheet = 1L, quiet = FALSE, ...) {
  if (!file.exists(file)) stop(sprintf("File not found: '%s'", file))
  ext <- tolower(tools::file_ext(file))
  if (ext == "csv") {
    raw <- utils::read.csv(file, sep = sep, dec = dec, stringsAsFactors = FALSE,
                           check.names = FALSE, ...)
  } else if (ext %in% c("xlsx", "xlsm", "xls")) {
    if (!requireNamespace("readxl", quietly = TRUE))
      stop("Package 'readxl' is required to read Excel files: install.packages('readxl')")
    raw <- as.data.frame(readxl::read_excel(file, sheet = sheet, ...))
  } else {
    stop(sprintf("Unsupported file extension '.%s'. Use .csv, .xlsx or .xls.", ext))
  }
  names(raw) <- trimws(names(raw))
  for (col in c(col_age, col_exposed, col_deaths))
    if (!col %in% names(raw))
      stop(sprintf("Column '%s' not found. Available columns: %s",
                   col, paste(names(raw), collapse = ", ")))

  has_year <- !is.null(col_year) && col_year %in% names(raw)
  num <- function(v) suppressWarnings(as.numeric(v))
  out <- data.frame(age = num(raw[[col_age]]), exposed = num(raw[[col_exposed]]),
                    deaths = num(raw[[col_deaths]]))
  if (has_year) out <- cbind(year = num(raw[[col_year]]), out)

  n_before <- nrow(out)
  out <- out[stats::complete.cases(out), , drop = FALSE]
  out <- out[out$exposed > 0, , drop = FALSE]
  n_removed <- n_before - nrow(out)
  out$age <- as.integer(out$age)
  if (has_year) {
    out$year <- as.integer(out$year)
    out <- out[order(out$year, out$age), , drop = FALSE]
  } else {
    out <- out[order(out$age), , drop = FALSE]
  }
  rownames(out) <- NULL

  if (!quiet) {
    msg <- sprintf("Fund data loaded: %d row(s) | %d unique age(s) | %s year(s) | %s exposed | %d deaths",
                   nrow(out), length(unique(out$age)),
                   if (has_year) as.character(length(unique(out$year))) else "no year column",
                   formatC(sum(out$exposed), format = "f", digits = 0, big.mark = ","),
                   as.integer(sum(out$deaths)))
    if (n_removed > 0)
      msg <- paste0(msg, sprintf(" | %d row(s) removed (zero/missing exposure or missing values)",
                                 n_removed))
    message(msg)
    if (!has_year && anyDuplicated(out$age) > 0)
      message(paste0("  Repeated ages without a year column: each row will be treated as an ",
                     "independent (year, age) cell."))
  }
  out
}
