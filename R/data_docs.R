#' Built-in Mortality Tables
#'
#' A data frame containing annual probabilities of death (\eqn{q_x}) for
#' 10 biometric mortality tables commonly used in the Brazilian actuarial market.
#'
#' @format A \code{data.frame} with 121 rows (ages 0 to 120) and 11 columns:
#' \describe{
#'   \item{age}{Integer age from 0 to 120.}
#'   \item{AT-2000bm}{American Table 2000 — Male Beneficiaries (Society of Actuaries).}
#'   \item{AT-2000m}{American Table 2000 — Male (Society of Actuaries).}
#'   \item{AT-49M}{American Table 1949 — Male.}
#'   \item{AT-55m}{American Table 1955 — Male.}
#'   \item{AT-83ms}{American Table 1983 — Male (smoothed).}
#'   \item{GAM71m}{Group Annuity Mortality Table 1971 — Male (SOA).}
#'   \item{GAM83m}{Group Annuity Mortality Table 1983 — Male (SOA).}
#'   \item{BR-EMS2010}{Brazilian Mortality Experience Table 2010 (FenaPrevi/SUSEP).}
#'   \item{BR-EMS2015}{Brazilian Mortality Experience Table 2015 (FenaPrevi/SUSEP).}
#'   \item{BR-EMS2021}{Brazilian Mortality Experience Table 2021 (FenaPrevi/SUSEP).}
#' }
#'
#' @details
#' All values represent \eqn{q_x}: the probability that a life aged exactly
#' \eqn{x} dies before reaching age \eqn{x+1}.
#'
#' The AT-2000 tables are widely used as regulatory benchmarks for Brazilian
#' pension funds under PREVIC (Superintendência Nacional de Previdência
#' Complementar) supervision. The BR-EMS tables were constructed from domestic
#' insurance and annuity experience and are particularly relevant for
#' Brazilian demographic conditions.
#'
#' Use \code{\link{listTables}()} for a human-readable catalogue and
#' \code{\link{loadTable}()} to extract any single table as a tidy data frame.
#'
#' @source
#' \itemize{
#'   \item AT-2000, GAM tables: Society of Actuaries (SOA), USA.
#'   \item BR-EMS tables: FenaPrevi / SUSEP, Brazil.
#' }
#'
#' @seealso \code{\link{listTables}}, \code{\link{loadTable}}
#'
#' @examples
#' data(mortality_tables)
#' head(mortality_tables[, 1:4])
#'
#' # Compare q_x at age 65 across all tables
#' as.data.frame(mortality_tables[mortality_tables$age == 65, ])
#'
#' # Plot all 10 curves
#' matplot(mortality_tables$age,
#'         log(mortality_tables[, -1]),
#'         type = "l", lty = 1,
#'         xlab = "Age", ylab = expression(log(q[x])),
#'         main = "Built-in Mortality Tables — mortalityAdherence")
#' legend("topleft", legend = names(mortality_tables)[-1],
#'        col = seq_len(10), lty = 1, cex = 0.7, bty = "n")
#'
"mortality_tables"
