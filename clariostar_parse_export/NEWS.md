# clariostarparser 0.2.0

* Adds `read_clariostar_csv()` to parse CLARIOstar CSV exports (a separate
  function from `read_clariostar()`, since the CSV format packages both the
  stacked measure matrices and the tidy per-well table into a single ragged,
  comma-delimited file rather than separate sheets).

# clariostarparser 0.1.0

* Initial release.
* `read_clariostar()` parses BMG CLARIOstar Excel exports into a tidy
  long-format data frame plus run metadata.
* Supports the `"Table All Data points"` export (tidy) and the
  `"Microplate End point"` export (stacked plate matrices), and both
  together when present.
* Adds `parse_info` tracking metadata (source file, sheets found, package
  version, parse timestamp) to every parsed result for traceability.
