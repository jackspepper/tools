# nd2_composite.py

Converts Nikon `.nd2` microscopy files into 16-bit composite TIFFs. Recursively
scans a folder, applies a maximum-intensity projection (MIP) to any Z-stack,
blends fluorescent channels into a single RGB composite using their native
channel colors, and optionally overlays a scale bar and/or channel labels.

## Requirements

```
pip install nd2 tifffile numpy tqdm Pillow
```

`Pillow` is only required for `--scale-bar` and `--channel-labels`.

## Basic usage

```bash
python nd2_composite.py /path/to/folder
```

Processes every `.nd2` file under the folder (recursive), writing
`<name>_comp.tiff` next to each source file.

```bash
python nd2_composite.py /path/to/folder --output /path/to/results
```

Writes all composites into one output folder instead of alongside the
sources. Files from different subfolders get the parent folder name
prefixed to avoid collisions.

```bash
python nd2_composite.py /path/to/folder --dry-run
```

Preview what would happen without writing anything.

## Common options

| Flag | Purpose |
|---|---|
| `--output`, `-o` | Output directory (default: next to each source file) |
| `--dry-run` | Preview without writing files |
| `--suffix` | Output filename suffix (default: `_comp`) |
| `--folder-pattern`, `-f` | Only process files whose parent folder matches a glob/regex (repeatable, OR logic) |
| `--include-td` | Blend brightfield/TD channel in as a grey overlay |
| `--td-opacity` | Opacity of the TD overlay, 0–1 (default: `0.3`) |
| `--split` | Also save each channel as a separate greyscale TIFF |
| `--scale-bar` | Burn a physical scale bar onto the image |
| `--scale-bar-size` | Bar length in µm (default: auto-picked) |
| `--scale-bar-position` | `bottom-right` \| `bottom-left` \| `top-right` \| `top-left` |
| `--channel-labels` | Overlay each channel's name in its channel color |
| `--label-position` | `top-left` \| `top-right` \| `bottom-left` \| `bottom-right` |

## Contrast / LUT control

By default each channel is contrast-stretched using percentiles of its own
pixel values (`--low 0 --high 100`, i.e. full range). For consistent
brightness/contrast across a batch of images, set an absolute LUT instead:

```bash
# Fix black/white points for every channel in every file
python nd2_composite.py /data --lut-min 200 --lut-max 4000

# Fix only specific channels; others still use percentile auto-stretch
python nd2_composite.py /data --lut-ch "DAPI:200:3000" --lut-ch "GFP:*:2500"
```

`*` in a `--lut-ch` bound means "use the global/percentile default for that
end" — e.g. `"mCherry:150:*"` fixes only the black point.

## Examples

```bash
# Only process folders starting with "JSP", burn scale bars + channel labels
python nd2_composite.py /data -f "JSP*" --scale-bar --channel-labels

# Save each channel separately as well as the composite
python nd2_composite.py /data --split

# Custom output suffix
python nd2_composite.py /data --suffix _MIP   # -> myfile_MIP.tiff
```

Each run writes a timestamped log file (`nd2_composite_<timestamp>.log`)
next to the output.

## Notes

- Brightfield/TD channels are auto-detected by name (`td`, `brightfield`,
  `bf`, `dic`, `phase`, `transmission`) or ND2 modality metadata, and are
  excluded from the composite by default — use `--include-td` to blend
  them in as a grey overlay instead.
- If a file has no fluorescent channels (brightfield only), it's skipped
  with a warning.
- On re-running against existing output, you'll be prompted per-file to
  overwrite/skip (or choose "all"/"none" to apply to the rest of the run).

## Used by

This script is called by the [Microscopy Imaging Presentation](./README_Microscopy_Imaging_Presentation.md)
Quarto pipeline, which converts a folder of `.nd2` files and assembles the
results into a PowerPoint deck. It's a general-purpose tool otherwise — no
dependency on that project.
