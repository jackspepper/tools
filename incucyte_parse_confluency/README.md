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

**Matrix** — one or more timestamp blocks, each followed by one or more tab-separated
well grids. A grid may optionally be preceded by a label line naming it:

- a metric name (e.g. `Std Err Img`) — if unlabeled, the file's top-level `Metric:`
  field is used instead.
- an image number (e.g. `Image 1`, `Image 2`) for **longitudinal/multi-image
  exports**, where more than one image is captured per well per timepoint.

```
Vessel Name: 20260710_Plate1
Metric: Phase Object Confluence (%)
...
Time Stamp:	10/07/2026 10:04:00 AM	Elapsed:	0	hours

Image 1
	1	2	3	...	12
A	71.11	77.28	71.97	...
B	...

Image 2
	1	2	3	...	12
A	70.98	77.10	71.85	...
B	...

Time Stamp:	10/07/2026 11:04:00 AM	Elapsed:	1	hours
...
```

Multiple `Time Stamp:` blocks (multiple timepoints in one file) and multiple
`Image N` grids per timepoint are both fully supported.

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
  xlsx    = FALSE                 # FALSE = csv, TRUE = single xlsx workbook
)

result$data      # file, file_path, timestamp, elapsed_hours, image, metric, well, row, column, value
result$metadata  # file, file_path, key, value  (long format, one row per field)
```

Export can also be run separately on an existing result:

```r
write_confluency_output(result, out_dir = "output", xlsx = TRUE)
```

## Output

- **csv** (default): `confluency_data.csv`, `confluency_metadata.csv`
- **xlsx** (`xlsx = TRUE`): single `confluency_export.xlsx`, one sheet per data frame

### `data` columns

| column          | meaning                                                                 |
|-----------------|--------------------------------------------------------------------------|
| `file`          | source filename                                                          |
| `file_path`     | full path to the source file (absolute, as scanned), for tracing a row back to the exact file on disk |
| `timestamp`     | this row's timepoint (Date/Time as read from the export)                 |
| `elapsed_hours` | elapsed hours for that timepoint                                         |
| `image`         | image number, for longitudinal/multi-image exports; `NA` if the file only has a single image per well/timepoint |
| `metric`        | which measurement (usually one per file, but matrix files can have several, e.g. confluence + `Std Err Img`) |
| `well`, `row`, `column` | well identifiers, useful for plate heatmaps (`ggplot2::geom_tile()`) |
| `value`         | the measurement                                                          |

## Notes

- `metadata` is long-format (`key`/`value` pairs) so it accommodates files with different
  fields. Widen with:
  ```r
  result$metadata %>% tidyr::pivot_wider(names_from = key, values_from = value)
  ```
- For matrix files with a **single** timepoint, `Time Stamp` / `Elapsed (hours)` are
  also echoed into `metadata` for convenience. Files with multiple timepoints instead
  record a `Time Stamp Count` metadata field — use the per-row `timestamp` /
  `elapsed_hours` columns in `data` for those.
- `image` is `NA` unless a file has more than one longitudinal image per well per
  timepoint. Filter to a single image (or `is.na(image)`) before reshaping to
  wide/heatmap form, alongside filtering to a single `metric` and `timestamp`:
  ```r
  result$data %>%
    filter(file == "Plate4.txt", metric == "Phase Object Confluence (%)",
           timestamp == first(timestamp), is.na(image) | image == 1)
  ```
- `verbose = TRUE` reports per-file row counts and NA values — a quick sanity check
  that nothing failed to parse.
