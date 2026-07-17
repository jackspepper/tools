# parse_confluency.R

Parses IncuCyte/HuMEE-style plate confluence export `.txt` files into two tidy data frames.

## Input format

Plain-text exports with a metadata header, a timestamp line, then a tab-separated well grid:

```
Vessel Name: 20260710_Plate1
Metric: Phase Object Confluence (%)
...
Time Stamp:	10/07/2026 10:04:00 AM	Elapsed:	0	hours

	1	2	3	...	12
A	71.11	77.28	71.97	...
B	...
```

## Dependencies

```r
install.packages(c("dplyr", "tidyr", "purrr", "stringr", "fs", "readr"))
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

result$data      # file, well, row, column, value  (one row per well)
result$metadata  # file, key, value                (long format, one row per field)
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
- `verbose = TRUE` reports per-file well counts and NA values — a quick sanity check that nothing failed to parse.
