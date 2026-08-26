#' Parse ProtoCOL 3 Colony Counter Report
#'
#' Reads a ProtoCOL 3 .ods report and splits it into one entry per imaged
#' plate. Each entry contains two tables: `metadata` (Plate Name, User,
#' Created, Comments / Notes, and optionally Parser Version) and `data`
#' (Sector, Colony Name, Count / Frame, Flags).
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
#' @param include_version Logical. If `TRUE` (default), adds a `"Parser Version"`
#'   column (e.g. `"0.1.0.9000"`) to each plate's `metadata` data frame and
#'   attaches `"parser_version"` and `"parsed_at"` attributes to the returned list.
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
                             exclude_column = "Plate Name",
                             include_version = TRUE) {

  .parse_protocol3_report(
    file = file,
    sheet = sheet,
    name_components = name_components,
    data_cols = c("Sector", "Colony Name", "Count / Frame", "Flags"),
    num_cols = "Count / Frame",
    split_flags = split_flags,
    exclude = exclude,
    exclude_column = exclude_column,
    include_version = include_version
  )
}

#' Parse ProtoCOL 3 Antibiotic Resistance (Zone) Report
#'
#' Reads a ProtoCOL 3 antibiotic zone plate report (.ods) and splits it into
#' one entry per imaged plate, mirroring [parse_protocol3()] for colony
#' counts. Each entry contains `metadata` (Plate Name, User, Created,
#' Comments / Notes, and optionally Parser Version) and `data` (Sector, Zone Name,
#' Zone Diameter (mm), Antibiotic Susceptibility, Flags).
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
                                 exclude_column = "Plate Name",
                                 include_version = TRUE) {

  .parse_protocol3_report(
    file = file,
    sheet = sheet,
    name_components = name_components,
    data_cols = c(
      "Sector", "Zone Name", "Zone Diameter (mm)",
      "Antibiotic Susceptibility", "Flags"
    ),
    num_cols = "Zone Diameter (mm)",
    split_flags = split_flags,
    exclude = exclude,
    exclude_column = exclude_column,
    include_version = include_version
  )
}
