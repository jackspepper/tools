# parse_confluency.R

Parses IncuCyte/HuMEE-style plate confluence export `.txt` files into two tidy data frames.

## Input formats

Two layouts are auto-detected per file — no configuration needed.

**Wide-row** — one header line of well IDs (any order), one data row per timepoint:

```
Vessel Name: 20260710_Plate1
Metric: Phase Object Confluence (%)
...

Date Time	Elapsed	A1	B1	C1	...
10/07/2026 10:04:00 AM	0	71.11	77.28	71.97	...
```

**Matrix** — timestamp line followed by one or more tab-separated well grids. A grid may optionally be preceded by a label line naming the metric (e.g. `Std Err Img`); if unlabeled, the file's top-level `Metric:` field is used:

```
Vessel Name: 20260710_Plate1
Metric: Phase Object Confluence (%)
...
Time Stamp:	10/07/2026 10:04:00 AM	Elapsed:	0	hours

	1	2	3	...	12
A	71.11	77.28	71.97	...
B	...
```

Multi-image exports (grids labeled `Image 1`, `Image 2`, ...) are **not yet supported** — see [Notes](#notes).

## Dependencies

```r
install.packages(c("dplyr", "tidyr", "purrr", "stringr"))
# only needed if xlsx = TRUE:
install.packages("openxlsx")
```

## Usage

```r
source("parse_confluency.R")

result <- read_confluency_folder(
  folder  = "path/to/folder",
  depth   = 0,                    # 0 = this folder only, 1 = +1 subfolder level, Inf = fully recursive
  pattern = "Plate.*\\.txt$",     # filename filter (regex)
  verbose = TRUE,                 # print progress messages
  progress = FALSE,               # txtProgressBar instead (ignored if verbose = TRUE)
  export  = FALSE,                # also write to disk (see below)
  out_dir = "output",
  xlsx    = FALSE,                # FALSE = csv, TRUE = single xlsx workbook
  skip_on_unsupported = NA        # NA = ask interactively, TRUE = auto-skip, FALSE = error (see Notes)
)

result$data      # file, metric, well, row, column, value  (one row per well per metric)
result$metadata  # file, key, value                        (long format, one row per field)
```

Export can also be run separately on an existing result:

```r
write_confluency_output(result, out_dir = "output", xlsx = TRUE)
```

## Output

- **csv** (default): `confluency_data.csv`, `confluency_metadata.csv`
- **xlsx** (`xlsx = TRUE`): single `confluency_export.xlsx`, one sheet per data frame

## Notes

- `metadata` is long-format (`key`/`value` pairs) so it accommodates files with different fields. Widen with:
  ```r
  result$metadata %>% tidyr::pivot_wider(names_from = key, values_from = value)
  ```
- `data` includes `row`/`column` as well as the combined `well` ID, useful for plate heatmaps (`ggplot2::geom_tile()`).
- `data` includes a `metric` column. Most files have a single metric (from the `Metric:` metadata field, or `NA` if that field is absent). Matrix files with multiple labeled grids (e.g. confluence + `Std Err Img`) will have one row per well *per metric* — filter to a single metric before reshaping to wide/heatmap form.
- **Unsupported multi-image exports**: grids labeled `Image 1`, `Image 2`, etc. (multiple longitudinal images from the same plate/timepoint) aren't parsed yet. Behavior is controlled by `skip_on_unsupported`:
  - `NA` (default) — prompts interactively whether to skip the file; errors if run non-interactively.
  - `TRUE` — skips affected blocks/files automatically, with a warning.
  - `FALSE` — stops immediately with an error.
- `verbose = TRUE` reports per-file row counts and NA values — a quick sanity check that nothing failed to parse.