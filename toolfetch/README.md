# toolfetch

Browse and download tools from [jackspepper/tools](https://github.com/jackspepper/tools) without cloning the whole repo. Folders that are R packages (i.e. contain a top-level `DESCRIPTION` file) can be installed automatically via `pak`. Fully scriptable — pass `folder` directly to skip all prompts.

## Install

```r
install.packages("pak")
pak::pkg_install("jackspepper/tools/toolfetch")
```

(`devtools::install_github("jackspepper/tools", subdir = "toolfetch")` also works if you'd rather not add `pak`. Note `pak` caches repo metadata, so if you've just pushed changes and a reinstall isn't picking them up, that's the likely cause — try again after a few minutes or use `devtools` for an immediate pull.)

`pak` is only required if you want automatic package installation (`install = "auto"`); it's listed under `Suggests`, not a hard dependency.

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

### Overwriting an existing download

By default, `tools_fetch()` refuses to write into a destination folder that
already exists and has files in it:

```r
tools_fetch("toolfetch")
#> Error: Destination '.../toolfetch' already exists and is not empty.
#> Use force = TRUE to overwrite.

# Wipe the existing folder and redownload fresh
tools_fetch("toolfetch", force = TRUE)
```

### Installing packages found in the repo

If the chosen folder contains a top-level `DESCRIPTION` file, it's treated as
an R package. What happens next is controlled by `install`:

| `install =` | Behaviour |
|---|---|
| `"ask"` (default) | Prompts interactively if a package is detected and the session is interactive. In non-interactive sessions, behaves like `"never"`. |
| `"auto"` / `TRUE` | Installs via `pak::pkg_install()` immediately, no prompt. |
| `"never"` / `FALSE` | Never installs, even if a package is detected. |

```r
# Interactive: will ask "Install 'mypkg' now with pak? [y/N]"
tools_fetch("mypkg")

# Scripted: install with no prompts
tools_fetch("mypkg", install = "auto")

# Just grab the files, never install
tools_fetch("mypkg", install = "never")
```

### Cleaning up after install

If you only wanted the package installed (not the downloaded source kept
around), pass `cleanup = TRUE`. This deletes `dest_dir` after a successful
`pak` install — the package remains installed in your R library, but the
downloaded folder is removed:

```r
tools_fetch("mypkg", install = "auto", cleanup = TRUE)
```

`cleanup` only has an effect if the folder is a package *and* an install
actually ran (i.e. it's ignored for plain tool folders, and ignored if
`install = "never"` or an `"ask"` prompt was declined).

### Fully scripted / automated use

For use in scripts, CI, or scheduled jobs, combine `folder`, `force`, and
`install` to run with zero prompts:

```r
tools_fetch(
  "toolfetch",
  force   = TRUE,   # overwrite any existing download
  install = "auto", # install via pak if it's a package, no prompt
  cleanup = TRUE,   # remove the downloaded source once installed
  quiet   = TRUE    # suppress status messages
)
```

Note: `tools_fetch()` errors immediately if `folder = NULL` and the session
is non-interactive (e.g. run via `Rscript`), rather than hanging on a menu
prompt — always pass `folder` explicitly for scripted use.

### Return value

`tools_fetch()` returns (invisibly) a list:

```r
list(
  dest_dir   = "...",   # path the files were written to (may no longer
                         # exist on disk if cleaned_up is TRUE)
  is_package = TRUE,    # whether a top-level DESCRIPTION was found
  installed  = TRUE,    # whether pak install actually ran
  cleaned_up = TRUE     # whether dest_dir was deleted post-install
)
```

## How it works

- `tools_list()` / `tools_fetch()` check a local cache (`tools::R_user_dir("toolfetch", "cache")`)
  of the repo's top-level folder names, refreshed automatically once a week.
- `refresh = TRUE` (or `tools_refresh()`) forces an immediate recheck via the GitHub contents API.
- `tools_fetch()` downloads the chosen folder's files directly (recursively) via the GitHub
  contents API — no token needed for this public repo, no browser required.
- Package detection (top-level `DESCRIPTION` file) is determined from the same file listing
  used for download, so it costs no extra API calls.
- `force = TRUE` deletes the destination directory's existing contents before writing.
- `browse = TRUE` instead opens `download-directory.github.io` for a manual zip download.
