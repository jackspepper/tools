# ==============================================================================
# parse_confluency.R
#
# Parses IncuCyte/HuMEE-style plate confluence export .txt files into two
# tidy data frames:
#   - data:     file, well, row, column, value  (one row per well)
#   - metadata: file, key, value                (long format, one row per field)
#
# Usage:
#   source("parse_confluency.R")
#   result   <- read_confluency_folder("path/to/folder", depth = 1, pattern = "Plate.*\\.txt$")
#   data_df     <- result$data
#   metadata_df <- result$metadata
# ==============================================================================

library(dplyr)
library(tidyr)
library(purrr)
library(stringr)
library(fs)
library(readr)

# ------------------------------------------------------------------------
# List files under a folder up to a given depth, matching a filename pattern.
# depth = 0 -> only files directly in `path`
# depth = 1 -> `path` + one level of subfolders, etc.
# depth = Inf -> fully recursive
# (fs::dir_ls's `recurse` argument natively accepts a depth, so no custom
#  recursion logic is needed)
# ------------------------------------------------------------------------
list_files_depth <- function(path, depth = 0, pattern = "\\.txt$") {
  as.character(dir_ls(path, recurse = depth, type = "file", regexp = pattern))
}

# ------------------------------------------------------------------------
# Parse a single confluence export file.
# Returns a list(data = <df>, metadata = <df>)
# ------------------------------------------------------------------------
parse_confluency_file <- function(filepath) {

  lines <- readLines(filepath, warn = FALSE)
  lines <- str_remove(lines, "\r$")   # strip stray CR if present

  file_id <- basename(filepath)

  # --- metadata block: "Key: value" lines up to the first blank line ---
  meta_end <- which(lines == "")[1] - 1
  meta_lines <- lines[1:meta_end]
  meta_lines <- meta_lines[nzchar(meta_lines)]

  meta_keys   <- str_trim(str_extract(meta_lines, "^[^:]+"))
  meta_values <- str_trim(str_remove(meta_lines, "^[^:]+:"))

  # --- Time Stamp / Elapsed line ---
  ts_idx  <- which(str_starts(lines, "Time Stamp:"))[1]
  ts_flds <- str_split(lines[ts_idx], "\t")[[1]]
  # Expected: "Time Stamp:", "<datetime>", "Elapsed:", "<n>", "hours"
  timestamp_val <- str_trim(ts_flds[2])
  elapsed_val   <- str_trim(ts_flds[4])

  meta_keys   <- c(meta_keys, "Time Stamp", "Elapsed (hours)")
  meta_values <- c(meta_values, timestamp_val, elapsed_val)

  metadata_df <- tibble(
    file  = file_id,
    key   = meta_keys,
    value = meta_values
  )

  # --- data table: header row (column numbers), then row A, B, C... ---
  header_idx <- which(str_starts(lines, "\t"))[1]  # first line starting with a tab = header
  col_ids    <- str_split(lines[header_idx], "\t")[[1]]
  col_ids    <- col_ids[col_ids != ""]

  data_start <- header_idx + 1
  data_end   <- data_start
  while (data_end <= length(lines) && nzchar(lines[data_end])) {
    data_end <- data_end + 1
  }
  data_end <- data_end - 1

  row_lines <- lines[data_start:data_end]

  data_df <- map_dfr(row_lines, function(l) {
    flds     <- str_split(l, "\t")[[1]]
    row_id   <- flds[1]
    values   <- as.numeric(flds[-1])
    tibble(
      file   = file_id,
      row    = row_id,
      column = as.integer(col_ids),
      value  = values
    )
  }) %>%
    mutate(well = paste0(row, column)) %>%
    select(file, well, row, column, value)

  list(data = data_df, metadata = metadata_df)
}

