# toolfetch 0.4.0

## New features

* All fetching/listing functions gain a `branch` argument, so tools can be
  browsed and fetched from any branch of `jackspepper/tools` — not just the
  default (`main`) — to test in-development work before it's merged.
  `branch = NULL` (the default everywhere) resolves to `main`.
  * `tools_list(branch = ...)`, `tools_refresh(branch = ...)`,
    `tools_fetch(branch = ...)` all accept it.
  * `tools_fetch()`'s interactive menu (when both `folder` and `branch` are
    left `NULL`) now shows a branch picker first, defaulting to `main` on
    Enter, before showing that branch's folder menu. Passing `folder`
    explicitly (scripted use) skips the branch prompt entirely and just
    uses `main` unless `branch` is also given.
  * The folder-listing cache is now kept per-branch, so switching branches
    doesn't invalidate or clobber the cache for other branches.
* New `tools_branches()` lists branches in `jackspepper/tools`, with the
  same caching/`refresh` behaviour as `tools_list()`. The default branch is
  marked in the printed output.
* `tools_fetch()`'s return list gains `branch` (character), the branch
  actually fetched from.

# toolfetch 0.3.0

## New features

* `tools_fetch()` gains a `cleanup` argument. If `TRUE`, the downloaded
  folder is deleted after a package install actually runs via `pak`,
  leaving only the installed package (no source folder left behind). Has no
  effect for non-package folders, or if `install` doesn't end up installing
  anything.
* `tools_fetch()`'s return list gains `cleaned_up` (logical), indicating
  whether `dest_dir` was removed.

# toolfetch 0.2.0

## New features

* `tools_fetch()` gains a `force` argument. By default, fetching into a
  destination that already exists and contains files now errors instead of
  silently merging/overwriting; pass `force = TRUE` to delete the existing
  contents and redownload fresh.
* `tools_fetch()` gains an `install` argument (`"ask"` / `"auto"` / `"never"`,
  also accepts `TRUE`/`FALSE`) controlling whether folders detected as R
  packages (top-level `DESCRIPTION` file) are installed via `pak`. `"auto"`
  installs with no prompt, suitable for scripts and CI.
* `tools_fetch()` can now be fully automated: passing `folder` together with
  `force` and/or `install` runs with zero interactive prompts. Calling it
  with `folder = NULL` in a non-interactive session (e.g. `Rscript`) now
  errors immediately with a clear message instead of hanging on `readline()`.
* `tools_fetch()` now returns (invisibly) a list — `dest_dir`, `is_package`,
  `installed` — instead of just the destination path, so scripts can branch
  on the outcome.

## Notes

* `pak` moved from an implicit runtime dependency to `Suggests`; it's only
  needed when `install` triggers an actual package installation.
* Package detection reuses the file listing already fetched for download, so
  it adds no extra GitHub API calls.

# toolfetch 0.1.0

* Initial release: `tools_list()`, `tools_fetch()`, `tools_refresh()`.
