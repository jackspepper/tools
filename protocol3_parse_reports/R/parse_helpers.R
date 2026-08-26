#' Helper to retrieve the installed or development package version
#' @keywords internal
.get_parser_version <- function() {
  tryCatch(
    as.character(utils::packageVersion("protocol3Parser")),
    error = function(e) {
      desc <- system.file("DESCRIPTION", package = "protocol3Parser")
      if (nzchar(desc) && file.exists(desc)) {
        as.character(read.dcf(desc)[1, "Version"])
      } else {
        "0.1.0.9000"
      }
    }
  )
}

#' Extract metadata rows from a plate block
#'
#' @param block Data frame representing a single plate block from raw ODS data.
#' @param include_version Logical indicating whether to append `"Parser Version"`.
#'
#' @return A single-row data frame containing metadata fields ("Plate Name",
#'   "User", "Created", "Comments / Notes", and optionally "Parser Version").
#' @keywords internal
.extract_metadata <- function(block, include_version = TRUE) {
  meta_rows <- block[
    trimws(block[[1]]) %in%
      c("Plate Name", "User", "Created", "Comments / Notes"),
    1:2
  ]
  metadata <- as.data.frame(
    t(stats::setNames(meta_rows[[2]], meta_rows[[1]])),
    stringsAsFactors = FALSE
  )
  rownames(metadata) <- NULL

  if (isTRUE(include_version)) {
    metadata[["Parser Version"]] <- .get_parser_version()
  }

  metadata
}

#' Optional: split Plate Name into named components
#'
#' @param metadata Single-row metadata data frame containing a `"Plate Name"`
#'   column.
#' @param name_components Optional character vector of component names.
#'
#' @return Metadata data frame with additional component columns appended if
#'   `name_components` is provided.
#' @keywords internal
.split_plate_name <- function(metadata, name_components) {
  if (is.null(name_components)) {
    return(metadata)
  }

  plate_name <- metadata[["Plate Name"]]
  parts <- strsplit(plate_name, "_")[[1]]

  if (length(parts) != length(name_components)) {
    warning(sprintf(
      "Plate Name '%s' has %d component(s), expected %d (name_components). Skipping split for this plate.",
      plate_name,
      length(parts),
      length(name_components)
    ))
    parts <- rep(NA_character_, length(name_components))
  }

  parts_df <- as.data.frame(t(parts), stringsAsFactors = FALSE)
  names(parts_df) <- name_components
  cbind(metadata, parts_df)
}

#' Extract and format tabular data block from a plate block
#'
#' @param block Data frame representing a single plate block.
#' @param data_cols Character vector of column names for the data table.
#'
#' @return Data frame of data rows with formatted column names, integer
#'   `Sector`, and blank rows removed.
#' @keywords internal
.extract_data_block <- function(block, data_cols) {
  header_row <- which(trimws(block[[1]]) == "Sector")
  if (length(header_row) == 0) {
    stop("Could not find 'Sector' header row in plate block.")
  }
  header_row <- header_row[1]

  data_block <- block[(header_row + 1):nrow(block), seq_len(length(data_cols)), drop = FALSE]
  names(data_block) <- data_cols

  # Drop trailing blank rows
  data_block <- data_block[!is.na(data_block[["Sector"]]), ]

  data_block[["Sector"]] <- as.integer(data_block[["Sector"]])
  rownames(data_block) <- NULL
  data_block
}

#' Apply post-processing (numeric conversion and flag splitting) to a plate
#'
#' @param plate Single plate list containing `$metadata` and `$data`.
#' @param num_cols Character vector of column names to coerce to numeric.
#' @param split_flags Logical indicating whether to add `Flags_list`.
#'
#' @return Post-processed plate list.
#' @keywords internal
.post_process_plate <- function(plate, num_cols, split_flags) {
  for (col in num_cols) {
    if (col %in% names(plate$data)) {
      plate$data[[col]] <- as.numeric(plate$data[[col]])
    }
  }
  if (isTRUE(split_flags) && "Flags" %in% names(plate$data)) {
    plate$data[["Flags_list"]] <- split_flags(plate$data[["Flags"]])
  }
  plate
}

