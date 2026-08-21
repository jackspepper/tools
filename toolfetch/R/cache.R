#' Repo configuration
#'
#' `branch` is the default branch used when none is supplied elsewhere.
#' @keywords internal
tf_repo <- function() {
  list(owner = "jackspepper", repo = "tools", branch = "main")
}

#' Resolve a branch argument to a concrete branch name
#'
#' Centralises the "NULL means default branch" rule used everywhere a
#' `branch` argument is accepted.
#' @keywords internal
tf_resolve_branch <- function(branch = NULL) {
  if (is.null(branch) || identical(branch, "")) {
    return(tf_repo()$branch)
  }
  if (!is.character(branch) || length(branch) != 1) {
    stop("`branch` must be a single string or NULL.", call. = FALSE)
  }
  branch
}

#' Sanitise a branch name for safe use as a cache filename component
#' @keywords internal
tf_cache_branch_key <- function(branch) {
  gsub("[^A-Za-z0-9._-]+", "_", branch)
}

#' Path to the local cache file for a given branch's folder listing
#' @keywords internal
tf_cache_path <- function(branch = NULL) {
  branch <- tf_resolve_branch(branch)
  dir <- tools::R_user_dir("toolfetch", "cache")
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  file.path(dir, paste0("folder_cache_", tf_cache_branch_key(branch), ".rds"))
}

#' Path to the local cache file for the repo's branch listing
#' @keywords internal
tf_branch_cache_path <- function() {
  dir <- tools::R_user_dir("toolfetch", "cache")
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  file.path(dir, "branch_cache.rds")
}

#' Read the folder-list cache for a branch from disk, if present
#' @keywords internal
tf_cache_read <- function(branch = NULL) {
  path <- tf_cache_path(branch)
  if (!file.exists(path)) return(NULL)
  tryCatch(readRDS(path), error = function(e) NULL)
}

#' Write the folder-list cache for a branch to disk
#' @keywords internal
tf_cache_write <- function(folders, branch = NULL) {
  saveRDS(
    list(folders = folders, fetched_at = Sys.time()),
    tf_cache_path(branch)
  )
}

#' Read the branch-list cache from disk, if present
#' @keywords internal
tf_branch_cache_read <- function() {
  path <- tf_branch_cache_path()
  if (!file.exists(path)) return(NULL)
  tryCatch(readRDS(path), error = function(e) NULL)
}

#' Write the branch-list cache to disk
#' @keywords internal
tf_branch_cache_write <- function(branches) {
  saveRDS(
    list(branches = branches, fetched_at = Sys.time()),
    tf_branch_cache_path()
  )
}

#' Is the cache stale (older than max_age_days, or missing)?
#' @keywords internal
tf_cache_stale <- function(cache, max_age_days = 7) {
  if (is.null(cache)) return(TRUE)
  age <- difftime(Sys.time(), cache$fetched_at, units = "days")
  age > max_age_days
}

#' Query the GitHub contents API for top-level folders in the repo
#' @param branch Character. Branch to list folders on. `NULL` uses the
#'   default branch (see `tf_repo()`).
#' @keywords internal
tf_fetch_folders_remote <- function(branch = NULL) {
  branch <- tf_resolve_branch(branch)
  cfg <- tf_repo()
  url <- sprintf(
    "https://api.github.com/repos/%s/%s/contents/?ref=%s",
    cfg$owner, cfg$repo, utils::URLencode(branch)
  )

  resp <- httr2::request(url) |>
    httr2::req_headers(Accept = "application/vnd.github+json") |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    stop(
      "Failed to list folders from ", cfg$owner, "/", cfg$repo,
      " on branch '", branch, "' (HTTP ", httr2::resp_status(resp), "). ",
      "Check the branch name, your network connection, or GitHub API rate limit.",
      call. = FALSE
    )
  }

  entries <- httr2::resp_body_json(resp)
  is_dir <- vapply(entries, function(x) identical(x$type, "dir"), logical(1))
  names  <- vapply(entries[is_dir], function(x) x$name, character(1))
  sort(names)
}

#' Get the list of top-level folders, using cache unless stale or forced
#' @param branch Character. Branch to list folders on. `NULL` uses the
#'   default branch. Each branch is cached separately.
#' @keywords internal
tf_get_folders <- function(branch = NULL, force = FALSE, max_age_days = 7, quiet = FALSE) {
  branch <- tf_resolve_branch(branch)
  cache <- tf_cache_read(branch)

  if (force || tf_cache_stale(cache, max_age_days)) {
    if (!quiet) {
      message(
        "Checking ", tf_repo()$owner, "/", tf_repo()$repo,
        " (branch: ", branch, ") for tool folders..."
      )
    }
    folders <- tf_fetch_folders_remote(branch)
    tf_cache_write(folders, branch)
    return(folders)
  }

  if (!quiet) {
    message(
      "Using cached folder list for branch '", branch, "' from ",
      format(cache$fetched_at, "%Y-%m-%d %H:%M"),
      " (use refresh = TRUE to recheck)"
    )
  }
  cache$folders
}

#' Query the GitHub API for branches in the repo
#' @keywords internal
tf_fetch_branches_remote <- function() {
  cfg <- tf_repo()
  url <- sprintf(
    "https://api.github.com/repos/%s/%s/branches?per_page=100",
    cfg$owner, cfg$repo
  )

  branches <- character(0)
  page <- 1
  repeat {
    resp <- httr2::request(url) |>
      httr2::req_headers(Accept = "application/vnd.github+json") |>
      httr2::req_url_query(page = page) |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    if (httr2::resp_status(resp) >= 400) {
      stop(
        "Failed to list branches from ", cfg$owner, "/", cfg$repo,
        " (HTTP ", httr2::resp_status(resp), "). ",
        "Check your network connection or GitHub API rate limit.",
        call. = FALSE
      )
    }

    entries <- httr2::resp_body_json(resp)
    if (length(entries) == 0) break

    names <- vapply(entries, function(x) x$name, character(1))
    branches <- c(branches, names)

    if (length(entries) < 100) break
    page <- page + 1
  }

  sort(branches)
}

#' Get the list of branches, using cache unless stale or forced
#' @keywords internal
tf_get_branches <- function(force = FALSE, max_age_days = 7, quiet = FALSE) {
  cache <- tf_branch_cache_read()

  if (force || tf_cache_stale(cache, max_age_days)) {
    if (!quiet) {
      message("Checking ", tf_repo()$owner, "/", tf_repo()$repo, " for branches...")
    }
    branches <- tf_fetch_branches_remote()
    tf_branch_cache_write(branches)
    return(branches)
  }

  if (!quiet) {
    message(
      "Using cached branch list from ",
      format(cache$fetched_at, "%Y-%m-%d %H:%M"),
      " (use refresh = TRUE to recheck)"
    )
  }
  cache$branches
}
