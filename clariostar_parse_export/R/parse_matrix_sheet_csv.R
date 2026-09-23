#' Parse the stacked measure matrices from a CLARIOstar CSV export
#'
#' The CSV export's matrix section has the same structure as the Excel
#' `"Microplate End point"` sheet -- a stack of labelled 8x12 (or similar)
#' matrices, one per measure (e.g. `"1. Layout"`, `"2. Raw Data (590)"`,
#' `"5. %CV over replicates..."`) -- except titles live in column 1 (not
#' column 2), and rows are ragged comma-separated text rather than a
#' rectangular data frame.
#'
#' Each matrix is preceded by a title row and a numeric column-header row
#' (1..ncol), then row-labelled (A, B, C...) data rows, terminated by a
#' blank row.
#'
#' @param rows A list of character vectors, one per raw CSV line, each
#'   already split on commas (fields not padded to a common length).
#' @param filename Character; source filename, used in error messages only.
#'
#' @return A tidy long-format data frame with one row per well per measure,
#'   with columns `well`, `plate_row`, `plate_col`, `measure`,
#'   `value_numeric`, `value_flag`.
#' @keywords internal
#' @noRd
parse_matrix_sheet_csv <- function(rows, filename) {

  get_field <- function(row, idx) {
    if (idx <= length(row)) row[idx] else NA_character_
  }

  # A genuine column-header row is a run of consecutive integers 1..N (the
  # plate columns), not just "contains a number" -- row-label columns
  # (A, B, C...) and data rows can otherwise be mistaken for one.
  is_col_header_row <- function(row) {
    vals <- suppressWarnings(as.numeric(row))
    vals <- vals[!is.na(vals)]
    if (length(vals) < 3) return(FALSE)
    isTRUE(all.equal(vals, seq_along(vals)))
  }

  col1 <- vapply(rows, get_field, character(1), idx = 1)

  is_candidate_title <- !is.na(col1) & trimws(col1) != "" &
    is.na(suppressWarnings(as.numeric(col1)))

  # The column-header row usually follows the title immediately, but the
  # CSV export sometimes inserts one blank line between them.
  header_offset <- vapply(seq_along(rows), function(i) {
    if (i + 1 <= length(rows) && is_col_header_row(rows[[i + 1]])) return(1L)
    if (i + 2 <= length(rows) && length(rows[[i + 1]]) == 0 &&
        is_col_header_row(rows[[i + 2]])) return(2L)
    0L
  }, integer(1))

  title_idx <- which(is_candidate_title & header_offset > 0)

  if (length(title_idx) == 0) {
    stop(sprintf(
      "No measure blocks (e.g. 'Raw Data' or '1. Raw Data') found in CSV matrix section. Re-check or re-export and try again.
      Errored File: %s", filename
    ))
  }

  blocks <- list()

  for (i in seq_along(title_idx)) {

    title_row <- title_idx[i]
    measure_name <- stringr::str_trim(stringr::str_remove(col1[title_row], "^[0-9]+\\.\\s*"))

    # column header row (well column numbers) follows the title, possibly
    # after one blank separator line
    header_row_idx <- title_row + header_offset[title_row]
    col_headers <- rows[[header_row_idx]]

    numeric_cols <- which(!is.na(suppressWarnings(as.numeric(col_headers))))
    if (length(numeric_cols) == 0) next  # not a real data block, skip

    data_start <- header_row_idx + 1
    row_labels_all <- vapply(rows, get_field, character(1), idx = 1)
    remaining <- seq(data_start, length(rows))
    blank_after <- remaining[which(is.na(row_labels_all[remaining]) | trimws(row_labels_all[remaining]) == "")]
    data_end <- if (length(blank_after) > 0) blank_after[1] - 1 else length(rows)

    if (data_end < data_start) next

    data_rows <- rows[data_start:data_end]
    plate_row <- vapply(data_rows, get_field, character(1), idx = 1)

    value_matrix <- lapply(numeric_cols, function(col_idx) {
      vapply(data_rows, get_field, character(1), idx = col_idx)
    })
    names(value_matrix) <- as.character(col_headers[numeric_cols])

    block <- data.frame(plate_row = plate_row, stringsAsFactors = FALSE)
    block <- cbind(block, as.data.frame(value_matrix, stringsAsFactors = FALSE, check.names = FALSE))

    block_long <- block %>%
      tidyr::pivot_longer(
        cols = -"plate_row",
        names_to = "plate_col",
        values_to = "value"
      ) %>%
      dplyr::mutate(
        well = paste0(.data$plate_row, stringr::str_pad(.data$plate_col, 2, pad = "0")),
        measure = measure_name
      ) %>%
      dplyr::select("well", "plate_row", "plate_col", "measure", "value")

    blocks[[measure_name]] <- block_long
  }

  if (length(blocks) == 0) {
    stop(sprintf(
      "Measure blocks were found but none contained parseable data.
      Errored File: %s", filename
    ))
  }

  combined <- dplyr::bind_rows(blocks)

  combined <- combined %>%
    dplyr::mutate(
      value_numeric = suppressWarnings(as.numeric(.data$value)),
      value = dplyr::if_else(is.na(.data$value_numeric) & !is.na(.data$value), .data$value, NA_character_)
    ) %>%
    dplyr::rename(value_flag = "value") %>%
    dplyr::relocate("value_numeric", .after = "measure") %>%
    dplyr::mutate(plate_col = as.integer(.data$plate_col))

  combined
}