# ------------------------------------------------------------------------
# Read every matching file in a folder and combine into two data frames.
#
# verbose  : TRUE/FALSE - print status messages (files found, per-file result,
#            timing, summary). Off by default so it stays quiet when called
#            from another script.
# progress : TRUE/FALSE - show a base-R txtProgressBar while parsing. Off by
#            default for the same reason. Suppressed automatically if
#            verbose = TRUE (the per-file messages replace it) or if not
#            running interactively.
# export   : TRUE/FALSE - if TRUE, also write the two data frames to disk via
#            write_confluency_output() (see out_dir / xlsx below). Off by
#            default so the function just returns the data frames - handy
#            when calling this from another script and you only want the
#            data in memory.
# out_dir  : folder to write to when export = TRUE. Ignored otherwise.
# xlsx     : passed through to write_confluency_output() when export = TRUE
#            - FALSE writes csv files, TRUE writes a single xlsx workbook.
# ------------------------------------------------------------------------
read_confluency_folder <- function(folder, depth = 0, pattern = "Plate.*\\.txt$",
                                    verbose = FALSE, progress = FALSE,
                                    export = FALSE, out_dir = ".", xlsx = FALSE) {

  if (verbose) message("Scanning '", folder, "' (depth = ", depth, ", pattern = '", pattern, "') ...")

  files <- list_files_depth(folder, depth = depth, pattern = pattern)

  if (length(files) == 0) {
    stop("No files found matching pattern '", pattern, "' in '", folder, "' (depth = ", depth, ")")
  }

  if (verbose) message("Found ", length(files), " file(s):\n  ", paste(basename(files), collapse = "\n  "))

  # progress bar and per-file messages are mutually exclusive - verbose already
  # gives per-file feedback, so skip the bar in that case
  use_bar <- progress && !verbose
  if (use_bar) pb <- utils::txtProgressBar(min = 0, max = length(files), style = 3)

  parsed <- vector("list", length(files))

  for (i in seq_along(files)) {
    t0 <- Sys.time()
    parsed[[i]] <- parse_confluency_file(files[i])

    if (verbose) {
      n_wells <- nrow(parsed[[i]]$data)
      n_na    <- sum(is.na(parsed[[i]]$data$value))
      message(sprintf("  [%d/%d] %s - %d wells parsed%s (%.2fs)",
                       i, length(files), basename(files[i]), n_wells,
                       if (n_na > 0) sprintf(", %d NA value(s)", n_na) else "",
                       as.numeric(Sys.time() - t0, units = "secs")))
    }

    if (use_bar) utils::setTxtProgressBar(pb, i)
  }

  if (use_bar) close(pb)

  data_df     <- map_dfr(parsed, "data")
  metadata_df <- map_dfr(parsed, "metadata")

  # Order wells A1, A2, ... A12, B1, ... for readability
  data_df <- data_df %>%
    mutate(row = factor(row, levels = LETTERS[1:26])) %>%
    arrange(file, row, column) %>%
    mutate(row = as.character(row))

  if (verbose) {
    message(sprintf("Done. %d files -> %d wells total (%d NA value(s)).",
                     length(files), nrow(data_df), sum(is.na(data_df$value))))
  }

  result <- list(data = data_df, metadata = metadata_df)

  if (export) write_confluency_output(result, out_dir = out_dir, xlsx = xlsx, verbose = verbose)

  result
}

# ------------------------------------------------------------------------
# Write the two data frames out to disk.
#
# xlsx = FALSE (default) -> writes "confluency_data.csv" and
#        "confluency_metadata.csv" into out_dir.
# xlsx = TRUE  -> writes a single "confluency_export.xlsx" into out_dir,
#        with the data on one sheet and metadata on another. Requires the
#        `openxlsx` package (not loaded by default - only needed if you use
#        this flag).
# ------------------------------------------------------------------------
write_confluency_output <- function(result, out_dir = ".", xlsx = FALSE, verbose = FALSE) {

  dir_create(out_dir)

  if (xlsx) {
    if (!requireNamespace("openxlsx", quietly = TRUE)) {
      stop("Package 'openxlsx' is required for xlsx = TRUE. Install it with install.packages('openxlsx').")
    }
    out_path <- file.path(out_dir, "confluency_export.xlsx")
    openxlsx::write.xlsx(
      list(data = result$data, metadata = result$metadata),
      file = out_path
    )
    if (verbose) message("Wrote xlsx file: ", out_path)
  } else {
    data_path <- file.path(out_dir, "confluency_data.csv")
    meta_path <- file.path(out_dir, "confluency_metadata.csv")
    write_csv(result$data, data_path)
    write_csv(result$metadata, meta_path)
    if (verbose) message("Wrote csv files:\n  ", data_path, "\n  ", meta_path)
  }

  invisible(out_dir)
}

# ------------------------------------------------------------------------
# Example
# ------------------------------------------------------------------------
# result <- read_confluency_folder("uploads", depth = 0, pattern = "Plate.*\\.txt$",
#                                   verbose = TRUE, progress = FALSE)
# result$data
# result$metadata
#
# # Quiet, with a progress bar instead (e.g. when sourced into another script):
# result <- read_confluency_folder("uploads", verbose = FALSE, progress = TRUE)
#
# # Metadata is long-format (file, key, value); widen it if you want one row per file:
# result$metadata %>% tidyr::pivot_wider(names_from = key, values_from = value)
#
# # data has row/column split out too, handy for plate heatmaps:
# result$data %>% filter(file == "Plate1.txt") %>%
#   ggplot2::ggplot(ggplot2::aes(column, row, fill = value)) + ggplot2::geom_tile()
#
# # Export to csv (default) or a single xlsx workbook (2 sheets: data, metadata),
# # either as a separate step:
# write_confluency_output(result, out_dir = "output", xlsx = FALSE)
# write_confluency_output(result, out_dir = "output", xlsx = TRUE)
#
# # ...or in one call via the export toggle (still returns the data frames,
# # so this works fine as a step inside another script - export just also
# # writes files as a side effect):
# result <- read_confluency_folder("uploads", export = TRUE, out_dir = "output", xlsx = TRUE)
