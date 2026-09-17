#' Parse the run metadata block from a CLARIOstar export sheet
#'
#' Appears as `"Key: Value"` strings in column 1 of the first rows of every
#' sheet in a CLARIOstar export (User, Path, Test ID, Test Name, Date,
#' Time, ID1, ...). Only the first colon in each line is treated as the
#' key/value separator, so values that themselves contain colons (e.g. a
#' Windows path's drive letter) are preserved intact.
#'
#' @param sheet_data A data frame as read by [readxl::read_excel()] with
#'   `col_names = FALSE`, for one CLARIOstar export sheet.
#'
#' @return A named list of metadata key/value pairs.
#' @keywords internal
#' @noRd
parse_metadata <- function(sheet_data) {

  header_rows <- sheet_data[[1]][seq_len(min(15, nrow(sheet_data)))]
  header_rows <- header_rows[!is.na(header_rows)]

  kv_rows <- header_rows[grepl(":", header_rows)]

  meta <- list()
  for (line in kv_rows) {
    parts <- stringr::str_split_fixed(line, ":", 2)
    key <- stringr::str_trim(parts[1, 1])
    val <- stringr::str_trim(parts[1, 2])
    if (nchar(key) > 0) {
      meta[[key]] <- val
    }
  }

  meta
}
