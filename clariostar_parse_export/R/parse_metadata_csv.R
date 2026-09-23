#' Parse the run metadata block from a CLARIOstar CSV export
#'
#' The CSV export packs several `"Key: Value"` pairs per line (comma
#' separated) in its first few lines, unlike the Excel export which puts
#' one pair per row in column 1. Only the first colon in each field is
#' treated as the key/value separator, so values that themselves contain
#' colons (e.g. a Windows path's drive letter) are preserved intact.
#'
#' @param lines Character vector of raw lines from the CSV export (as read
#'   by [readLines()]), before any delimiter splitting.
#'
#' @return A named list of metadata key/value pairs.
#' @keywords internal
#' @noRd
parse_metadata_csv <- function(lines) {

  header_lines <- lines[seq_len(min(15, length(lines)))]
  header_lines <- header_lines[!is.na(header_lines) & trimws(header_lines) != ""]

  meta <- list()
  for (line in header_lines) {
    fields <- strsplit(line, ",")[[1]]
    for (field in fields) {
      if (!grepl(":", field)) next
      parts <- stringr::str_split_fixed(field, ":", 2)
      key <- stringr::str_trim(parts[1, 1])
      val <- stringr::str_trim(parts[1, 2])
      if (nchar(key) > 0 && nchar(val) > 0) {
        meta[[key]] <- val
      }
    }
  }

  meta
}
