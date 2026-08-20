# Changelog

All notable changes to `qpcrpipeline` are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
For the user-facing summary, see [`NEWS.md`](NEWS.md).

## [0.3.2] - 2026-08-20

### Added

- `example_plate_path()` - returns the path to the packaged example CFX
  Maestro export (`inst/extdata/examplePlate.csv`), with a `dir_only`
  argument to return the containing directory instead. Exported and
  documented (`man/example_plate_path.Rd`).
- Five package vignettes shipped for the first time: `qpcrpipeline`,
  `cleaning-pipeline`, `consolidation`, `reference`, `troubleshooting`.
  `VignetteBuilder: knitr` and `Roxygen: list(markdown = TRUE)` added to
  `DESCRIPTION` to support this.

### Changed

- `DESCRIPTION`:
  - `Version` bumped `0.3.1` -> `0.3.2`.
  - `Suggests` gained `knitr`, `rmarkdown`, `here` (previously only
    `testthat (>= 3.0.0)`, `tibble`).
  - `Config/roxygen2/version` bumped `8.0.0` -> `8.1.0`.
  - `LazyData: true` removed (no longer applicable - no lazy-loaded
    dataset remains in `data/`).
- `README.md`: install instructions changed from
  `remotes::install_github("jackspepper/qPCR-pipeline")` to
  `pak::pkg_install("jackspepper/tools/toolfetch")` +
  `toolfetch::tools_fetch()`. Removed the "imported from another repo,
  requires cleaning" migration notice and the CI/license badges.
- `inst/example_project/qpcr_pipeline.R`:
  - Install instructions in the header comment updated to match the new
    `toolfetch`-based method.
  - `input_dir`, `output_dir`, and `consolidation_dir` now resolved via
    `here::here()` instead of bare relative paths.
  - Variable naming made consistent (`CONSOLIDATION_DIR` -> lowercase
    `consolidation_dir` throughout).
- `man/run_cleaning_pipeline.Rd`, `man/run_consolidation_pipeline.Rd`:
  cosmetic-only re-render of inline code spans (backtick -> `\code{}`),
  no argument or behaviour changes.

### Fixed

- `inst/example_project/qpcr_pipeline.R`: the completion `message()` at
  the end of the script referenced `OUTPUT_DIR` and `CONSOLIDATION_DIR`,
  neither of which matched the actual variable names in scope
  (`output_dir`, `CONSOLIDATION_DIR` used inconsistently elsewhere in the
  file). This raised an "object not found" error immediately after the
  pipeline had already completed successfully. Variable names are now
  consistent throughout the script.

### Deprecated / Known issues

- `man/examplePlate.Rd` documents a lazy-loaded `examplePlate` dataset
  that no longer exists: `data/examplePlate.csv` was removed and
  replaced with `inst/extdata/examplePlate.csv` (see `example_plate_path()`
  above), but the corresponding `.Rd` file was left behind. This will
  produce an orphaned/incorrect help page (`?examplePlate`) until removed
  in a future release.

### Internal

- `data/examplePlate.csv` removed; superseded by
  `inst/extdata/examplePlate.csv`.
- `build/vignette.rds` and `inst/doc/*` (rendered `.R`/`.Rmd`/`.html` per
  vignette) now present as build artifacts from `VignetteBuilder: knitr`.
- No changes to `tests/testthat/*` in this release - note that the new
  `example_plate_path()` function currently has no accompanying test.

---

## [0.3.1] - 2026-08-20 (baseline for this changelog)

### Changed

- Cleaning and consolidation logic reworked from standalone scripts
  (`qpcr_cleaning_pipeline.R`, `qpcr_consolidation.R`) into exported
  package functions, `run_cleaning_pipeline()` and
  `run_consolidation_pipeline()`.

### Added

- `use_qpcr_template()` - scaffolds a new project folder with the
  expected structure and a ready-to-run example script.
- `DEFAULT_target_lod`, `DEFAULT_always_positive_targets` - exported
  default lookup tables for target LOD values and always-positive
  target names.

[0.3.2]: https://github.com/jackspepper/tools/tree/main/qPCR_pipeline
[0.3.1]: https://github.com/jackspepper/tools/tree/main/qPCR_pipeline
