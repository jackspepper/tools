#' Repo configuration
#' @keywords internal
tf_repo <- function() {
  list(owner = "jackspepper", repo = "tools", branch = "main")
}

#' Path to the local cache file
#' @keywords internal
tf_cache_path <- function() {
  dir <- tools::R_user_dir("toolfetch", "cache")
  if (!dir.exists(dir)) dir.create(dir, recursive = TRUE)
  file.path(dir, "folder_cache.rds")
}

#' Read the cache from disk, if present
#' @keywords internal
tf_cache_read <- function() {
  path <- tf_cache_path()
  if (!file.exists(path)) return(NULL)
  tryCatch(readRDS(path), error = function(e) NULL)
}

#' Write the cache to disk
#' @keywords internal
tf_cache_write <- function(folders) {
  saveRDS(
    list(folders = folders, fetched_at = Sys.time()),
    tf_cache_path()
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
#' @keywords internal
tf_fetch_folders_remote <- function() {
  cfg <- tf_repo()
  url <- sprintf(
    "https://api.github.com/repos/%s/%s/contents/?ref=%s",
    cfg$owner, cfg$repo, cfg$branch
  )

  resp <- httr2::request(url) |>
    httr2::req_headers(Accept = "application/vnd.github+json") |>
    httr2::req_error(is_error = function(resp) FALSE) |>
    httr2::req_perform()

  if (httr2::resp_status(resp) >= 400) {
    stop(
      "Failed to list folders from ", cfg$owner, "/", cfg$repo,
      " (HTTP ", httr2::resp_status(resp), "). ",
      "Check your network connection or GitHub API rate limit.",
      call. = FALSE
    )
  }

  entries <- httr2::resp_body_json(resp)
  is_dir <- vapply(entries, function(x) identical(x$type, "dir"), logical(1))
  names  <- vapply(entries[is_dir], function(x) x$name, character(1))
  sort(names)
}

#' Get the list of top-level folders, using cache unless stale or forced
#' @keywords internal
tf_get_folders <- function(force = FALSE, max_age_days = 7, quiet = FALSE) {
  cache <- tf_cache_read()

  if (force || tf_cache_stale(cache, max_age_days)) {
    if (!quiet) message("Checking ", tf_repo()$owner, "/", tf_repo()$repo, " for tool folders...")
    folders <- tf_fetch_folders_remote()
    tf_cache_write(folders)
    return(folders)
  }

  if (!quiet) {
    message(
      "Using cached folder list from ",
      format(cache$fetched_at, "%Y-%m-%d %H:%M"),
      " (use refresh = TRUE to recheck)"
    )
  }
  cache$folders
}
