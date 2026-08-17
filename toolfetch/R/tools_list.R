#' List available tool folders in jackspepper/tools
#'
#' Returns the top-level folder names in the repo. Uses a local cache that
#' refreshes automatically once a week; pass `refresh = TRUE` to force a
#' recheck against GitHub right now.
#'
#' @param refresh Logical. Force a recheck against GitHub, ignoring the cache.
#' @param max_age_days Numeric. Cache max age in days before it's considered
#'   stale (default 7).
#' @param quiet Logical. Suppress status messages.
#'
#' @return Character vector of folder names, invisibly returned and also
#'   printed.
#' @export
#'
#' @examples
#' \dontrun{
#' tools_list()
#' tools_list(refresh = TRUE)
#' }
tools_list <- function(refresh = FALSE, max_age_days = 7, quiet = FALSE) {
  folders <- tf_get_folders(force = refresh, max_age_days = max_age_days, quiet = quiet)
  if (!quiet) {
    for (i in seq_along(folders)) {
      cat(sprintf("%2d. %s\n", i, folders[i]))
    }
  }
  invisible(folders)
}

#' Force a recheck of the repo, refreshing the local cache
#'
#' Shorthand for `tools_list(refresh = TRUE)`.
#'
#' @param quiet Logical. Suppress status messages.
#' @return Character vector of folder names, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' tools_refresh()
#' }
tools_refresh <- function(quiet = FALSE) {
  tools_list(refresh = TRUE, quiet = quiet)
}