#' Internal: parse the common ProtoCOL 3 block structure
#'
#' Shared by [parse_protocol3()] and [parse_protocol3_abx()]. Both report
#' types repeat the same block layout (Plate Name / User / Created /
#' Comments / Notes, followed by a header row and data rows) and differ only
#' in the data column names.
#'
#' @param file Path to the .ods report file.
#' @param sheet Sheet name or index.
#' @param name_components Optional character vector of Plate Name components.
#' @param data_cols Character vector of data column names, in file order,
#'   as they appear after "Sector" (used to detect the header row and to
#'   size/name the data block). Must start with `"Sector"`.
#' @param include_version Logical. If `TRUE` (default), appends `"Parser Version"` to metadata.
#'
#' @return A named list, one element per plate.
#' @keywords internal
.parse_protocol3_blocks <- function(file, sheet, name_components, data_cols,
                                    include_version = TRUE) {

  raw <- readODS::read_ods(file, sheet = sheet, col_names = FALSE)
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)

  # Locate the start of each plate block ("Plate Name" in column 1)
  plate_starts <- which(trimws(raw[[1]]) == "Plate Name")

  if (length(plate_starts) == 0) {
    stop("No 'Plate Name' blocks found - is this a ProtoCOL 3 report?")
  }

  plates <- list()

  for (i in seq_along(plate_starts)) {
    start <- plate_starts[i]
    end <- if (i < length(plate_starts)) plate_starts[i + 1] - 1 else nrow(raw)
    block <- raw[start:end, , drop = FALSE]

    metadata <- .extract_metadata(block, include_version = include_version)
    metadata <- .split_plate_name(metadata, name_components)
    data_block <- .extract_data_block(block, data_cols)

    plate_name <- metadata[["Plate Name"]]
    plates[[plate_name]] <- list(metadata = metadata, data = data_block)
  }

  plates
}

#' Apply an exclusion filter to a list of parsed plates
#'
#' Splits a parsed plates list into plates whose `column` value matches
#' `exclude` and those that don't. Matches are printed to the console.
#'
#' @param plates A named list as returned by [parse_protocol3()] or
#'   [parse_protocol3_abx()].
#' @param exclude Character string to match against `column` (fixed
#'   substring match, not regex). If `NULL` (default), no filtering is done
#'   and everything is returned under `$included`.
#' @param column Which field to search for `exclude`. One of `"Plate Name"`,
#'   `"User"`, `"Comments / Notes"`, or any other metadata/name_components
#'   column present in each plate's `$metadata`. Default `"Plate Name"`.
#'
#' @return A list with `$included` and `$excluded`, each a named list of
#'   plates in the same shape as `plates`.
#' @keywords internal
.apply_exclusion <- function(plates, exclude, column) {
  if (is.null(exclude)) {
    return(list(included = plates, excluded = list()))
  }

  is_match <- vapply(plates, function(p) {
    if (!column %in% names(p$metadata)) {
      stop(sprintf(
        "Exclusion column '%s' not found in plate metadata. Available columns: %s",
        column, paste(names(p$metadata), collapse = ", ")
      ))
    }
    value <- p$metadata[[column]]
    !is.na(value) && grepl(exclude, value, fixed = TRUE)
  }, logical(1))

  if (any(is_match)) {
    message(sprintf(
      "Excluded %d plate(s) matching '%s' in '%s': %s",
      sum(is_match), exclude, column,
      paste(names(plates)[is_match], collapse = ", ")
    ))
  }

  list(included = plates[!is_match], excluded = plates[is_match])
}

#' Internal: shared report parser runner
#'
#' Handles common workflow for parsing blocks, post-processing plate data,
#' and applying exclusions.
#'
#' @inheritParams parse_protocol3
#' @param data_cols Character vector of data column names in file order.
#' @param num_cols Character vector of column names to convert to numeric.
#'
#' @return Parsed plates list, or list with `$included` and `$excluded`.
#' @keywords internal
.parse_protocol3_report <- function(file, sheet, name_components, data_cols,
                                    num_cols, split_flags, exclude, exclude_column,
                                    include_version = TRUE) {
  plates <- .parse_protocol3_blocks(
    file = file,
    sheet = sheet,
    name_components = name_components,
    data_cols = data_cols,
    include_version = include_version
  )
  plates <- lapply(plates, .post_process_plate, num_cols = num_cols, split_flags = split_flags)
  result <- .apply_exclusion(plates, exclude, exclude_column)

  out <- if (is.null(exclude)) result$included else result

  attr(out, "parser_version") <- .get_parser_version()
  attr(out, "parsed_at") <- Sys.time()

  out
}
