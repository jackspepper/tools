# protocol3Parser

`protocol3Parser` is an R package for importing and tidying ProtoCOL 3 reports exported as `.ods` spreadsheets: colony counts and antibiotic resistance (zone diameter) reports.

The package parses each plate section from a ProtoCOL 3 report into a structured object containing:

- Plate metadata
- Colony count data, or antibiotic zone/susceptibility data
- Optional parsing of plate-name components
- Optional splitting of multi-value `Flags` into a vector per row
- Optional exclusion of plates matching a string (e.g. `"_Exclude"` in the plate name)
- Embedded package version and timestamp for auditability & provenance tracking
- Conversion to a single tidy data frame for downstream analysis

## Installation

You can install the package directly from GitHub:

```r
install.packages("pak")
pak::pkg_install("jackspepper/tools/toolfetch")
 
toolfetch::tools_fetch("protocol3_parse_counts", install = "auto")
```
(`devtools::install_github("jackspepper/tools", subdir = "protocol3_parse_counts")` also works if you'd rather not add `pak`.)

## Dependencies

- **Imports**: `readODS`
- **Suggests**: `testthat (>= 3.0.0)`

## Example Data

The package includes example ProtoCOL 3 reports:

```r
# Colony counts report example
counts_file <- system.file(
  "extdata",
  "ExampleCounts.ods",
  package = "protocol3Parser"
)

# Antibiotic zone report example
abx_file <- system.file(
  "extdata",
  "ExampleAbxRes.ods",
  package = "protocol3Parser"
)
```

## Basic Usage

Load the package and parse a report:

```r
library(protocol3Parser)

file <- system.file(
  "extdata",
  "ExampleCounts.ods",
  package = "protocol3Parser"
)

plates <- parse_protocol3(file)
```

The result is a named list, with one entry per plate.

```r
names(plates)
```

Inspect metadata:

```r
plates[[1]]$metadata
```

Inspect colony count data:

```r
plates[[1]]$data
```

## Parsing Plate Name Components

Plate names often contain underscore-separated fields.

For example:

```text
20260712_24h_SubjectA_Plate1
```

These can be split into named metadata columns:

```r
plates <- parse_protocol3(
  file,
  name_components = c(
    "Date",
    "BacTime",
    "Subject",
    "PlateID"
  )
)
```

The extracted components are appended to each plate's metadata table.

## Auditability & Provenance Tracking

For audit compliance, both `parse_protocol3()` and `parse_protocol3_abx()` automatically record provenance metadata by default (`include_version = TRUE`):

1. **Metadata Column**: A `"Parser Version"` column (e.g. `"0.1.0.9000"`) is added to each plate's metadata table, which is automatically included in `tidy_protocol3()` data frames.
2. **Object Attributes**: Top-level attributes `parser_version` and `parsed_at` (timestamp) are attached to returned lists and tidy data frames:

```r
attr(plates, "parser_version")
#> [1] "0.1.0.9000"

attr(plates, "parsed_at")
#> [1] "2026-08-26 14:44:00 AWST"
```

To disable metadata version embedding, pass `include_version = FALSE`.

## Creating a Tidy Data Frame

Combine all plate data into a single analysis-ready table:

```r
tidy_data <- tidy_protocol3(plates)
```

Example:

```r
head(tidy_data)
```

Each row represents a single sector/well and includes:

- Plate metadata
- Parser Version (if `include_version = TRUE`)
- Parsed name components (if requested)
- Sector
- Colony Name
- Count / Frame
- Flags

## Antibiotic Resistance (Zone) Reports

For ProtoCOL 3 antibiotic zone plate reports, use `parse_protocol3_abx()` instead. It has the same interface as `parse_protocol3()`, but reads the zone-report columns (`Sector`, `Zone Name`, `Zone Diameter (mm)`, `Antibiotic Susceptibility`, `Flags`):

```r
file <- system.file(
  "extdata",
  "ExampleAbxRes.ods",
  package = "protocol3Parser"
)

plates <- parse_protocol3_abx(file)
plates[["1.1A"]]$data
```

## Splitting Multi-Value Flags

ProtoCOL 3 stores multiple flags as a single space-separated string (e.g. `"E M"`). Both parsers add a `Flags_list` column by default (`split_flags = TRUE`), giving each row a character vector of individual flags:

```r
plates[["1.1B"]]$data$Flags_list
#> [[1]]
#> [1] "E" "M"
```

You can also apply this to any flags string directly:

```r
split_flags(c("E M", "M", NA))
```

Set `split_flags = FALSE` to skip this and keep only the raw `Flags` string.

## Excluding Plates

Pass `exclude` to drop plates whose plate name (or another metadata column) contains a given string. Matches are reported to the console, and the result is split into `$included` / `$excluded`:

```r
res <- parse_protocol3_abx(file, exclude = "_Exclude")
#> Excluded 1 plate(s) matching '_Exclude' in 'Plate Name': 1.2A_Exclude

names(res$included)  # plates that passed through
names(res$excluded)  # plates that were dropped
```

By default the string is matched against `"Plate Name"`. To match against a different metadata field (e.g. `"User"`, `"Comments / Notes"`, or a `name_components` column), set `exclude_column`:

```r
res <- parse_protocol3_abx(file, exclude = "repeat", exclude_column = "Comments / Notes")
```

If `exclude` is not supplied, both functions return the plain per-plate list as before (no `$included`/`$excluded` wrapper) — this is fully backward compatible with existing code.

## Package Structure & Functions

### R Source Files

- `R/parse_protocol3.R`: High-level exported parser functions (`parse_protocol3()` and `parse_protocol3_abx()`).
- `R/parse_helpers.R`: Shared internal block parser, post-processing, and plate filter helper functions.
- `R/split_flags.R`: `split_flags()` utility function.
- `R/tidy_protocol3.R`: `tidy_protocol3()` dataset flattening function.

### Functions Overview

- `parse_protocol3()`: Reads a ProtoCOL 3 colony counter `.ods` report and returns a structured list of plates.
- `parse_protocol3_abx()`: Reads a ProtoCOL 3 antibiotic zone `.ods` report and returns a structured list of plates.
- `split_flags()`: Splits space-separated `Flags` strings into lists of character vectors.
- `tidy_protocol3()`: Converts a parsed plate list into a single long-format data frame.

## Testing & Development

Run the `testthat` suite locally using R:

```r
testthat::test_dir("tests/testthat")
```

## Example Workflow

```r
file <- system.file(
  "extdata",
  "ExampleCounts.ods",
  package = "protocol3Parser"
)

plates <- parse_protocol3(
  file,
  name_components = c(
    "Date",
    "BacTime",
    "Subject",
    "PlateID"
  )
)

results <- tidy_protocol3(plates)
```
