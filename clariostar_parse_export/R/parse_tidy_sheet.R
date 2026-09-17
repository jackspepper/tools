#' Parse the "Table All Data points" sheet
#'
#' This export sheet is already tidy (one row per well) but has a metadata
#' preamble above the table, and the "Well" header needs to be located
#' dynamically since export layouts can shift row/column position.
#'
#' @param data_all A data frame as read by [readxl::read_excel()] with
#'   `col_names = FALSE`, for the "Table All Data points" sheet.
#' @param filename Character; source filename, used in error messages only.
#'
#' @return A tidy data frame with one row per well, plus derived `row` and
#'   `col` columns parsed from `Well`.
#' @keywords internal
#' @noRd
parse_tidy_sheet <- function(data_all, filename) {

  pos <- which(data_all == "Well", arr.ind = TRUE)

  if (nrow(pos) == 0) {
    stop(sprintf(
      "'Well' not found in 'Table All Data points'. Re-check or re-export the data and try again.
      Errored File: %s", filename
    ))
  }

  start_row <- pos[1, "row"]
  start_col <- pos[1, "col"]

  sub_data <- data_all[start_row:nrow(data_all), start_col:ncol(data_all)]

  empty_rows <- apply(sub_data, 1, function(x) all(is.na(x) | trimws(as.character(x)) == ""))
  end_row <- if (any(empty_rows)) start_row + which(empty_rows)[1] - 2 else nrow(data_all)

  empty_cols <- apply(sub_data, 2, function(x) all(is.na(x) | trimws(as.character(x)) == ""))
  end_col <- if (any(empty_cols)) start_col + which(empty_cols)[1] - 2 else ncol(data_all)

  data_table <- data_all[start_row:end_row, start_col:end_col, drop = FALSE]

  if (nrow(data_table) <= 1 || ncol(data_table) <= 1) {
    stop(sprintf(
      "Detected table is unexpectedly small (%d rows x %d columns).
      Errored File: %s", nrow(data_table), ncol(data_table), filename
    ))
  }

  header <- as.character(unlist(data_table[1, ]))
  body <- data_table[-1, ]
  names(body) <- make.unique(header, sep = "_")

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
