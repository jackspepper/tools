#' Read a BMG CLARIOstar CSV export
#'
#' Parses a CLARIOstar plate reader CSV export into a tidy long-format
#' data frame plus parsed run metadata. This is a separate entry point
#' from [read_clariostar()] because the CSV export packages both the
#' stacked measure matrices (like the Excel `"Microplate End point"`
#' sheet) and the tidy per-well table (like the Excel `"Table All Data
#' points"` sheet) into a single ragged, comma-delimited file, along with
#' instrument settings and a run log that this function ignores.
#'
#' @param path_csv Path to the `.csv` file exported from the CLARIOstar
#'   control software.
#'
#' @return A list with elements:
#' \describe{
#'   \item{metadata}{Named list of run metadata parsed from the export
#'     header (User, Path, Test run no., Test name, Date, Time, ID1, ...).}
#'   \item{data}{Tidy long-format data frame, sourced from the
#'     `"Well,Content,..."` table when present, otherwise from the
#'     parsed measure matrices.}
#'   \item{matrix_data}{Tidy long-format data frame parsed from the
#'     stacked measure matrices, or `NULL` if none are found.}
#'   \item{format_used}{Character; `"tidy"` or `"matrix"`, indicating
#'     which section became `data`.}
#'   \item{parse_info}{Named list of parse-time tracking metadata: the
#'     source filename, package version, and parse timestamp.}
#' }
#'
#' @examples
#' \dontrun{
#' result <- read_clariostar_csv("ClarioSTAR_Export.csv")
#' result$metadata
#' result$data
#' result$parse_info
#' }
#'
#' @export
read_clariostar_csv <- function(path_csv) {
  if (!file.exists(path_csv)) {
    stop(sprintf("File not found: %s", path_csv))
  }

  filename <- basename(path_csv)

  # CLARIOstar CSV exports are typically Windows-1252 encoded with CRLF
  # line endings; readLines handles CRLF fine, and encoding only matters
  # for the occasional degree sign / non-ASCII character in settings text,
  # which is outside every section this function parses.
  lines <- readLines(path_csv, warn = FALSE)
  rows <- strsplit(lines, ",")

  meta <- parse_metadata_csv(lines)

  matrix_data <- tryCatch(
    parse_matrix_sheet_csv(rows, filename),
    error = function(e) NULL
  )

  tidy_data <- parse_tidy_sheet_csv(rows, filename)

  if (is.null(tidy_data) && is.null(matrix_data)) {
    stop(sprintf(
      "This function cannot process CSV exports with neither a 'Well,Content' tidy table nor recognisable measure matrices.
      Please re-export data from the ClarioSTAR and try again.
      Errored File: %s",
      filename
    ))
  }

  result <- list(
    metadata = meta,
    data = NULL,
    matrix_data = matrix_data,
    format_used = NULL,
    parse_info = list(
      source_file = filename,
      source_path = path_csv,
      package_version = as.character(utils::packageVersion("clariostarparser")),
      parsed_at = Sys.time()
    )
  )

  if (!is.null(tidy_data)) {
    result$data <- tidy_data
    result$format_used <- "tidy"
  } else {
    result$data <- matrix_data
    result$format_used <- "matrix"
  }

  result
}
