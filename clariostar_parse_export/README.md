# clariostarparser

Parses Excel exports from BMG CLARIOstar plate readers into a tidy long-format
data frame, plus parsed run metadata. Part of the
[jackspepper/tools](https://github.com/jackspepper/tools) collection.

Note: This package is untested for longitudinal data, and was designed for reading single-acquisition crystal violet stain measure. No guarantee is made this can read other formats for export.

## Installation

```r
# install.packages("pak")
pak::pak("jackspepper/tools", subdir = "clariostarparser")
```

## Usage

```r
library(clariostarparser)

result <- read_clariostar("ClarioSTAR_Export.xlsx")

result$metadata     # run metadata: User, Test ID, Test Name, Date, Time, ID1, ...
result$data          # primary tidy long-format data frame
result$matrix_data   # long-format data from "Microplate End point", if present
result$format_used   # "tidy" or "matrix" - which sheet became result$data
result$parse_info    # source file, sheets found, package version, parse timestamp
```

## Supported export formats

CLARIOstar exports vary by sheet selection at export time. This package
handles either sheet, or both together:

- **`Table All Data points`** — already tidy, one row per well.
- **`Microplate End point`** — stacked 8x12 plate matrices, one per
  calculated measure (Raw Data, Average, Median, %CV, good/bad, Difference).
  Parsed and pivoted to one row per well per measure.

If both sheets are present, `Table All Data points` is used as the primary
`data` output, with the matrix sheet available separately in `matrix_data`
as a cross-check.

## CSV exports

CLARIOstar can also export to a single `.csv` file, which combines the
stacked measure matrices and the tidy per-well table (plus instrument
settings and a run log) into one ragged, comma-delimited file. Use the
separate `read_clariostar_csv()` function for these:

```r
result <- read_clariostar_csv("ClarioSTAR_Export.csv")

result$metadata     # run metadata: User, Path, Test run no., Test name, Date, Time, ID1, ...
result$data          # primary tidy long-format data frame (from the "Well,Content,..." table)
result$matrix_data   # long-format data from the stacked measure matrices
result$format_used   # "tidy" or "matrix" - which section became result$data
result$parse_info    # source file, package version, parse timestamp
```

The return shape matches `read_clariostar()`, except `parse_info` has no
`sheets_found` (CSV exports have no sheets).

## Development

```r
devtools::load_all()
devtools::test()
devtools::document()
devtools::check()
```

See `NEWS.md` for release history.
