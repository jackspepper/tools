#' Read a BMG CLARIOstar Excel export
#'
#' Parses a CLARIOstar plate reader Excel export into a tidy long-format
#' data frame plus parsed run metadata, regardless of which export sheet(s)
#' are present:
#'
#' * `"Table All Data points"` -- already tidy, one row per well
#' * `"Microplate End point"` -- stacked 8x12 plate matrices, one per
#'   calculated measure (Raw Data, Average, Median, %CV, good/bad,
#'   Difference, ...)
#'
#' If both sheets are present, `"Table All Data points"` is used as the
#' primary tidy output (it is the authoritative long format) and the
#' matrix sheet is parsed as a cross-check / fallback source. If only one
#' sheet is present, that one is parsed directly.
#'
#' @param path_workbook Path to the `.xlsx` file exported from the
#'   CLARIOstar control software.
#'
#' @return A list with elements:
#' \describe{
#'   \item{metadata}{Named list of run metadata parsed from the export
#'     header (User, Path, Test ID, Test Name, Date, Time, ID1, ...).}
#'   \item{data}{Tidy long-format data frame. Sourced from
#'     `"Table All Data points"` when present, otherwise from
#'     `"Microplate End point"`.}
#'   \item{matrix_data}{Tidy long-format data frame parsed from
#'     `"Microplate End point"`, or `NULL` if that sheet is absent.}
#'   \item{format_used}{Character; `"tidy"` or `"matrix"`, indicating
#'     which sheet became `data`.}
#'   \item{parse_info}{Named list of parse-time tracking metadata: the
#'     source filename, sheets found, package version, and parse
#'     timestamp. See Details.}
#' }
#'
#' @details
#' `parse_info` is intended to make parsed objects traceable back to their
#' source file and the package version that produced them, which matters
#' once outputs are cached, shared, or fed into downstream pipelines.
#' It contains:
#' \describe{
#'   \item{source_file}{`basename()` of `path_workbook`.}
#'   \item{source_path}{The path as supplied.}
#'   \item{sheets_found}{Character vector of sheet names in the workbook.}
#'   \item{package_version}{Installed version of clariostarparser, as a
#'     string.}
#'   \item{parsed_at}{`Sys.time()` at parse, as a POSIXct.}
#' }
#'
#' @examples
#' \dontrun{
#' result <- read_clariostar("ClarioSTAR_Export.xlsx")
#' result$metadata
#' result$data
#' result$parse_info
#' }
#'
#' @export
read_clariostar <- function(path_workbook) {
  if (!file.exists(path_workbook)) {
    stop(sprintf("File not found: %s", path_workbook))
  }

  filename <- basename(path_workbook)
  data_sheets <- readxl::excel_sheets(path_workbook)

  data_list <- list()
  for (sheet in data_sheets) {
    message(sprintf("Reading sheet: %s", sheet))
    data_list[[sheet]] <- readxl::read_excel(
      path_workbook,
      sheet = sheet,
      trim_ws = TRUE,
      .name_repair = "universal_quiet",
      col_names = FALSE
    )
  }

  has_tidy <- "Table All Data points" %in% data_sheets
  has_matrix <- "Microplate End point" %in% data_sheets

  if (!has_tidy && !has_matrix) {
    stop(sprintf(
      "This function cannot process exports missing both 'Table All Data points' and 'Microplate End point'.
      Please re-export data from the ClarioSTAR and try again.
      Errored File: %s",
      filename
    ))
  }

  # Metadata is duplicated (identically formatted) at the top of every sheet
  # in these exports, so grab it from whichever sheet we have.
  meta <- parse_metadata(data_list[[
    if (has_tidy) "Table All Data points" else "Microplate End point"
  ]])

  result <- list(
    metadata = meta,
    data = NULL,
    matrix_data = NULL,
    format_used = NULL,
    parse_info = list(
      source_file = filename,
      source_path = path_workbook,
      sheets_found = data_sheets,
      package_version = as.character(utils::packageVersion("clariostarparser")),
      parsed_at = Sys.time()
    )
  )

  if (has_tidy) {
    result$data <- parse_tidy_sheet(
      data_list[["Table All Data points"]],
      filename
    )
    result$format_used <- "tidy"
  }

  if (has_matrix) {
    result$matrix_data <- parse_matrix_sheet(
      data_list[["Microplate End point"]],
      filename
    )
    if (is.null(result$data)) {
      result$data <- result$matrix_data
      result$format_used <- "matrix"
    }
  }

  result
}
