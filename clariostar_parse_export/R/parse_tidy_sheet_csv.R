#' Parse the "Well, Content, ..." tidy table from a CLARIOstar CSV export
#'
#' Unlike the Excel export (where the tidy table and matrix blocks live on
#' separate sheets), the CSV export contains both in a single file: the
#' matrix blocks first, followed by a `"Well,Content,..."` tidy table
#' further down, then plate-reader settings and a run log. This locates
#' that tidy table by its `"Well"` header and reads it as a rectangular
#' block, terminated by the first blank row.
#'
#' @param rows A list of character vectors, one per raw CSV line, each
#'   already split on commas (fields not padded to a common length).
#' @param filename Character; source filename, used in error messages only.
#'
#' @return A tidy data frame with one row per well, plus derived `row` and
#'   `col` columns parsed from `Well`, or `NULL` if no `"Well,Content"`
#'   table is found.
#' @keywords internal
#' @noRd
parse_tidy_sheet_csv <- function(rows, filename) {

  get_field <- function(row, idx) {
    if (idx <= length(row)) row[idx] else NA_character_
  }

  col1 <- vapply(rows, get_field, character(1), idx = 1)
  header_idx <- which(trimws(col1) == "Well")

  if (length(header_idx) == 0) {
    return(NULL)
  }

  header_row <- header_idx[1]
  header <- rows[[header_row]]
  # Drop a trailing empty field left by a trailing comma in the export.
  if (length(header) > 0 && trimws(utils::tail(header, 1)) == "") {
    header <- header[-length(header)]
  }
  ncols <- length(header)

  data_start <- header_row + 1
  well_col <- vapply(rows, get_field, character(1), idx = 1)
  remaining <- seq(data_start, length(rows))
  blank_after <- remaining[which(is.na(well_col[remaining]) | trimws(well_col[remaining]) == "")]
  data_end <- if (length(blank_after) > 0) blank_after[1] - 1 else length(rows)

  if (data_end < data_start) {
    stop(sprintf(
      "'Well' header found but no data rows followed it in the CSV tidy table.
      Errored File: %s", filename
    ))
  }

  data_rows <- rows[data_start:data_end]
  body_list <- lapply(seq_len(ncols), function(col_idx) {
    vapply(data_rows, get_field, character(1), idx = col_idx)
  })
  names(body_list) <- make.unique(header, sep = "_")
  body <- as.data.frame(body_list, stringsAsFactors = FALSE, check.names = FALSE)

  # Coerce likely-numeric columns (everything except Well/Content/pass-fail flags)
  numeric_like <- !names(body) %in% c("Well", "Content") &
    !grepl("good / bad|good/bad", names(body), ignore.case = TRUE)

  body <- body %>%
    dplyr::mutate(dplyr::across(dplyr::all_of(names(body)[numeric_like]), ~ suppressWarnings(as.numeric(.x)))) %>%
    dplyr::mutate(
      row = stringr::str_extract(.data$Well, "^[A-Za-z]+"),
      col = as.integer(stringr::str_extract(.data$Well, "[0-9]+$"))
    ) %>%
    dplyr::relocate(.data$row, .data$col, .after = .data$Well)

  body
}
