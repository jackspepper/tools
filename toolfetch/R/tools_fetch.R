#' Is a path absolute? (handles POSIX and Windows drive-letter/UNC paths)
#' @keywords internal
fs_is_absolute <- function(path) {
  grepl("^(/|~|[A-Za-z]:[\\\\/]|\\\\\\\\)", path)
}

#' Download a folder recursively via the GitHub contents API
#'
#' Also detects whether the folder is an R package (a top-level DESCRIPTION
#' file present in the collected entries) and returns that alongside the
#' download path, so callers don't need a second API round-trip.
#'
#' @keywords internal
tf_download_folder <- function(
  folder_name,
  dest_dir,
  branch = NULL,
  quiet = FALSE,
  force = FALSE
) {
  cfg <- tf_repo()
  branch <- tf_resolve_branch(branch)

  fetch_entries <- function(path) {
    url <- sprintf(
      "https://api.github.com/repos/%s/%s/contents/%s?ref=%s",
      cfg$owner,
      cfg$repo,
      utils::URLencode(path),
      utils::URLencode(branch)
    )
    resp <- httr2::request(url) |>
      httr2::req_headers(Accept = "application/vnd.github+json") |>
      httr2::req_error(is_error = function(resp) FALSE) |>
      httr2::req_perform()

    if (httr2::resp_status(resp) >= 400) {
      stop(
        "Failed to read '",
        path,
        "' (HTTP ",
        httr2::resp_status(resp),
        ").",
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

  if (!quiet) {
    message("Fetching file list for '", folder_name, "'...")
  }
  files <- collect_files(folder_name)

  if (length(files) == 0) {
    stop("No files found in '", folder_name, "'.", call. = FALSE)
  }

  # Package detection: a DESCRIPTION file sitting directly at the folder root
  is_package <- any(vapply(
    files,
    function(f) identical(f$path, file.path(folder_name, "DESCRIPTION")),
    logical(1)
  ))

  dir_exists_already <- dir.exists(dest_dir)
  if (dir_exists_already && !force) {
    existing <- list.files(dest_dir, recursive = TRUE, all.files = FALSE)
    if (length(existing) > 0) {
      stop(
        "Destination '",
        dest_dir,
        "' already exists and is not empty. ",
        "Use force = TRUE to overwrite.",
        call. = FALSE
      )
    }
  }

  if (dir_exists_already && force) {
    if (!quiet) {
      message("force = TRUE: removing existing contents of ", dest_dir)
    }
    unlink(dest_dir, recursive = TRUE, force = TRUE)
  }

  if (!dir.exists(dest_dir)) {
    dir.create(dest_dir, recursive = TRUE)
  }

  for (f in files) {
    # relative path inside the folder, e.g. "subdir/script.R"
    rel_path <- sub(paste0("^", folder_name, "/?"), "", f$path)
    out_path <- file.path(dest_dir, rel_path)
    out_dir <- dirname(out_path)
    if (!dir.exists(out_dir)) {
      dir.create(out_dir, recursive = TRUE)
    }

    if (!quiet) {
      message("  downloading ", rel_path)
    }
    utils::download.file(
      f$download_url,
      out_path,
      mode = "wb",
      quiet = TRUE
    )
  }

  list(dest_dir = dest_dir, is_package = is_package)
}

#' Install a downloaded folder as an R package via pak
#' @keywords internal
tf_install_package <- function(dest_dir, quiet = FALSE) {
  if (!requireNamespace("pak", quietly = TRUE)) {
    stop(
      "pak is required to install packages. Install it with install.packages('pak').",
      call. = FALSE
    )
  }
  if (!quiet) {
    message("Installing package from ", dest_dir, " via pak...")
  }
  pak::pkg_install(paste0("local::", dest_dir), ask = FALSE)
  invisible(dest_dir)
}

#' Fetch (and optionally install) a tool or package folder from jackspepper/tools
#'
#' Lists the top-level folders in the repo (via cache, refreshed weekly or
#' on demand), and downloads a chosen folder's files into the current
#' working directory. Fully scriptable: pass `folder` (and `install`/`force`
#' as needed) to run non-interactively with no prompts.
#'
#' @param folder Character. Skip the interactive menu and fetch this folder
#'   name directly. If `NULL` (default), an interactive menu is shown.
#'   Required for non-interactive/scripted use.
#' @param branch Character. Branch to fetch from. If `NULL` (default), the
#'   repo's default branch (`main`) is used. In an interactive session with
#'   `folder = NULL`, a branch menu is shown before the folder menu.
#'   Required (or left as `NULL` for `main`) for non-interactive/scripted use.
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
#' @param force Logical. If `TRUE`, overwrite an existing non-empty
#'   destination directory (its contents are deleted first). Default `FALSE`,
#'   which errors if `dest_dir` already exists and has files in it.
#' @param install Character or logical. Controls installation for folders
#'   detected as R packages (a top-level `DESCRIPTION` file). One of:
#'   \describe{
#'     \item{`"ask"`}{(default) Prompt interactively if a package is
#'       detected and the session is interactive; otherwise behaves like
#'       `"never"`.}
#'     \item{`"auto"` / `TRUE`}{Always install detected packages via `pak`,
#'       no prompt. Safe for non-interactive/scripted use.}
#'     \item{`"never"` / `FALSE`}{Never install, regardless of detection.}
#'   }
#' @param cleanup Logical. If `TRUE`, delete the downloaded folder
#'   (`dest_dir`) after a package install actually runs — since the package
#'   is installed into the R library at that point, the downloaded source
#'   is no longer needed. Default `TRUE`. Has no effect if the folder isn't
#'   a package, or if it is but `install` doesn't end up installing it.
#' @param browse Logical. Instead of downloading directly, open
#'   download-directory.github.io in the browser for the chosen folder and
#'   let the user download the zip manually.
#' @param quiet Logical. Suppress status messages.
#'
#' @return Invisibly, a list with `dest_dir` (path written to — or removed,
#'   if `cleanup = TRUE` and an install ran; see `cleaned_up`), `branch`
#'   (character, the branch actually fetched from), `is_package`
#'   (logical), `installed` (logical, whether `pak` install ran), and
#'   `cleaned_up` (logical, whether `dest_dir` was deleted post-install).
#' @export
#'
#' @examples
#' \dontrun{
#' # Interactive menu, files placed in ./<tool_name>/
#' tools_fetch()
#'
#' # Fully scripted: fetch a specific folder, overwrite if present,
#' # auto-install if it's a package - no prompts at all
#' tools_fetch("toolfetch", force = TRUE, install = "auto", quiet = TRUE)
#'
#' # Same, but also remove the downloaded source once installed
#' # (leaves no folder behind - only the installed package remains)
#' tools_fetch(
#'   "toolfetch", force = TRUE, install = "auto", cleanup = TRUE, quiet = TRUE
#' )
#'
#' # Skip the menu, fetch a specific folder as-is into the cwd
#' tools_fetch("incucyte_parse_confluency", subfolder = FALSE)
#'
#' # Download into ./temp/ instead of ./<tool_name>/
#' tools_fetch(subfolder = "temp")
#'
#' # Force a recheck of the repo first
#' tools_fetch(refresh = TRUE)
#'
#' # Fetch from a branch under active development
#' tools_fetch("toolfetch", branch = "dev")
#'
#' # Interactive: pick a branch first, then a folder from that branch
#' tools_fetch()
#' }
tools_fetch <- function(
  folder = NULL,
  branch = NULL,
  subfolder = TRUE,
  base_dir = getwd(),
  refresh = FALSE,
  force = FALSE,
  install = c("ask", "auto", "never"),
  cleanup = TRUE,
  browse = FALSE,
  quiet = FALSE
) {
  if (is.logical(install)) {
    install <- if (isTRUE(install)) "auto" else "never"
  }
  install <- match.arg(install)

  # Interactive branch menu: only offered when the caller didn't pin a
  # branch AND is also letting the folder menu run interactively. If a
  # `folder` was given explicitly, don't prompt for a branch either -
  # default to main (or whatever was passed) to keep scripted-style calls
  # (folder given, branch omitted) non-interactive even in an interactive
  # session.
  if (is.null(folder) && is.null(branch) && interactive()) {
    branches <- tf_get_branches(force = refresh, quiet = quiet)
    default_branch <- tf_repo()$branch

    cat("Available branches in jackspepper/tools:\n\n")
    for (i in seq_along(branches)) {
      marker <- if (identical(branches[i], default_branch)) "  (default)" else ""
      cat(sprintf("%2d. %s%s\n", i, branches[i], marker))
    }
    cat("\n")

    b_choice <- readline(sprintf(
      "Enter a number to select a branch (or Enter for '%s', 0 to cancel): ",
      default_branch
    ))

    if (identical(b_choice, "0")) {
      message("Cancelled.")
      return(invisible(NULL))
    }
    if (identical(b_choice, "")) {
      branch <- default_branch
    } else {
      b_choice_num <- suppressWarnings(as.integer(b_choice))
      if (is.na(b_choice_num) || b_choice_num < 1 || b_choice_num > length(branches)) {
        stop("Invalid selection: ", b_choice, call. = FALSE)
      }
      branch <- branches[b_choice_num]
    }
  }

  branch <- tf_resolve_branch(branch)
  folders <- tf_get_folders(branch = branch, force = refresh, quiet = quiet)

  if (is.null(folder)) {
    if (!interactive()) {
      stop(
        "`folder` must be specified when running non-interactively ",
        "(no interactive() session to show a menu in).",
        call. = FALSE
      )
    }

    cat("Available tools in jackspepper/tools (branch: ", branch, "):\n\n", sep = "")
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
      "'",
      folder,
      "' is not a top-level folder in ",
      tf_repo()$owner,
      "/",
      tf_repo()$repo,
      " on branch '",
      branch,
      "'. Run tools_list(branch = '",
      branch,
      "') to see available folders (or with refresh = TRUE).",
      call. = FALSE
    )
  }

  if (isTRUE(browse)) {
    cfg <- tf_repo()
    tree_url <- sprintf(
      "https://github.com/%s/%s/tree/%s/%s",
      cfg$owner,
      cfg$repo,
      branch,
      folder
    )
    dl_url <- sprintf(
      "https://download-directory.github.io/?url=%s&filename=%s",
      utils::URLencode(tree_url, reserved = TRUE),
      folder
    )
    if (!quiet) {
      message("Opening browser to download '", folder, "'...")
    }
    utils::browseURL(dl_url)
    return(invisible(dl_url))
  }

  if (isTRUE(subfolder)) {
    dest_dir <- file.path(base_dir, folder)
  } else if (identical(subfolder, FALSE)) {
    dest_dir <- base_dir
  } else if (is.character(subfolder) && length(subfolder) == 1) {
    dest_dir <- if (fs_is_absolute(subfolder)) {
      subfolder
    } else {
      file.path(base_dir, subfolder)
    }
  } else {
    stop(
      "`subfolder` must be TRUE, FALSE, or a single path string.",
      call. = FALSE
    )
  }

  # Only prompt when writing flat into base_dir with no dedicated subfolder
  # AND not already forcing an overwrite, since that's the case most likely
  # to clobber unrelated files and `force` already signals explicit intent.
  if (
    identical(subfolder, FALSE) && !force && interactive() && !isTRUE(quiet)
  ) {
    ok <- readline(sprintf(
      "This will write '%s' files directly into %s. Continue? [y/N]: ",
      folder,
      dest_dir
    ))
    if (!tolower(ok) %in% c("y", "yes")) {
      message("Cancelled.")
      return(invisible(NULL))
    }
  }

  result <- tf_download_folder(
    folder,
    dest_dir,
    branch = branch,
    quiet = quiet,
    force = force
  )

  if (!quiet) {
    message(
      "Done. '", folder, "' (branch: ", branch, ") written to: ", result$dest_dir
    )
  }

  installed <- FALSE
  cleaned_up <- FALSE
  if (result$is_package) {
    do_install <- switch(
      install,
      auto = TRUE,
      never = FALSE,
      ask = {
        if (interactive() && !isTRUE(quiet)) {
          if (!quiet) {
            message(
              "'",
              folder,
              "' looks like an R package (DESCRIPTION found)."
            )
          }
          ok <- readline(sprintf("Install '%s' now with pak? [y/N]: ", folder))
          tolower(ok) %in% c("y", "yes")
        } else {
          FALSE
        }
      }
    )

    if (do_install) {
      tf_install_package(result$dest_dir, quiet = quiet)
      installed <- TRUE

      if (isTRUE(cleanup)) {
        if (!quiet) {
          message(
            "cleanup = TRUE: removing downloaded source at ",
            result$dest_dir
          )
        }
        unlink(result$dest_dir, recursive = TRUE, force = TRUE)
        cleaned_up <- TRUE
      }
    } else if (!quiet && install != "never") {
      message(
        "'",
        folder,
        "' looks like an R package. Install it with: ",
        "pak::pkg_install('local::",
        result$dest_dir,
        "')"
      )
    }
  }

  invisible(list(
    dest_dir = result$dest_dir,
    branch = branch,
    is_package = result$is_package,
    installed = installed,
    cleaned_up = cleaned_up
  ))
}
