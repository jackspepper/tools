# Microscopy Imaging Presentation

A Quarto document (`Microscopy_Imaging_Presentation.qmd`) that turns a folder
of `.nd2` microscopy files into a PowerPoint deck. For each sample it
converts every Z-slice to a composite MIP TIFF, then builds one slide showing
Z1–Z3 side by side, plus (if any images have a zoom-level suffix) a second
slide with all zoomed images side by side, each captioned with its own zoom
level.

## What it does, step by step

1. Scans `cfg$input_dir` for `.nd2` files (flat folder, not recursive).
2. Excludes any file matching `cfg$exclude_pattern` (default: single-image
   `_S<n>` files with no Z-stack — these can't be MIP'd).
3. Parses each remaining filename against `cfg$filename_pattern` to extract
   the sample ID, Z position, and zoom level (if present).
4. Runs [`nd2_composite.py`](./README_nd2_composite.md) on each file to
   produce a composite MIP TIFF (skips files already converted, unless
   `cfg$force_reconvert` is `TRUE`).
5. Converts each TIFF to PNG (PowerPoint can't reliably embed 16-bit TIFF).
6. Builds the `.pptx` directly with `python-pptx`, one slide per sample
   (no-zoom set) and one slide per sample's zoomed set.

## Requirements

- **R** with: `reticulate`, `magick`, `stringr`, `purrr`, `dplyr`, `tidyr`,
  `glue`, `here` — the setup chunk installs any that are missing.
- **Python**, provisioned automatically by `reticulate::py_require()`. No
  manual venv/conda setup needed. If your `reticulate` version predates
  `py_require()`'s automatic environment provisioning, the doc falls back
  to `pip install`-ing directly into whatever interpreter `reticulate`
  resolves.
- [`nd2_composite.py`](./README_nd2_composite.md), referenced via
  `cfg$py_script`.

## Running it

Open the `.qmd` in RStudio and Render (`Ctrl+Shift+K`), or:

```r
quarto::quarto_render("Microscopy_Imaging_Presentation.qmd")
```

The rendered `.html` is just a run log. The deliverable is the `.pptx` file
written to `cfg$pptx_path`.

## Configuration (`cfg`, top of the document)

| Field | Purpose |
|---|---|
| `input_dir` | Folder of `.nd2` files to process |
| `output_dir` | Where composite TIFFs + PNGs are written (`tiff/`, `png/` subfolders) |
| `py_script` | Path to `nd2_composite.py` |
| `filename_pattern` | Regex (named capture groups) used to parse each filename — see below |
| `exclude_pattern` | Filenames matching this are skipped before parsing (default: `_S<n>` single-image files). Set to `NULL` to disable |
| `py_extra_args` | Extra CLI flags passed to every `nd2_composite.py` call (e.g. `--scale-bar`, `--lut-min`/`--lut-max`) |
| `py_suffix` | Must match the `--suffix` value inside `py_extra_args` |
| `py_packages` | Python packages required (`nd2`, `tifffile`, `numpy`, `tqdm`, `Pillow`, `python-pptx`) |
| `slide_image_width_in` | Width of each image on a slide, in inches |
| `pptx_path` | Output `.pptx` file path |
| `slide_width_in` / `slide_height_in` | Slide canvas size (default: 13.333" × 7.5", widescreen) |
| `force_reconvert` | `TRUE` re-runs `nd2_composite.py` / PNG conversion even if output already exists (needed after changing LUT/contrast settings) |

### Filename pattern

Default format: `date_Study_Type_Batch_Sample_Zinfo`, e.g.

```
20260213_ZDNA_Optimisations_OP2_BiofilmNo1_Z1
20260213_ZDNA_Optimisations_OP2_BiofilmNo1_Z1x40
20260213_ZDNA_Optimisations_OP2_BiofilmAllH        (no Z/zoom info)
```

- `biofilmNo` captures whatever sample label sits in that position — it
  doesn't require the literal word "Biofilm". It only needs to be unique
  per sample.
- The trailing `_Z<n>` / `_Z<n>x<zoom>` segment is optional; files with no
  Z/zoom info still parse.
- Required named groups: `biofilmNo`, `z`, `zoom` (`z`/`zoom` may come back
  `NA`).
- **Capture group names must be alphanumeric only — no underscores.** This
  is an ICU regex requirement (`stringr`/`stringi`), not a choice; a group
  named `biofilm_no` will fail with `Invalid capture group name`.

Edit `filename_pattern` if your naming convention changes — the rest of the
document only refers to these group names, not their position.

## Slide grouping logic

For each unique sample (`biofilmNo`):

- **No-zoom slide**: all images with no zoom suffix, ordered by Z,
  side by side. Skipped if there are none.
- **Zoomed slide**: all images *with* a zoom suffix, ordered by Z, side by
  side, each captioned with its own zoom level underneath. Zoom values
  don't need to match across Z positions on the same slide (e.g. Z1/Z2 at
  x2.5 next to Z3 at x3.5 render fine, each with its own caption) — this
  pipeline doesn't attempt to reconcile mismatched zoom levels, only
  labels them.

## Why python-pptx instead of Quarto's pptx renderer

Earlier versions of this pipeline emitted Markdown (`![]()` images, tables)
for Quarto/pandoc to convert to `.pptx`. In testing, pandoc's pptx writer:

- only kept the **first** image when multiple `![]()` tags were placed on
  one line, dropping the rest silently (no side-by-side layout).
- **cannot embed images inside table cells at all** — used for
  per-image captions — silently dropping the images and keeping only the
  caption text.

Both failure modes are silent (no error, no warning), so the deck can look
fine in the render log and only reveal the problem when opened. To avoid
this, slide generation now calls `python-pptx` directly (via
`reticulate::py_run_string()`) with explicit inch-based positioning for
every image and caption.

## Troubleshooting

- **`ModuleNotFoundError` for a Python package** — the doc auto-installs
  missing packages into the resolved interpreter, but if this happens
  during `nd2_composite.py`'s own run (not the doc's Python setup chunk),
  install manually: see [nd2_composite.py's README](./README_nd2_composite.md#requirements).
- **A file silently doesn't appear in the deck** — check the render log for
  "did not match filename_pattern" or "excluded by exclude_pattern"
  warnings; both are logged, not silent failures.
- **`Invalid capture group name` error** — a custom `filename_pattern` used
  an underscore in a group name. Use camelCase instead (e.g. `biofilmNo`,
  not `biofilm_no`).

## Related

- [`nd2_composite.py`](./README_nd2_composite.md) — the standalone
  ND2→TIFF conversion tool this pipeline calls.
