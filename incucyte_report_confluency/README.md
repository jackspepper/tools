# IncuCyte_Confluency_Report.qmd

Quarto report that parses IncuCyte/HuMEE-style plate confluency exports and produces
per-plate/per-date summaries, well-flagging, and heatmaps (raw + stage-to-stage delta).

## Setup

Two things need to be in place before rendering:

1. **An `.Rproj` in this folder.** The report uses `here::here()` to build all its
   paths, which anchors to the `.Rproj` location rather than the current working
   directory — needed for consistent renders whether run from RStudio, `quarto
   render`, or a scheduled job.
2. **`parse_confluency.R`.** Not bundled with the report — on first render it is
   downloaded automatically from
   [jackspepper/tools](https://github.com/jackspepper/tools/blob/main/incucyte_parse_confluency/parse_confluency.R)
   into `R/parse_confluency.R` and cached there. This is a stopgap until the script is
   packaged; delete `R/parse_confluency.R` to force a re-download of the latest
   version. See that repo's README for full details on the parser itself (input
   formats, output columns, etc.).

## Dependencies

```r
install.packages(c("tidyverse", "knitr", "kableExtra", "here",
                    "dplyr", "tidyr", "purrr", "stringr"))
```

## Folder layout expected

```
your-project/
├── your-project.Rproj
├── R/
│   └── parse_confluency.R   # auto-downloaded on first render
├── output/                  # created automatically; csv + png outputs land here
├── IncuCyte_Confluency_Report.qmd
└── ...                      # IncuCyte export .txt files, searched up to 5 levels deep
```

By default the report searches for export files starting from the parent of this
folder (`data_dir <- here("..")`, `depth = 5`, filename pattern `"Plate.*\\.txt$"`).
Adjust `data_dir`, `depth`, or `pattern` in the setup chunk if your exports live
elsewhere.

## Usage

1. Place this `.qmd` (and an `.Rproj`) in a folder near your IncuCyte export files.
2. Edit **Study configuration** (assay stage order, primary metric, acceptable
   confluence range) and **Exclusions** (dates/plates/metrics/wells/imaging
   types/dates to drop) to match the current run.
3. Render:
   ```r
   quarto::quarto_render("IncuCyte_Confluency_Report.qmd")
   ```

## Output

Written to `output/`:

- `confluency_data.csv`, `confluency_metadata.csv` — tidy parsed data (see parser
  README for column definitions)
- `PlateConfluencyHeatmap.png` — raw well-level confluence
- `PlateFlaggedWellsHeatmap.png` — wells outside the configured range
- `PlateStageDeltaHeatmap.png` — well-level change between assay stages

## Report sections

| Section | What it shows |
|---|---|
| Parse data | Parses exports into a tidy table; derives `date`, `plate`, `imaging_date`, `imaging_type` from file paths |
| Study configuration | Editable: assay stage order, primary metric, confluence range |
| Exclusions | Editable: drop specific dates/plates/metrics/wells/imaging types before any analysis |
| Summaries | Descriptive stats (n, mean, sd, min, max) per date-group and per plate |
| Flagged wells | Wells outside the configured confluence range |
| Plate heatmaps | Well-level confluence, and the same with flags highlighted |
| Assay stage comparison | Per-well and per-plate deltas between assay stages (e.g. Prefix → Postfix), plus delta heatmaps |
| Metadata | Raw key/value metadata parsed from each source file |

## Notes

- Rows/columns auto-detect from the data — 6-, 24-, 96-, and 384-well plates all work
  without editing the report.
- `imaging_date`/`imaging_type` are parsed from filenames of the form
  `..._Imaged27JUL2026_Prefix.txt`; both are `NA` (rows still kept) if the pattern
  isn't present.
- The assay stage comparison section only compares stage pairs actually present for a
  given well/date/plate/metric — missing images are skipped, not treated as zero.
