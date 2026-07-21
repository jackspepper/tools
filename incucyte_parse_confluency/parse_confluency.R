# ==============================================================================
# parse_confluency.R
#
# Parses IncuCyte/HuMEE-style plate confluence export .txt files into two
# tidy data frames:
#   - data:     file, metric, well, row, column, value  (one row per well per metric)
#   - metadata: file, key, value                        (long format)
#
# Supports two export layouts, auto-detected per file:
#
#   1. WIDE-ROW layout: one header line of well IDs (any order), one data
#      row per timepoint starting with "Date Time  Elapsed  <well> <well> ...".
#      (e.g. "..._Prefix.txt", "..._Prefix_1.txt")
#
#   2. MATRIX layout: "Time Stamp: <dt>  Elapsed: <n>  hours" line, followed
#      by one or more blocks of an 8x12 (row A-H x col 1-12) grid. Each block
#      may optionally be preceded by a metric-name label line (e.g. "Std Err
#      Img"). If no label line precedes a block, the file's top-level
#      "Metric:" field is used as the metric name.
#      (e.g. "..._Prefix_1_2.txt" .. "..._Prefix_1_4.txt")
#
#   Multi-image matrix exports (blocks labeled "Image 1", "Image 2", etc.)
#   are NOT currently supported - these represent longitudinal images from
#   the same plate/timepoint and need a distinct data model. Such blocks are
#   skipped, with the caller prompted/warned (see skip_on_unsupported).
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

# ------------------------------------------------------------------------
# List files under a folder up to a given depth, matching a filename pattern.
# depth = 0 -> only files directly in `path`
# depth = 1 -> `path` + one level of subfolders, etc.
# depth = Inf -> fully recursive (same as list.files(..., recursive = TRUE))
# ------------------------------------------------------------------------
list_files_depth <- function(path, depth = 0, pattern = "\\.txt$") {
  path <- normalizePath(path, mustWork = TRUE)

  collect <- function(dir, remaining_depth) {
    entries <- list.files(dir, full.names = TRUE)
    files   <- entries[!dir.exists(entries)]
    matched <- files[grepl(pattern, basename(files), ignore.case = TRUE)]

    if (remaining_depth > 0) {
      subdirs <- entries[dir.exists(entries)]
      sub_matched <- unlist(lapply(subdirs, collect, remaining_depth = remaining_depth - 1))
      matched <- c(matched, sub_matched)
    }
    matched
  }

  collect(path, depth)
}

# ------------------------------------------------------------------------
# Parse the "Key: value" metadata block at the top of any export
# (lines up to the first blank line). Returns list(keys, values).
# ------------------------------------------------------------------------
.parse_meta_block <- function(lines) {
  blank_idx <- which(lines == "")[1]
  meta_end  <- if (is.na(blank_idx)) length(lines) else blank_idx - 1
  meta_lines <- lines[1:meta_end]
  meta_lines <- meta_lines[nzchar(meta_lines)]

  keys   <- str_trim(str_extract(meta_lines, "^[^:]+"))
  values <- str_trim(str_remove(meta_lines, "^[^:]+:"))

  list(keys = keys, values = values)
}

# ------------------------------------------------------------------------
# Detect which layout a file uses.
# Returns "wide_row", "matrix", or "unknown"
# ------------------------------------------------------------------------
.detect_layout <- function(lines) {
  if (any(str_starts(lines, "Date Time\tElapsed"))) return("wide_row")
  if (any(str_starts(lines, "Time Stamp:")))          return("matrix")
  "unknown"
}

# ------------------------------------------------------------------------
# Parse a WIDE-ROW layout file (header of well IDs in any order, one row
# per timepoint). Only the first timepoint row is expected in these
# single-timepoint exports, but this handles multiple rows if present.
# ------------------------------------------------------------------------
.parse_wide_row <- function(lines, file_id, metric_name) {
  header_idx <- which(str_starts(lines, "Date Time\tElapsed"))[1]
  well_ids   <- str_split(lines[header_idx], "\t")[[1]][-(1:2)]

  data_start <- header_idx + 1
  data_end   <- data_start
  while (data_end <= length(lines) && nzchar(lines[data_end])) data_end <- data_end + 1
  data_end <- data_end - 1

  row_lines <- lines[data_start:data_end]

  data_df <- map_dfr(row_lines, function(l) {
    flds   <- str_split(l, "\t")[[1]]
    values <- as.numeric(flds[-(1:2)])
    tibble(
      file   = file_id,
      metric = metric_name,
      well   = well_ids,
      value  = values
    )
  }) %>%
    mutate(
      row    = str_extract(well, "^[A-Za-z]+"),
      column = as.integer(str_extract(well, "\\d+$"))
    ) %>%
    select(file, metric, well, row, column, value)

  data_df
}

