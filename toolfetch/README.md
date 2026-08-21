# toolfetch

Browse and download tools from [jackspepper/tools](https://github.com/jackspepper/tools) without cloning the whole repo. Folders that are R packages (i.e. contain a top-level `DESCRIPTION` file) can be installed automatically via `pak`. Fetches from any branch, defaulting to `main`. Fully scriptable — pass `folder` directly to skip all prompts.

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

# List folders on a different branch
tools_list(branch = "dev")

# List available branches
tools_branches()

# Force a recheck of the repo (cache normally refreshes weekly)
tools_refresh()
tools_fetch(refresh = TRUE)

# Prefer download-directory.github.io in the browser instead
tools_fetch("96_well_plate_editor", browse = TRUE)
```

### Fetching from a branch

By default, everything fetches from `main`. Pass `branch` to work against
tools that are still in development on another branch:

```r
# Scripted: fetch a specific folder from a specific branch
tools_fetch("toolfetch", branch = "dev")

# List folders on that branch first
tools_list(branch = "dev")

# See what branches exist
tools_branches()
#>  1. dev
#>  2. main  (default)
#>  3. someone/feature-x
```

Calling `tools_fetch()` interactively with no arguments now shows a branch
menu first, before the folder menu:

```r
tools_fetch()
#> Available branches in jackspepper/tools:
#>
#>  1. dev
#>  2. main  (default)
#>
#> Enter a number to select a branch (or Enter for 'main', 0 to cancel):
```

Press Enter to accept the default (`main`) and go straight to the usual
folder menu, or pick a number to browse that branch's folders instead.

Passing `folder` directly (the scripted path) skips the branch prompt
entirely and uses `main` unless `branch` is also given — so existing
scripted calls like `tools_fetch("toolfetch", force = TRUE)` are
unaffected by this change.

The folder listing is cached separately per branch, so checking `dev`
doesn't invalidate or overwrite the cached listing for `main`, and each
refreshes independently on its own weekly schedule (or via `refresh =
TRUE`).

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

### Cleaning up after package install

If you only wanted the package installed (not the downloaded source kept
around), pass `cleanup = TRUE` (default behaviour). This deletes `dest_dir` after a successful
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

# Same, but pinned to a specific branch instead of main
tools_fetch(
  "toolfetch",
  branch  = "dev",
  force   = TRUE,
  install = "auto",
  cleanup = TRUE,
  quiet   = TRUE
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
  branch     = "main",  # branch actually fetched from
  is_package = TRUE,    # whether a top-level DESCRIPTION was found
  installed  = TRUE,    # whether pak install actually ran
  cleaned_up = TRUE     # whether dest_dir was deleted post-install
)
```

## How it works

- `tools_list()` / `tools_fetch()` check a local cache (`tools::R_user_dir("toolfetch", "cache")`)
  of the repo's top-level folder names, refreshed automatically once a week. The cache is
  keyed per branch, so `main` and `dev` (for example) are tracked independently.
- `tools_branches()` similarly caches the repo's branch list, refreshed weekly.
- `refresh = TRUE` (or `tools_refresh()`) forces an immediate recheck via the GitHub contents API,
  for whichever branch was requested (default `main`).
- `tools_fetch()` downloads the chosen folder's files directly (recursively) via the GitHub
  contents API — no token needed for this public repo, no browser required.
- Package detection (top-level `DESCRIPTION` file) is determined from the same file listing
  used for download, so it costs no extra API calls.
- `force = TRUE` deletes the destination directory's existing contents before writing.
- `browse = TRUE` instead opens `download-directory.github.io` for a manual zip download.
