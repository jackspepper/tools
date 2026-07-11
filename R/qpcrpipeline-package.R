#' qpcrpipeline: MIQE-aligned qPCR Data Cleaning and Consolidation Pipeline
#'
#' An R package for cleaning, auditing, and consolidating qPCR data.
#'
#' @import dplyr
#' @import tidyr
#' @import openxlsx
#' @import readr
#' @import stringr
#' @import fs
#' @import cli
#' @import rlang
#' @import lubridate
#' @importFrom utils packageVersion head tail read.csv write.csv sessionInfo
#' @importFrom stats median sd
#' @importFrom grDevices dev.off
#' @importFrom stats setNames
#' @importFrom utils flush.console timestamp
#' @importFrom purrr pmap_chr
#' @name qpcrpipeline
NULL

# Register non-standard evaluation variables used by dplyr pipelines.
# This prevents R CMD check NOTES for data mask globals in package internals.
utils::globalVariables(c(
  ".display", "MAX_WRITE_TRIES", "WAIT_SECS", "Sheet", "Target",
  "action", "all_adjusted", "all_cq_na", "avg_sq", "both_cq_na",
  "content", "cq", "cq_num", "cq_vals", "delta_cq", "elapsed_s",
  "excess_reps", "flag_name_mismatch", "fluor", "input_file",
  "lod_override", "missing_standards", "n_num_cq", "n_rows", "n_samples",
  "needs_review", "notes", "one_cq_na", "out_average_sq", "out_delta_cq",
  "out_reason", "outcome", "pass_negative", "plate", "plate_sort",
  "rep_idx", "review_reason", "rm_hit", "rows_out", "rule_id", "run_id",
  "rv_delta_cq", "rv_excess_reps", "rv_high_sq", "rv_mixed_na_num",
  "rv_single_rep", "rv_unexpected_neg", "rv_unexpected_neg_sub",
  "sample_reason", "samples", "secs_per_row", "single_rep", "sq_adj",
  "sq_adj_reason", "sq_raw", "starting_quantity_sq", "status", "target",
  "well"
))