# ------------------------------------------------------------------------
# Parse a single 8x12 matrix block starting at header_idx (the line
# "\t1\t2\t...\t12"). Returns list(data = <df rows A-H>, next_idx = <line
# after the block>).
# ------------------------------------------------------------------------
.parse_matrix_block <- function(lines, header_idx, file_id, metric_name) {
  col_ids <- str_split(lines[header_idx], "\t")[[1]]
  col_ids <- col_ids[nzchar(col_ids)]

  data_start <- header_idx + 1
  data_end   <- data_start
  while (data_end <= length(lines) && nzchar(lines[data_end]) &&
         str_detect(lines[data_end], "^[A-Za-z]\t")) {
    data_end <- data_end + 1
  }
  data_end <- data_end - 1

  row_lines <- lines[data_start:data_end]

  data_df <- map_dfr(row_lines, function(l) {
    flds   <- str_split(l, "\t")[[1]]
    row_id <- flds[1]
    values <- as.numeric(flds[-1])
    tibble(
      file   = file_id,
      metric = metric_name,
      row    = row_id,
      column = as.integer(col_ids),
      value  = values
    )
  }) %>%
    mutate(well = paste0(row, column)) %>%
    select(file, metric, well, row, column, value)

  list(data = data_df, next_idx = data_end + 1)
}

# ------------------------------------------------------------------------
# Parse a MATRIX layout file. Handles one or more blocks. A block may be
# preceded by a label line (metric name, e.g. "Std Err Img") - if so that
# label is used as the metric; otherwise the top-level "Metric:" metadata
# field is used.
#
# Multi-image blocks (label starting with "Image ") are NOT supported yet
# and are skipped, with the label recorded in unsupported_labels; see
# skip_on_unsupported in read_confluency_folder() for how the caller is
# prompted.
# ------------------------------------------------------------------------
.parse_matrix <- function(lines, file_id, default_metric) {
  ts_idx <- which(str_starts(lines, "Time Stamp:"))[1]

  blocks <- list()
  unsupported_labels <- character(0)

  idx <- ts_idx + 1
  while (idx <= length(lines)) {
    line <- lines[idx]

    if (!nzchar(line)) { idx <- idx + 1; next }

    # A grid header line looks like "\t1\t2\t...\t12" (starts with tab)
    if (str_starts(line, "\t")) {
      block <- .parse_matrix_block(lines, idx, file_id, default_metric)
      blocks[[length(blocks) + 1]] <- block$data
      idx <- block$next_idx
      next
    }

    # Otherwise this is a label line for the following block
    label <- str_trim(line)
    grid_header_idx <- idx + 1
    if (grid_header_idx > length(lines) || !str_starts(lines[grid_header_idx], "\t")) {
      # Not actually followed by a grid - skip this stray line
      idx <- idx + 1
      next
    }

    if (str_starts(label, "Image ")) {
      unsupported_labels <- c(unsupported_labels, label)
      # Skip over this block's data without parsing it
      skip_idx <- grid_header_idx + 1
      while (skip_idx <= length(lines) && nzchar(lines[skip_idx]) &&
             str_detect(lines[skip_idx], "^[A-Za-z]\t")) {
        skip_idx <- skip_idx + 1
      }
      idx <- skip_idx
      next
    }

    block <- .parse_matrix_block(lines, grid_header_idx, file_id, label)
    blocks[[length(blocks) + 1]] <- block$data
    idx <- block$next_idx
  }

  list(
    data = if (length(blocks) > 0) bind_rows(blocks) else NULL,
    unsupported_labels = unsupported_labels
  )
}

