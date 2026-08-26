#' Split a ProtoCOL 3 "Flags" string into a vector
#'
#' ProtoCOL 3 stores multiple flags as a single space-separated string in the
#' `Flags` column (e.g. `"E M"`). This splits that string into a character
#' vector (e.g. `c("E", "M")`) so flags can be tested/filtered individually.
#'
#' @param flags Character vector (typically a `Flags` column).
#'
#' @return A list the same length as `flags`, each element a character vector
#'   of the individual flag tokens for that row (`character(0)` for NA/blank).
#'
#' @examples
#' split_flags(c("E M", "M", NA))
#'
#' @export
split_flags <- function(flags) {
  lapply(flags, function(x) {
    if (is.na(x) || !nzchar(trimws(x))) {
      character(0)
    } else {
      strsplit(trimws(x), "\\s+")[[1]]
    }
  })
}
