#' Built-in Mortality Tables
#'
#' Annual probabilities of death (\eqn{q_x}) of 10 mortality / annuity tables
#' used in the Brazilian actuarial market, ages 0 to 120.
#'
#' @format A \code{data.frame} with 121 rows and 11 columns: \code{age} and
#'   one \eqn{q_x} column per table: \code{AT-2000bm}, \code{AT-2000m},
#'   \code{AT-49M}, \code{AT-55m}, \code{AT-83ms}, \code{GAM71m},
#'   \code{GAM83m}, \code{BR-EMS2010}, \code{BR-EMS2015}, \code{BR-EMS2021}.
#'
#' @details \eqn{q_x} is the probability that a life aged exactly \eqn{x} dies
#'   before reaching age \eqn{x + 1}. Use \code{\link{listTables}()} for the
#'   catalogue and \code{\link{loadTable}()} to extract one table.
#'
#' @source AT and GAM tables: Society of Actuaries (\url{https://mort.soa.org/}).
#'   BR-EMS tables: Brazilian insurance market experience, SUSEP
#'   (\url{https://www.gov.br/susep}).
#'
#' @seealso \code{\link{listTables}}, \code{\link{loadTable}}
#' @examples
#' head(mortality_tables[, 1:4])
#' mortality_tables[mortality_tables$age == 65, ]
#' matplot(mortality_tables$age, log(mortality_tables[, -1]), type = "l", lty = 1,
#'         xlab = "Age", ylab = "log q(x)")
#' @docType data
#' @usage NULL
#' @keywords datasets
#' @export
"mortality_tables"