# ------------------------------------------------------------------------
# Parse a single confluence export file. Returns list(data, metadata,
# unsupported_labels). `data` is NULL if the file contained ONLY
# unsupported blocks (e.g. a pure multi-image export).
# ------------------------------------------------------------------------
parse_confluency_file <- function(filepath) {

  lines <- readLines(filepath, warn = FALSE)
  lines <- str_remove(lines, "\r$")   # strip stray CR if present

  file_id <- basename(filepath)

  meta <- .parse_meta_block(lines)
  meta_keys   <- meta$keys
  meta_values <- meta$values
  default_metric <- {
    m <- meta_values[meta_keys == "Metric"]
    if (length(m) == 0) NA_character_ else m[1]
  }

  layout <- .detect_layout(lines)

  unsupported_labels <- character(0)

  if (layout == "wide_row") {
    ts_idx <- which(str_starts(lines, "Date Time\tElapsed"))[1] + 1
    ts_flds <- str_split(lines[ts_idx], "\t")[[1]]
    meta_keys   <- c(meta_keys, "Time Stamp", "Elapsed (hours)")
    meta_values <- c(meta_values, str_trim(ts_flds[1]), str_trim(ts_flds[2]))

    data_df <- .parse_wide_row(lines, file_id, default_metric)

  } else if (layout == "matrix") {
    ts_idx  <- which(str_starts(lines, "Time Stamp:"))[1]
    ts_flds <- str_split(lines[ts_idx], "\t")[[1]]
    # Expected: "Time Stamp:", "<datetime>", "Elapsed:", "<n>", "hours"
    meta_keys   <- c(meta_keys, "Time Stamp", "Elapsed (hours)")
    meta_values <- c(meta_values, str_trim(ts_flds[2]), str_trim(ts_flds[4]))

    parsed <- .parse_matrix(lines, file_id, default_metric)
    data_df <- parsed$data
    unsupported_labels <- parsed$unsupported_labels

  } else {
    stop("Unrecognized file layout in '", file_id,
         "' - expected a 'Date Time\\tElapsed' header (wide-row layout) or a ",
         "'Time Stamp:' line (matrix layout).")
  }

  metadata_df <- tibble(file = file_id, key = meta_keys, value = meta_values)

  if (!is.null(data_df)) {
    data_df <- data_df %>%
      mutate(row = factor(row, levels = LETTERS[1:26])) %>%
      arrange(metric, row, column) %>%
      mutate(row = as.character(row))
  }

  list(data = data_df, metadata = metadata_df, unsupported_labels = unsupported_labels)
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
# skip_on_unsupported : TRUE/FALSE/NA (default NA). Controls behaviour when a
#            file contains unsupported multi-image blocks (labeled
#            "Image 1", "Image 2", ...) - not yet supported by this parser.
#              NA    -> interactively ask the user whether to skip the file
#                       and continue (only in an interactive session; falls
#                       back to erroring if non-interactive).
#              TRUE  -> silently skip such blocks (or whole files, if that's
#                       all they contain) and continue.
#              FALSE -> stop with an error as soon as one is encountered.
# ------------------------------------------------------------------------
read_confluency_folder <- function(folder, depth = 0, pattern = "Plate.*\\.txt$",
                                   verbose = FALSE, progress = FALSE,
                                   export = FALSE, out_dir = ".", xlsx = FALSE,
                                   skip_on_unsupported = NA) {

  if (verbose) message("Scanning '", folder, "' (depth = ", depth, ", pattern = '", pattern, "') ...")

  files <- list_files_depth(folder, depth = depth, pattern = pattern)

  if (length(files) == 0) {
    stop("No files found matching pattern '", pattern, "' in '", folder, "' (depth = ", depth, ")")
  }

  if (verbose) message("Found ", length(files), " file(s):\n  ", paste(basename(files), collapse = "\n  "))

  use_bar <- progress && !verbose
  if (use_bar) pb <- utils::txtProgressBar(min = 0, max = length(files), style = 3)

  parsed <- vector("list", length(files))
  keep   <- rep(TRUE, length(files))

  for (i in seq_along(files)) {
    t0 <- Sys.time()
    res <- parse_confluency_file(files[i])

    if (length(res$unsupported_labels) > 0) {
      msg <- sprintf(
        "%s contains unsupported multi-image block(s): %s. This format (multiple longitudinal images per plate) is not yet handled by this parser.",
        basename(files[i]), paste(unique(res$unsupported_labels), collapse = ", ")
      )

      do_skip <- isTRUE(skip_on_unsupported)

      if (is.na(skip_on_unsupported)) {
        if (interactive()) {
          ans <- readline(paste0(msg, "\nSkip this file and continue? [y/n]: "))
          do_skip <- tolower(str_trim(ans)) %in% c("y", "yes")
          if (!do_skip) stop(msg, " Aborting as requested.")
        } else {
          stop(msg, " Set skip_on_unsupported = TRUE to skip such files automatically.")
        }
      } else if (isFALSE(skip_on_unsupported)) {
        stop(msg)
      }

      if (do_skip) {
        warning(msg, " Skipping.", call. = FALSE)
        if (is.null(res$data)) {
          keep[i] <- FALSE
          if (verbose) message(sprintf("  [%d/%d] %s - skipped (unsupported format only)", i, length(files), basename(files[i])))
          if (use_bar) utils::setTxtProgressBar(pb, i)
          next
        }
        # file had a mix of supported + unsupported blocks - keep the supported data
      }
    }

    parsed[[i]] <- res

    if (verbose) {
      n_wells <- if (is.null(res$data)) 0 else nrow(res$data)
      n_na    <- if (is.null(res$data)) 0 else sum(is.na(res$data$value))
      message(sprintf("  [%d/%d] %s - %d row(s) parsed%s (%.2fs)",
                      i, length(files), basename(files[i]), n_wells,
                      if (n_na > 0) sprintf(", %d NA value(s)", n_na) else "",
                      as.numeric(Sys.time() - t0, units = "secs")))
    }

    if (use_bar) utils::setTxtProgressBar(pb, i)
  }

  if (use_bar) close(pb)

  parsed <- parsed[keep]

  data_df     <- map_dfr(parsed, "data")
  metadata_df <- map_dfr(parsed, "metadata")

  # Order wells A1, A2, ... A12, B1, ... for readability
  data_df <- data_df %>%
    mutate(row = factor(row, levels = LETTERS[1:26])) %>%
    arrange(file, metric, row, column) %>%
    mutate(row = as.character(row))

  if (verbose) {
    message(sprintf("Done. %d files -> %d row(s) total (%d NA value(s)).",
                    sum(keep), nrow(data_df), sum(is.na(data_df$value))))
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

  if (!dir.exists(out_dir)) dir.create(out_dir, recursive = TRUE)

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
    write.csv(result$data, data_path, row.names = FALSE)
    write.csv(result$metadata, meta_path, row.names = FALSE)
    if (verbose) message("Wrote csv files:\n  ", data_path, "\n  ", meta_path)
  }

  invisible(out_dir)
}

# ------------------------------------------------------------------------
# Example
# ------------------------------------------------------------------------
# result <- read_confluency_folder("uploads", depth = 0, pattern = "Plate.*\\.txt$",
#                                   verbose = TRUE, progress = FALSE)
# result$data      # columns: file, metric, well, row, column, value
# result$metadata  # columns: file, key, value
#
# # Files with unsupported multi-image blocks: by default you'll be asked
# # interactively whether to skip them. To automate (e.g. in a script/batch
# # job), set skip_on_unsupported = TRUE to skip automatically, or FALSE to
# # error out immediately instead.
# result <- read_confluency_folder("uploads", skip_on_unsupported = TRUE, verbose = TRUE)
#
# # Metadata is long-format (file, key, value); widen it if you want one row per file:
# result$metadata %>% tidyr::pivot_wider(names_from = key, values_from = value)
#
# # data has row/column split out too, handy for plate heatmaps. Filter to a
# # single metric first if a file has multiple (e.g. confluence vs std err):
# result$data %>% filter(file == "Plate1.txt", metric == "Phase Object Confluence (%)") %>%
#   ggplot2::ggplot(ggplot2::aes(column, row, fill = value)) + ggplot2::geom_tile()
#
# # Export to csv (default) or a single xlsx workbook (2 sheets: data, metadata):
# write_confluency_output(result, out_dir = "output", xlsx = FALSE)
# write_confluency_output(result, out_dir = "output", xlsx = TRUE)
#
# # ...or in one call via the export toggle:
# result <- read_confluency_folder("uploads", export = TRUE, out_dir = "output",
#                                   xlsx = TRUE, skip_on_unsupported = TRUE)