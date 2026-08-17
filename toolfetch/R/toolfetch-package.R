#' toolfetch: Browse and Install Tools from jackspepper/tools
#'
#' Provides an interactive way to browse the top-level folders in the
#' jackspepper/tools GitHub repository and download a chosen one into the
#' current working directory. Maintains a local cache of the folder listing
#' that refreshes weekly, and can be forced to recheck on demand.
#'
#' @section Main functions:
#' \describe{
#'   \item{\code{\link{tools_list}}}{List available tool folders.}
#'   \item{\code{\link{tools_fetch}}}{Interactively pick and download one.}
#'   \item{\code{\link{tools_refresh}}}{Force a recheck of the repo.}
#' }
#'
#' @keywords internal
"_PACKAGE"
