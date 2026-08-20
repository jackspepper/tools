# qpcrpipeline 0.3.2

## New features

* Added `example_plate_path()`, which returns the path to the packaged
  example CFX Maestro plate export (`examplePlate.csv`). Use
  `dir_only = TRUE` to get the containing directory instead of the file
  itself. The example data can be piped straight into
  `run_cleaning_pipeline()` for a quick demo or smoke test.

## Documentation

* Added five vignettes: `qpcrpipeline` (setup and file conventions),
  `cleaning-pipeline`, `consolidation`, `reference` (argument and target
  defaults), and `troubleshooting`. Run `browseVignettes("qpcrpipeline")`
  to view them.
* Updated `README.md` installation instructions to use `pak` and
  `toolfetch::tools_fetch()` instead of `remotes::install_github()`.
* `here` added to `Suggests`, since the example project template
  (`use_qpcr_template()`) depends on it for path resolution.

## Bug fixes

* Fixed the example project runner script
  (`inst/example_project/qpcr_pipeline.R`): the final completion message
  referenced undefined variables (`OUTPUT_DIR`, and an inconsistently
  cased `CONSOLIDATION_DIR`), which would error after the pipeline had
  already completed successfully. Paths are now resolved consistently
  with `here::here()` and referenced with matching variable names
  throughout.

## Internal

* Example data moved from a lazy-loaded dataset (`data/examplePlate.csv`,
  documented via `examplePlate.Rd`) to `inst/extdata/examplePlate.csv`,
  accessed via the new `example_plate_path()` function. The old
  `examplePlate.Rd` man page was not removed as part of this migration
  and now documents a dataset that no longer exists in the package -
  flagged for cleanup in a future release.
* Minor `.Rd` formatting changes from an `Roxygen2` version bump
  (8.0.0 -> 8.1.0) and `Roxygen: list(markdown = TRUE)` - inline code
  spans now render as `\code{}` rather than backticks. No functional
  change.

---

# qpcrpipeline 0.3.1

* Cleaning and consolidation logic reworked from standalone scripts
  (`qpcr_cleaning_pipeline.R`, `qpcr_consolidation.R`) into exported
  package functions, `run_cleaning_pipeline()` and
  `run_consolidation_pipeline()`.
* Added `use_qpcr_template()` to scaffold a new project folder with the
  expected structure and a ready-to-run example script.
* Added `DEFAULT_target_lod` and `DEFAULT_always_positive_targets` as
  exported default lookup tables.
