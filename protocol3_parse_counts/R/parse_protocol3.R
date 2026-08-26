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
#'
#' @return A named list, one element per plate.
#' @keywords internal
.parse_protocol3_blocks <- function(file, sheet, name_components, data_cols) {

  raw <- readODS::read_ods(file, sheet = sheet, col_names = FALSE)
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)

  # Locate the start of each plate block ("Plate Name" in column 1)
  plate_starts <- which(trimws(raw[[1]]) == "Plate Name")

  if (length(plate_starts) == 0) {
    stop("No 'Plate Name' blocks found - is this a ProtoCOL 3 report?")
  }

  n_cols <- length(data_cols)
  plates <- list()

  for (i in seq_along(plate_starts)) {
    start <- plate_starts[i]
    end <- if (i < length(plate_starts)) plate_starts[i + 1] - 1 else nrow(raw)
    block <- raw[start:end, , drop = FALSE]

    # --- Metadata: the 4 label/value rows preceding the "Sector" header ---
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

    # --- Optional: split Plate Name into named components ---
    if (!is.null(name_components)) {
      parts <- strsplit(metadata[["Plate Name"]], "_")[[1]]

      if (length(parts) != length(name_components)) {
        warning(sprintf(
          "Plate Name '%s' has %d component(s), expected %d (name_components). Skipping split for this plate.",
          metadata[["Plate Name"]],
          length(parts),
          length(name_components)
        ))
        parts <- rep(NA_character_, length(name_components))
      }

      parts_df <- as.data.frame(t(parts), stringsAsFactors = FALSE)
      names(parts_df) <- name_components
      metadata <- cbind(metadata, parts_df)
    }

    # --- Data: rows after the "Sector" header row, until blank/next block ---
    header_row <- which(trimws(block[[1]]) == "Sector")
    data_block <- block[(header_row + 1):nrow(block), seq_len(n_cols), drop = FALSE]
    names(data_block) <- data_cols

    # Drop trailing blank rows
    data_block <- data_block[!is.na(data_block[["Sector"]]), ]

    data_block[["Sector"]] <- as.integer(data_block[["Sector"]])
    rownames(data_block) <- NULL

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

#' Parse ProtoCOL 3 Colony Counter Report
#'
#' Reads a ProtoCOL 3 .ods report and splits it into one entry per imaged
#' plate. Each entry contains two tables: `metadata` (Plate Name, User,
#' Created, Comments / Notes) and `data` (Sector, Colony Name, Count / Frame,
#' Flags).
#'
#' @param file Path to the .ods report file.
#' @param sheet Sheet name or index to read (default: 1, the first sheet).
#' @param name_components Optional character vector naming the underscore-
#'   separated components of "Plate Name" (e.g.
#'   c("Date", "BacTime", "Subject", "PlateID")). If supplied, these become
#'   additional columns in `metadata`. Plate names with a different number of
#'   underscore-separated parts than `length(name_components)` are left as NA
#'   with a warning.
#' @param split_flags Logical. If `TRUE` (default), an additional
#'   `Flags_list` column is added to each plate's `data`, holding the
#'   individual flag tokens as a character vector per row (e.g. `"E M"`
#'   becomes `c("E", "M")`).
#' @param exclude Optional character string. Plates whose `exclude_column`
#'   value contains this string are removed from the returned list and
#'   reported to the console (e.g. `exclude = "_Exclude"`). Default `NULL`
#'   (no filtering).
#' @param exclude_column Which metadata field to search for `exclude`.
#'   Default `"Plate Name"`.
#'
#' @return If `exclude` is `NULL`, a named list, one element per plate (named
#'   after "Plate Name"), each a list with `$metadata` and `$data` data
#'   frames. If `exclude` is supplied, a list with `$included` and
#'   `$excluded`, each in that same per-plate shape.
#'
#' @examples
#' file <- system.file(
#'   "extdata",
#'   "ExampleCounts.ods",
#'   package = "protocol3Parser"
#' )
#'
#' plates <- parse_protocol3(file)
#' plates[["Plate1A"]]$metadata
#' plates[["Plate1A"]]$data
#'
#' # Split "Plate1A" into named components
#' plates <- parse_protocol3(
#'   file,
#'   name_components = c("Date", "BacTime", "Subject", "PlateID")
#' )
#' plates[["Plate1A"]]$metadata
#'
#' @export
parse_protocol3 <- function(file, sheet = 1, name_components = NULL,
                             split_flags = TRUE, exclude = NULL,
                             exclude_column = "Plate Name") {

  data_cols <- c("Sector", "Colony Name", "Count / Frame", "Flags")
  plates <- .parse_protocol3_blocks(file, sheet, name_components, data_cols)

  plates <- lapply(plates, function(p) {
    p$data[["Count / Frame"]] <- as.numeric(p$data[["Count / Frame"]])
    if (isTRUE(split_flags)) {
      p$data[["Flags_list"]] <- split_flags(p$data[["Flags"]])
    }
    p
  })

  result <- .apply_exclusion(plates, exclude, exclude_column)
  if (is.null(exclude)) result$included else result
}

#' Parse ProtoCOL 3 Antibiotic Resistance (Zone) Report
#'
#' Reads a ProtoCOL 3 antibiotic zone plate report (.ods) and splits it into
#' one entry per imaged plate, mirroring [parse_protocol3()] for colony
#' counts. Each entry contains `metadata` (Plate Name, User, Created,
#' Comments / Notes) and `data` (Sector, Zone Name, Zone Diameter (mm),
#' Antibiotic Susceptibility, Flags).
#'
#' @inheritParams parse_protocol3
#'
#' @return If `exclude` is `NULL`, a named list, one element per plate (named
#'   after "Plate Name"), each a list with `$metadata` and `$data` data
#'   frames. If `exclude` is supplied, a list with `$included` and
#'   `$excluded`, each in that same per-plate shape.
#'
#' @examples
#' file <- system.file(
#'   "extdata",
#'   "ExampleAbxRes.ods",
#'   package = "protocol3Parser"
#' )
#'
#' plates <- parse_protocol3_abx(file)
#' plates[["1.1A"]]$data
#' plates[["1.1B"]]$data$Flags_list
#'
#' # Drop any plate whose name contains "_Exclude"
#' res <- parse_protocol3_abx(file, exclude = "_Exclude")
#' names(res$included)
#' names(res$excluded)
#'
#' @export
parse_protocol3_abx <- function(file, sheet = 1, name_components = NULL,
                                 split_flags = TRUE, exclude = NULL,
                                 exclude_column = "Plate Name") {

  data_cols <- c(
    "Sector", "Zone Name", "Zone Diameter (mm)",
    "Antibiotic Susceptibility", "Flags"
  )
  plates <- .parse_protocol3_blocks(file, sheet, name_components, data_cols)

  plates <- lapply(plates, function(p) {
    p$data[["Zone Diameter (mm)"]] <- as.numeric(p$data[["Zone Diameter (mm)"]])
    if (isTRUE(split_flags)) {
      p$data[["Flags_list"]] <- split_flags(p$data[["Flags"]])
    }
    p
  })

  result <- .apply_exclusion(plates, exclude, exclude_column)
  if (is.null(exclude)) result$included else result
}

#' Flatten a parse_protocol3() result into one tidy data frame
#'
#' Combines every plate's `data` table into a single long-format data frame,
#' with the plate's metadata (Plate Name, User, Created, Comments / Notes,
#' and any name_components columns) repeated on every row.
#'
#' @param plates Output of \code{\link{parse_protocol3}} or
#'   \code{\link{parse_protocol3_abx}} (the per-plate list; if you filtered
#'   with `exclude`, pass `result$included` or `result$excluded`, not the
#'   wrapper itself).
#'
#' @return A single data frame: one row per Sector/well, with metadata columns
#'   joined in. If present, `Flags_list` is kept as a list-column.
#'
#' @examples
#' file <- system.file(
#'   "extdata",
#'   "ExampleCounts.ods",
#'   package = "protocol3Parser"
#' )
#'
#' plates <- parse_protocol3(
#'   file,
#'   name_components = c("Date", "BacTime", "Subject", "PlateID")
#' )
#' tidy_data <- tidy_protocol3(plates)
#'
#' @export

tidy_protocol3 <- function(plates) {
  rows <- lapply(plates, function(p) {
    cbind(
      p$metadata[rep(1, nrow(p$data)), , drop = FALSE],
      p$data,
      row.names = NULL
    )
  })
  do.call(rbind, rows)
}

# ---------------------------------------------------------------------------
# Example usage (run interactively / uncomment to use as a script)
# ---------------------------------------------------------------------------
# plates <- parse_protocol3("Experiment1.ods")
#
# # List plate names found
# names(plates)
#
# # Access metadata / data for one plate
# plates[["Plate1A"]]$metadata
# plates[["Plate1A"]]$data
#
# # Combine all plates' data into one long table with a Plate column
# all_data <- do.call(rbind, lapply(names(plates), function(nm) {
#   cbind(Plate = nm, plates[[nm]]$data)
# }))
