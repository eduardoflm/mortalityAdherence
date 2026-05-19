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
#' @param col_age \code{character} — name of the age column in the file.
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
#' @return A \code{data.frame} with columns \code{age}, \code{exposed}, and
#'   \code{deaths}, sorted by age. Rows with zero or missing exposure are
#'   removed automatically.
#'
#' @details
#' Reading Excel files (\code{.xlsx} or \code{.xls}) requires the
#' \pkg{readxl} package:
#' \code{install.packages("readxl")}.
#'
#' For Brazilian CSV files (semicolon separator, comma decimal), use:
#' \code{loadFundData("file.csv", sep = ";", dec = ",")}
#'
#' @examples
#' \dontrun{
#' # Standard CSV
#' data <- loadFundData("experience.csv")
#'
#' # Brazilian-format CSV
#' data <- loadFundData("experiencia.csv", sep = ";", dec = ",",
#'                       col_age = "Idade", col_exposed = "Expostos",
#'                       col_deaths = "Obitos")
#'
#' # Excel file
#' data <- loadFundData("fund_data.xlsx",
#'                       col_age     = "FxEtaria",
#'                       col_exposed = "ExpostoRisco",
#'                       col_deaths  = "Mortes",
#'                       sheet       = "Mortalidade")
#' }
#'
#' @export
loadFundData <- function(file,
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

  # Verify requested columns exist
  for (col in c(col_age, col_exposed, col_deaths)) {
    if (!col %in% names(raw))
      stop(sprintf(
        "Column '%s' not found. Available columns: %s",
        col, paste(names(raw), collapse = ", ")
      ))
  }

  out <- data.frame(
    age     = as.integer(raw[[col_age]]),
    exposed = as.numeric(raw[[col_exposed]]),
    deaths  = as.integer(raw[[col_deaths]]),
    stringsAsFactors = FALSE
  )

  # Remove invalid rows
  n_before <- nrow(out)
  out <- out[!is.na(out$age) & out$exposed > 0 & !is.na(out$deaths), ]
  out <- out[order(out$age), ]
  n_removed <- n_before - nrow(out)

  message(sprintf(
    "Fund data loaded: %d age group(s) | %s exposed | %d deaths%s",
    nrow(out),
    format(as.integer(sum(out$exposed)), big.mark = ","),
    sum(out$deaths),
    if (n_removed > 0) sprintf(" | %d row(s) removed (zero/missing exposure)", n_removed) else ""
  ))

  out
}
