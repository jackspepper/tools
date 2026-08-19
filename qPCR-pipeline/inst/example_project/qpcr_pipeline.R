# ============================================================
#  qPCR Pipeline Runner (Package-Based)
# ============================================================
#
# PURPOSE:
#   Central configuration and entry point for the qPCR
#   processing pipeline. This script uses the 'qpcrpipeline' package
#   to clean and consolidate qPCR exports from CFX Maestro.
#
# INSTALLATION:
#   install.packages("pak")
#   pak::pkg_install("jackspepper/tools/toolfetch")
#
#   toolfetch::tools_fetch(
#     folder = "qPCR-pipeline",
#     install = "auto",
#     cleanup = TRUE
#   )
#
# USAGE:
#   Set your run parameters below and run the script.
# ============================================================

library(qpcrpipeline)

# 1. Configuration
# All defaults are defined inside the package. Override only what you need.
# Note: For the example data to run out-of-the-box, we align paths:
if (basename(getwd()) == "example_project" || !dir.exists("inst")) {
  input_dir <- here::here("RawData/")
} else {
  input_dir <- "inst/example_project/RawData/"
}

output_dir <- here::here("outputs/")
consolidation_dir <- here::here("consolidated")

# QC Thresholds
delta_cq_threshold <- 1.0
n_standards <- 6
skip_completed <- TRUE

# 2. Run the pipeline using R Pipes (magrittr %>% or native |>)
# This feeds the output directory of the cleaning stage
# directly into the consolidation stage.
input_dir |>
  run_cleaning_pipeline(
    output_dir = output_dir,
    delta_cq_threshold = delta_cq_threshold,
    n_standards = n_standards,
    skip_completed = skip_completed
  ) |>
  run_consolidation_pipeline(
    consolidation_dir = consolidation_dir
  )

message(
  "\n====================================================
  qPCR Pipeline completed successfully!
  Cleaned CSV files written to: ",
  output_dir,
  "
  Consolidated workbooks written to: ",
  consolidation_dir,
  "\n===================================================="
)
