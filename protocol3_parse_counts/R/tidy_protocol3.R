#' Flatten a parse_protocol3() result into one tidy data frame
#'
#' Combines every plate's `data` table into a single long-format data frame,
#' with the plate's metadata (Plate Name, User, Created, Comments / Notes,
#' and any name_components columns) repeated on every row.
#'
#' @param plates Output of \code{\link{parse_protocol3}} or
#'   \code{\link{parse_protocol3_abx}} (the per-plate list; if you filtered
#'   with `exclude`, pass `result$included` or `result$excluded`, not the
#'   wrapper itself).
#'
#' @return A single data frame: one row per Sector/well, with metadata columns
#'   joined in. If present, `Flags_list` is kept as a list-column.
#'
#' @examples
#' file <- system.file(
#'   "extdata",
#'   "ExampleCounts.ods",
#'   package = "protocol3Parser"
#' )
#'
#' plates <- parse_protocol3(
#'   file,
#'   name_components = c("Date", "BacTime", "Subject", "PlateID")
#' )
#' tidy_data <- tidy_protocol3(plates)
#'
#' @export
tidy_protocol3 <- function(plates) {
  rows <- lapply(plates, function(p) {
    cbind(
      p$metadata[rep(1, nrow(p$data)), , drop = FALSE],
      p$data,
      row.names = NULL
    )
  })
  do.call(rbind, rows)
}
