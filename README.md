# tools
This is just a collection of tools that I have created or found useful. Some of them are standalone scripts, while others are small programs. Feel free to use them as you see fit.

## Installation
Install the `toolfetch` package, then use it to browse and download individual tool folders as needed:
```
install.packages("pak")
pak::pkg_install("jackspepper/tools/toolfetch")
 
library(toolfetch)
tools_fetch()
```
(`devtools::install_github("jackspepper/tools", subdir = "toolfetch")` also works if you'd rather not add `pak`.)
 
See the [toolfetch README](./toolfetch/README.md) for full usage.

## Tools
[toolfetch](./toolfetch) - An R package for browsing and downloading tools from this repo (see Installation above).\
[Incucyte Confluency Parser](./incucyte_parse_confluency/) - A script to parse Incucyte confluency analysis data and output a tidy data frame.\
[Incucyte Confluency Report](./incucyte_report_confluency/) - A Quarto report that builds on the parser to produce per-plate/per-date summaries, well-flagging, and confluence heatmaps.\
[96-Well Plate Editor](./96_well_plate_editor/) - A standalone browser app to create a visualisation of 96-well plate layouts with colours and dilutions.\
[ND2 Composite](./nd2_composite/) - A python script that converts .nd2 Z-stacks into Maximum Intensity Plots (MIP).\
[Microscopy Presentation](./microscopy_presentation_pipeline/) - A Quarto document that builds a automatic presentation of microscopy Z-stack MIPs using python helper functions.\
[qPCR Pipeline](./qPCR_pipeline/) - A qPCR pipeline for cleaning and identifying samples that require additional scrutiny.\
[ProtoCOL3 Counts Parser](./protocol3_parse_counts) - A small package that parses region count data export from the ProtoCOL3 (v1.0.26.0) OPKA protocol.
