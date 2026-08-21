#' List available tool folders in jackspepper/tools
#'
#' Returns the top-level folder names in the repo. Uses a local cache that
#' refreshes automatically once a week; pass `refresh = TRUE` to force a
#' recheck against GitHub right now. Each branch is cached separately.
#'
#' @param branch Character. Branch to list folders on. `NULL` (default)
#'   uses the repo's default branch (`main`).
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
#' tools_list(branch = "dev")
#' tools_list(refresh = TRUE)
#' }
tools_list <- function(branch = NULL, refresh = FALSE, max_age_days = 7, quiet = FALSE) {
  folders <- tf_get_folders(
    branch = branch,
    force = refresh,
    max_age_days = max_age_days,
    quiet = quiet
  )
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
#' @param branch Character. Branch to refresh. `NULL` uses the default branch.
#' @param quiet Logical. Suppress status messages.
#' @return Character vector of folder names, invisibly.
#' @export
#'
#' @examples
#' \dontrun{
#' tools_refresh()
#' tools_refresh(branch = "dev")
#' }
tools_refresh <- function(branch = NULL, quiet = FALSE) {
  tools_list(branch = branch, refresh = TRUE, quiet = quiet)
}

#' List available branches in jackspepper/tools
#'
#' Returns branch names in the repo. Uses a local cache that refreshes
#' automatically once a week; pass `refresh = TRUE` to force a recheck.
#'
#' @param refresh Logical. Force a recheck against GitHub, ignoring the cache.
#' @param max_age_days Numeric. Cache max age in days before it's considered
#'   stale (default 7).
#' @param quiet Logical. Suppress status messages.
#'
#' @return Character vector of branch names, invisibly returned and also
#'   printed.
#' @export
#'
#' @examples
#' \dontrun{
#' tools_branches()
#' tools_branches(refresh = TRUE)
#' }
tools_branches <- function(refresh = FALSE, max_age_days = 7, quiet = FALSE) {
  branches <- tf_get_branches(force = refresh, max_age_days = max_age_days, quiet = quiet)
  default_branch <- tf_repo()$branch
  if (!quiet) {
    for (i in seq_along(branches)) {
      marker <- if (identical(branches[i], default_branch)) "  (default)" else ""
      cat(sprintf("%2d. %s%s\n", i, branches[i], marker))
    }
  }
  invisible(branches)
}
