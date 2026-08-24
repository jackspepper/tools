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
#'
#' @return A named list, one element per plate (named after "Plate Name").
#'   Each element is a list with `$metadata` and `$data` data frames.
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
parse_protocol3 <- function(file, sheet = 1, name_components = NULL) {

  raw <- readODS::read_ods(file, sheet = sheet, col_names = FALSE)
  raw <- as.data.frame(raw, stringsAsFactors = FALSE)

  # Locate the start of each plate block ("Plate Name" in column 1)
  plate_starts <- which(trimws(raw[[1]]) == "Plate Name")

  if (length(plate_starts) == 0) {
    stop("No 'Plate Name' blocks found - is this a ProtoCOL 3 report?")
  }

  data_cols <- c("Sector", "Colony Name", "Count / Frame", "Flags")

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
    data_block <- block[(header_row + 1):nrow(block), 1:4, drop = FALSE]
    names(data_block) <- data_cols

    # Drop trailing blank rows
    data_block <- data_block[!is.na(data_block[["Sector"]]), ]

    data_block[["Sector"]] <- as.integer(data_block[["Sector"]])
    data_block[["Count / Frame"]] <- as.numeric(data_block[["Count / Frame"]])
    rownames(data_block) <- NULL

    plate_name <- metadata[["Plate Name"]]
    plates[[plate_name]] <- list(metadata = metadata, data = data_block)
  }

  plates
}

#' Flatten a parse_protocol3() result into one tidy data frame
#'
#' Combines every plate's `data` table into a single long-format data frame,
#' with the plate's metadata (Plate Name, User, Created, Comments / Notes,
#' and any name_components columns) repeated on every row.
#'
#' @param plates Output of \code{\link{parse_protocol3}}.
#'
#' @return A single data frame: one row per Sector/well, with metadata columns
#'   joined in.
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
