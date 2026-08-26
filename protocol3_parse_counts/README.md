# protocol3Parser

`protocol3Parser` is an R package for importing and tidying ProtoCOL 3 reports exported as `.ods` spreadsheets: colony counts and antibiotic resistance (zone diameter) reports.

The package parses each plate section from a ProtoCOL 3 report into a structured object containing:

- Plate metadata
- Colony count data, or antibiotic zone/susceptibility data
- Optional parsing of plate-name components
- Optional splitting of multi-value `Flags` into a vector per row
- Optional exclusion of plates matching a string (e.g. `"_Exclude"` in the plate name)
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

- readODS

## Example Data

The package includes an example ProtoCOL 3 report:

```r
file <- system.file(
  "extdata",
  "ExampleCounts.ods",
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

## Package Functions

### parse_protocol3()

Reads a ProtoCOL 3 colony counter `.ods` report and returns a structured list of plates.

### parse_protocol3_abx()

Reads a ProtoCOL 3 antibiotic zone plate `.ods` report and returns a structured list of plates, with the same options (`name_components`, `split_flags`, `exclude`, `exclude_column`) as `parse_protocol3()`.

### split_flags()

Splits a space-separated `Flags` string (or vector of them) into a list of character vectors.

### tidy_protocol3()

Converts a parsed plate list (colony count or Abx) into a single long-format data frame. If filtering with `exclude`, pass `res$included` or `res$excluded`, not the wrapper itself.

## Workflow

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
