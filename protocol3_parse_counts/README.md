# protocol3Parser

`protocol3Parser` is an R package for importing and tidying ProtoCOL 3 colony counter reports exported as `.ods` spreadsheets.

The package parses each plate section from a ProtoCOL 3 report into a structured object containing:

- Plate metadata
- Colony count data
- Optional parsing of plate-name components
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

## Package Functions

### parse_protocol3()

Reads a ProtoCOL 3 `.ods` report and returns a structured list of plates.

### tidy_protocol3()

Converts the parsed plate list into a single long-format data frame.

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
