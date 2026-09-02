#' Parse the "Microplate End point" sheet
#'
#' This export sheet is a stack of labelled 8x12 (or similar) matrices, one
#' per measure (e.g. `"1. Raw Data (590)"`, `"2. Average over
#' replicates..."`, `"5. good / bad based on %CV"`, etc). Each matrix is
#' preceded by a title row and a numeric column-header row (1..ncol), then
#' row-labelled (A, B, C...) data rows, terminated by a blank row (or the
#' end of sheet, for the final block).
#'
#' @param data_all A data frame as read by [readxl::read_excel()] with
#'   `col_names = FALSE`, for the "Microplate End point" sheet.
#' @param filename Character; source filename, used in error messages only.
#'
#' @return A tidy long-format data frame with one row per well per measure,
#'   with columns `well`, `plate_row`, `plate_col`, `measure`,
#'   `value_numeric`, `value_flag`.
#' @keywords internal
#' @noRd
parse_matrix_sheet <- function(data_all, filename) {

  col1 <- as.character(data_all[[2]])  # titles live in column 2 in this export

  # Title rows look like "1. Raw Data  (590)" - i.e. start with a digit + "."
  title_idx <- which(grepl("^[0-9]+\\.\\s", col1))

  if (length(title_idx) == 0) {
    stop(sprintf(
      "No measure blocks (e.g. '1. Raw Data') found in 'Microplate End point'. Re-check or re-export and try again.
      Errored File: %s", filename
    ))
  }

  blocks <- list()

  for (i in seq_along(title_idx)) {

    title_row <- title_idx[i]
    measure_name <- stringr::str_trim(stringr::str_remove(col1[title_row], "^[0-9]+\\.\\s*"))

    # column header row (well column numbers) is immediately below the title
    header_row_idx <- title_row + 1
    col_headers <- data_all[header_row_idx, ]
    col_headers <- as.character(unlist(col_headers))

    numeric_cols <- which(!is.na(suppressWarnings(as.numeric(col_headers))))
    if (length(numeric_cols) == 0) next  # not a real data block, skip

    data_start <- header_row_idx + 1
    # find first blank row after data_start (row-label column is col 1)
    row_labels_all <- as.character(data_all[[1]])
    remaining <- seq(data_start, nrow(data_all))
    blank_after <- remaining[which(is.na(row_labels_all[remaining]) | trimws(row_labels_all[remaining]) == "")]
    data_end <- if (length(blank_after) > 0) blank_after[1] - 1 else nrow(data_all)

    block <- data_all[data_start:data_end, c(1, numeric_cols)]
    names(block) <- c("plate_row", as.character(col_headers[numeric_cols]))

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

  # value column mixes numerics ("failed"/"passed" flags stay character)
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
