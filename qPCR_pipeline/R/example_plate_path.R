#' Path to packaged example qPCR data
#'
#' @description
#' Returns the path to the example qPCR plate export included with
#' the package. By default, the full path to `examplePlate.csv`
#' is returned. Optionally, the path to the containing `extdata`
#' directory can be returned for functions that expect a folder
#' rather than a single file.
#'
#' The example data can be used with
#' [run_cleaning_pipeline()] and
#' [run_consolidation_pipeline()] to demonstrate or test the
#' qPCR processing workflow.
#'
#' @param dir_only Logical. If `FALSE` (default), returns the full
#'   path to `examplePlate.csv`. If `TRUE`, returns the path to the
#'   package's `extdata` directory containing the example file.
#'
#' @return
#' A character string containing either:
#' \itemize{
#'   \item the full path to `examplePlate.csv` when
#'   `dir_only = FALSE`
#'   \item the path to the package `extdata` directory when
#'   `dir_only = TRUE`
#' }
#'
#' @examples
#' # Get the example plate file
#' plate_file <- example_plate_path()
#'
#' # Get the directory containing the example plate
#' plate_dir <- example_plate_path(dir_only = TRUE)
#'
#' # Run the cleaning pipeline using the example directory
#' result <- run_cleaning_pipeline(
#'   plate_dir,
#'   dry_run = TRUE
#' )
#'
#' @export
example_plate_path <- function(dir_only = FALSE) {
  if (!dir_only) {
    system.file(
      "extdata",
      "examplePlate.csv",
      package = "qpcrpipeline"
    )
  } else {
    system.file(
      "extdata",
      package = "qpcrpipeline"
    )
  }
}
