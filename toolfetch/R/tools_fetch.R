#' Is a path absolute? (handles POSIX and Windows drive-letter/UNC paths)
#' @keywords internal
fs_is_absolute <- function(path) {
  grepl("^(/|~|[A-Za-z]:[\\\\/]|\\\\\\\\)", path)
}

#' Download a folder recursively via the GitHub contents API
#' @keywords internal
tf_download_folder <- function(folder_name, dest_dir, quiet = FALSE) {
  cfg <- tf_repo()

  fetch_entries <- function(path) {
    url <- sprintf(
      "https://api.github.com/repos/%s/%s/contents/%s?ref=%s",
      cfg$owner, cfg$repo, utils::URLencode(path), cfg$branch
    )
    resp <- httr2::request(url) |>
      httr2::req_headers(Accept = "application/vnd.github+json") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    if (httr2::resp_status(resp) >= 400) {
      stop(
        "Failed to read '", path, "' (HTTP ", httr2::resp_status(resp), ").",
        call. = FALSE
      )
    }
    httr2::resp_body_json(resp)
  }

  # Recursively collect every file entry under folder_name
  collect_files <- function(path) {
    entries <- fetch_entries(path)
    files <- list()
    for (e in entries) {
      if (identical(e$type, "file")) {
        files[[length(files) + 1]] <- e
      } else if (identical(e$type, "dir")) {
        files <- c(files, collect_files(e$path))
      }
    }
    files
  }

  if (!quiet) message("Fetching file list for '", folder_name, "'...")
  files <- collect_files(folder_name)

  if (length(files) == 0) {
    stop("No files found in '", folder_name, "'.", call. = FALSE)
  }

  if (!dir.exists(dest_dir)) dir.create(dest_dir, recursive = TRUE)

  for (f in files) {
    # relative path inside the folder, e.g. "subdir/script.R"
    rel_path <- sub(paste0("^", folder_name, "/?"), "", f$path)
    out_path <- file.path(dest_dir, rel_path)
    out_dir  <- dirname(out_path)
    if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

    if (!quiet) message("  downloading ", rel_path)
    utils::download.file(
      f$download_url, out_path,
      mode = "wb", quiet = TRUE
    )
  }

  invisible(dest_dir)
}

#' Interactively pick and download a tool folder from jackspepper/tools
#'
#' Lists the top-level folders in the repo (via cache, refreshed weekly or
#' on demand), presents a numbered menu, and downloads the chosen folder's
#' files into the current working directory.
#'
#' @param folder Character. Skip the interactive menu and fetch this folder
#'   name directly. If `NULL` (default), an interactive menu is shown.
#' @param subfolder Logical or character. If `TRUE` (default), files are
#'   placed in a new subfolder named after the tool, under `base_dir`
#'   (`<base_dir>/<folder>/...`). If `FALSE`, files are placed as-is directly
#'   into `base_dir`. If a character string, it's used as the subfolder path
#'   (relative to `base_dir` unless absolute) instead of the tool's name —
#'   e.g. `subfolder = "temp"` writes to `<base_dir>/temp/...`.
#' @param base_dir Character. Directory that `subfolder` is resolved against.
#'   Defaults to the current working directory (`getwd()`).
#' @param refresh Logical. Force a recheck of the repo's folder list before
#'   showing the menu, ignoring the weekly cache.
#' @param browse Logical. Instead of downloading directly, open
#'   download-directory.github.io in the browser for the chosen folder and
#'   let the user download the zip manually.
#' @param quiet Logical. Suppress status messages.
#'
#' @return Invisibly, the path the files were written to.
#' @export
#'
#' @examples
#' \dontrun{
#' # Interactive menu, files placed in ./<tool_name>/
#' tools_fetch()
#'
#' # Skip the menu, fetch a specific folder as-is into the cwd
#' tools_fetch("incucyte_parse_confluency", subfolder = FALSE)
#'
#' # Download into ./temp/ instead of ./<tool_name>/
#' tools_fetch(subfolder = "temp")
#'
#' # Force a recheck of the repo first
#' tools_fetch(refresh = TRUE)
#' }
tools_fetch <- function(folder = NULL,
                        subfolder = TRUE,
                        base_dir = getwd(),
                        refresh = FALSE,
                        browse = FALSE,
                        quiet = FALSE) {
  folders <- tf_get_folders(force = refresh, quiet = quiet)

  if (is.null(folder)) {
    cat("Available tools in jackspepper/tools:\n\n")
    for (i in seq_along(folders)) {
      cat(sprintf("%2d. %s\n", i, folders[i]))
    }
    cat("\n")

    choice <- readline("Enter a number to download (or 0 to cancel): ")
    choice_num <- suppressWarnings(as.integer(choice))

    if (is.na(choice_num) || choice_num == 0) {
      message("Cancelled.")
      return(invisible(NULL))
    }
    if (choice_num < 1 || choice_num > length(folders)) {
      stop("Invalid selection: ", choice, call. = FALSE)
    }
    folder <- folders[choice_num]
  } else if (!folder %in% folders) {
    stop(
      "'", folder, "' is not a top-level folder in ", tf_repo()$owner, "/", tf_repo()$repo,
      ". Run tools_list() to see available folders (or tools_list(refresh = TRUE)).",
      call. = FALSE
    )
  }

  if (isTRUE(browse)) {
    cfg <- tf_repo()
    tree_url <- sprintf(
      "https://github.com/%s/%s/tree/%s/%s",
      cfg$owner, cfg$repo, cfg$branch, folder
    )
    dl_url <- sprintf(
      "https://download-directory.github.io/?url=%s&filename=%s",
      utils::URLencode(tree_url, reserved = TRUE), folder
    )
    if (!quiet) message("Opening browser to download '", folder, "'...")
    utils::browseURL(dl_url)
    return(invisible(dl_url))
  }

  if (isTRUE(subfolder)) {
    dest_dir <- file.path(base_dir, folder)
  } else if (identical(subfolder, FALSE)) {
    dest_dir <- base_dir
  } else if (is.character(subfolder) && length(subfolder) == 1) {
    dest_dir <- if (fs_is_absolute(subfolder)) subfolder else file.path(base_dir, subfolder)
  } else {
    stop("`subfolder` must be TRUE, FALSE, or a single path string.", call. = FALSE)
  }

  # Only prompt when writing flat into base_dir with no dedicated subfolder,
  # since that's the case most likely to clobber unrelated files.
  if (identical(subfolder, FALSE) && interactive() && !isTRUE(quiet)) {
    ok <- readline(sprintf(
      "This will write '%s' files directly into %s. Continue? [y/N]: ",
      folder, dest_dir
    ))
    if (!tolower(ok) %in% c("y", "yes")) {
      message("Cancelled.")
      return(invisible(NULL))
    }
  }

  tf_download_folder(folder, dest_dir, quiet = quiet)

  if (!quiet) message("Done. '", folder, "' written to: ", dest_dir)
  invisible(dest_dir)
}
