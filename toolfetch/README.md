# toolfetch

Browse and download tools from [jackspepper/tools](https://github.com/jackspepper/tools) without cloning the whole repo.

## Install

```r
install.packages("pak")
pak::pkg_install("jackspepper/tools/toolfetch")
```

(`devtools::install_github("jackspepper/tools", subdir = "toolfetch")` also works if you'd rather not add `pak`. Note `pak` caches repo metadata, so if you've just pushed changes and a reinstall isn't picking them up, that's the likely cause — try again after a few minutes or use `devtools` for an immediate pull.)

## Usage

```r
library(toolfetch)

# Interactive numbered menu, downloads into ./<tool_name>/
tools_fetch()

# Skip the menu, grab a specific folder
tools_fetch("incucyte_parse_confluency")

# Place files directly in the cwd instead of a subfolder
tools_fetch("96_well_plate_editor", subfolder = FALSE)

# List folders without downloading
tools_list()

# Force a recheck of the repo (cache normally refreshes weekly)
tools_refresh()
tools_fetch(refresh = TRUE)

# Prefer download-directory.github.io in the browser instead
tools_fetch("96_well_plate_editor", browse = TRUE)
```

## How it works

- `tools_list()` / `tools_fetch()` check a local cache (`tools::R_user_dir("toolfetch", "cache")`)
  of the repo's top-level folder names, refreshed automatically once a week.
- `refresh = TRUE` (or `tools_refresh()`) forces an immediate recheck via the GitHub contents API.
- `tools_fetch()` downloads the chosen folder's files directly (recursively) via the GitHub
  contents API — no token needed for this public repo, no browser required.
- `browse = TRUE` instead opens `download-directory.github.io` for a manual zip download.
