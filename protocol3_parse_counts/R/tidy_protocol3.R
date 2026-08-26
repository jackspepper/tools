#' Flatten a parse_protocol3() result into one tidy data frame
#'
#' Combines every plate's `data` table into a single long-format data frame,
#' with the plate's metadata (Plate Name, User, Created, Comments / Notes,
#' Parser Version, and any name_components columns) repeated on every row.
#'
#' @param plates Output of \code{\link{parse_protocol3}} or
#'   \code{\link{parse_protocol3_abx}} (the per-plate list, or the wrapper
#'   list returned when using `exclude`).
#'
#' @return A single data frame: one row per Sector/well, with metadata columns
#'   joined in. If present, `Flags_list` is kept as a list-column. Audit
#'   attributes `parser_version` and `parsed_at` are attached if present.
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
  # Handle both plain plate list and exclusion wrapper ($included)
  plates_list <- if ("included" %in% names(plates) && is.list(plates$included)) {
    plates$included
  } else {
    plates
  }

  rows <- lapply(plates_list, function(p) {
    cbind(
      p$metadata[rep(1, nrow(p$data)), , drop = FALSE],
      p$data,
      row.names = NULL
    )
  })
  res <- do.call(rbind, rows)

  if (!is.null(attr(plates, "parser_version"))) {
    attr(res, "parser_version") <- attr(plates, "parser_version")
  }
  if (!is.null(attr(plates, "parsed_at"))) {
    attr(res, "parsed_at") <- attr(plates, "parsed_at")
  }

  res
}
