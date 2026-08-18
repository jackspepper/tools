#!/usr/bin/env python3
"""
nd2_composite.py
----------------
Reads ND2 microscopy images recursively and creates a 16-bit composite TIFF.

New flags:
  --include-td          Blend TD/brightfield as a grey overlay
  --td-opacity          Opacity for TD overlay (default: 0.3)
  --split               Save each channel as a separate greyscale TIFF
  --scale-bar           Burn a physical scale bar onto the composite
  --scale-bar-size      Bar length in µm (default: auto)
  --scale-bar-position  bottom-right | bottom-left | top-right | top-left
  --scale-bar-color     white | black
  --channel-labels      Overlay channel names in their channel colour
  --label-position      top-left | top-right | bottom-left | bottom-right
  --folder-pattern/-f   Glob or regex pattern(s) to filter folder names
  --suffix              Output filename addition (default: _comp)
  --lut-min             Global absolute LUT minimum (raw counts, 0-65535)
  --lut-max             Global absolute LUT maximum (raw counts, 0-65535)
  --lut-ch              Per-channel absolute LUT: "NAME:min:max" (repeatable)

Usage:
  python nd2_composite.py .
  python nd2_composite.py /data --output /results --scale-bar --channel-labels
  python nd2_composite.py /data --split --include-td --td-opacity 0.2
  python nd2_composite.py /data --dry-run
  python nd2_composite.py /data -f "JSP*"                  # glob: only JSP… folders
  python nd2_composite.py /data -f "JSP*" -f "ABC*"        # multiple patterns (OR)
  python nd2_composite.py /data -f "^JSP[0-9]+"            # regex pattern
  python nd2_composite.py /data --suffix _MIP               # save as *_MIP.tiff
  python nd2_composite.py /data --lut-min 100 --lut-max 4000          # global abs LUT
  python nd2_composite.py /data --lut-ch "DAPI:200:3000" --lut-ch "GFP:100:2000"

Dependencies:
  pip install nd2 tifffile numpy tqdm Pillow
  (Pillow only required for --scale-bar and --channel-labels)
"""

import argparse
import logging
import re
import sys
from datetime import datetime
from pathlib import Path

import numpy as np

try:
    import nd2
except ImportError:
    sys.exit("Missing dependency: install with  pip install nd2")

try:
    import tifffile
except ImportError:
    sys.exit("Missing dependency: install with  pip install tifffile")

try:
    from tqdm import tqdm
except ImportError:
    sys.exit("Missing dependency: install with  pip install tqdm")

try:
    from PIL import Image, ImageDraw, ImageFont
    PIL_AVAILABLE = True
except ImportError:
    PIL_AVAILABLE = False


# ── Constants ─────────────────────────────────────────────────────────────────

BRIGHTFIELD_KEYWORDS = ("td", "brightfield", "bf", "dic", "phase", "transmission")
UINT16_MAX = np.iinfo(np.uint16).max


# ── Channel helpers ───────────────────────────────────────────────────────────

def is_brightfield(channel_name, modality_flags=None):
    if modality_flags:
        flags_lower = [f.lower() for f in modality_flags]
        if "brightfield" in flags_lower or "transmitdetector" in flags_lower:
            return True
    return any(kw in channel_name.lower().strip() for kw in BRIGHTFIELD_KEYWORDS)


def extract_rgb_from_color(color_obj):
    if hasattr(color_obj, "r") and hasattr(color_obj, "g") and hasattr(color_obj, "b"):
        return color_obj.r / 255.0, color_obj.g / 255.0, color_obj.b / 255.0
    if isinstance(color_obj, int):
        return (
            (color_obj & 0x0000FF) / 255.0,
            ((color_obj & 0x00FF00) >> 8) / 255.0,
            ((color_obj & 0xFF0000) >> 16) / 255.0,
        )
    return 1.0, 1.0, 1.0


def _fallback_color(index, total):
    import colorsys
    return colorsys.hsv_to_rgb(index / max(total, 1), 1.0, 1.0)


def _nice_scale_bar_um(target_um):
    """Return a human-readable scale bar length close to target_um."""
    for v in [0.5, 1, 2, 5, 10, 20, 25, 50, 100, 200, 250, 500, 1000, 2000]:
        if v >= target_um * 0.4:
            return float(v)
    return 1000.0


def _load_font(size):
    """Try to load a TrueType font; fall back to PIL default."""
    candidates = [
        "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf",
        "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf",
        "/usr/share/fonts/truetype/liberation/LiberationSans-Regular.ttf",
        "/System/Library/Fonts/Helvetica.ttc",
        "/Library/Fonts/Arial.ttf",
        "C:/Windows/Fonts/arial.ttf",
        "C:/Windows/Fonts/Arial.ttf",
    ]
    from PIL import ImageFont
    for p in candidates:
        try:
            return ImageFont.truetype(p, size=size)
        except Exception:
            continue
    return ImageFont.load_default()


# ── Array helpers ─────────────────────────────────────────────────────────────

def mip(array, z_axis):
    return array.max(axis=z_axis)


def percentile_stretch(plane, low_pct, high_pct):
    p_low = float(np.percentile(plane, low_pct))
    p_high = float(np.percentile(plane, high_pct))
    if p_high == p_low:
        return np.zeros_like(plane, dtype=np.float64)
    return np.clip((plane.astype(np.float64) - p_low) / (p_high - p_low), 0.0, 1.0)


def lut_stretch(plane, low_pct, high_pct, lut_min=None, lut_max=None):
    """Normalise *plane* to [0, 1].

    If *lut_min* and/or *lut_max* are given (absolute raw counts) they take
    precedence over the corresponding percentile boundary.  Either can be
    supplied alone (e.g. fix only the black point, auto the white point).
    """
    if lut_min is not None:
        p_low = float(lut_min)
    else:
        p_low = float(np.percentile(plane, low_pct))

    if lut_max is not None:
        p_high = float(lut_max)
    else:
        p_high = float(np.percentile(plane, high_pct))

    if p_high == p_low:
        return np.zeros_like(plane, dtype=np.float64)
    return np.clip((plane.astype(np.float64) - p_low) / (p_high - p_low), 0.0, 1.0)


# ── Overlay helpers (PIL) ─────────────────────────────────────────────────────

def _text_size(font, text):
    if hasattr(font, "getbbox"):
        bb = font.getbbox(text)
        return bb[2] - bb[0], bb[3] - bb[1]
    if hasattr(font, "getsize"):
        return font.getsize(text)
    return len(text) * 8, 14


def _draw_channel_labels(draw, font, channels_meta, fluorescent_idx, position, w, h, margin):
    is_top = "top" in position
    is_right = "right" in position
    labels = [(channels_meta[i]["name"], channels_meta[i]["rgb"]) for i in fluorescent_idx]
    if not is_top:
        labels = labels[::-1]
    y = margin if is_top else (h - margin)
    dy = 1 if is_top else -1
    for name, (r, g, b) in labels:
        tw, th = _text_size(font, name)
        x = (w - margin - tw) if is_right else margin
        draw.text((x + 1, y + 1), name, fill=(0, 0, 0, 180), font=font)
        draw.text((x, y), name, fill=(int(r * 255), int(g * 255), int(b * 255), 230), font=font)
        y += dy * (th + 4)


def _draw_scale_bar(draw, font, pixel_size_um, bar_um, position, color_name, w, h, margin):
    if bar_um is None or bar_um <= 0:
        bar_um = _nice_scale_bar_um((w / 5) * pixel_size_um)
    bar_px = max(2, int(round(bar_um / pixel_size_um)))
    bar_h = max(4, h // 150)
    fg = (255, 255, 255, 255) if color_name == "white" else (0, 0, 0, 255)
    sh = (0, 0, 0, 180)       if color_name == "white" else (255, 255, 255, 180)
    x1 = (w - margin - bar_px) if "right" in position else margin
    x2 = x1 + bar_px
    y2 = (h - margin)          if "bottom" in position else (margin + bar_h)
    y1 = y2 - bar_h
    draw.rectangle([x1, y1, x2, y2], fill=fg)
    label = f"{int(bar_um)} um" if bar_um == int(bar_um) else f"{bar_um} um"
    tw, th = _text_size(font, label)
    tx = x1 + (bar_px - tw) // 2
    label_y = (y2 + 3) if "bottom" in position else (y1 - th - 3)
    draw.text((tx + 1, label_y + 1), label, fill=sh, font=font)
    draw.text((tx, label_y), label, fill=fg, font=font)


def draw_overlays(composite_float, pixel_size_um, channels_meta, fluorescent_idx, args):
    """Alpha-composite a scale bar and/or channel labels onto the float image."""
    if not PIL_AVAILABLE:
        logging.getLogger("nd2_composite").warning(
            "Pillow not installed — overlays skipped.  pip install Pillow"
        )
        return composite_float
    h, w = composite_float.shape[:2]
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    draw = ImageDraw.Draw(overlay)
    font_size = max(14, min(w, h) // 45)
    font = _load_font(font_size)
    margin = max(15, min(w, h) // 50)
    if getattr(args, "channel_labels", False):
        _draw_channel_labels(draw, font, channels_meta, fluorescent_idx,
                             args.label_position, w, h, margin)
    if getattr(args, "scale_bar", False) and pixel_size_um and pixel_size_um > 0:
        _draw_scale_bar(draw, font, pixel_size_um,
                        getattr(args, "scale_bar_size", None),
                        args.scale_bar_position, args.scale_bar_color,
                        w, h, margin)
    overlay_np = np.array(overlay).astype(np.float64) / 255.0
    alpha = overlay_np[..., 3:4]
    rgb   = overlay_np[..., :3]
    return np.clip(composite_float * (1.0 - alpha) + rgb * alpha, 0.0, 1.0)


# ── Folder pattern filtering ──────────────────────────────────────────────────

def _folder_matches(nd2_path: Path, root_input: Path, patterns: list) -> bool:
    """Return True if any ancestor folder (relative to root_input) matches any pattern.

    Each pattern is tried first as a glob (fnmatch) against every path part,
    then as a full regex match against every path part.  A file sitting directly
    inside root_input (no sub-folder) is matched only when patterns is empty.
    """
    import fnmatch
    rel_parts = nd2_path.relative_to(root_input).parts[:-1]  # exclude filename
    if not patterns:
        return True
    if not rel_parts:
        # File is directly in root — check whether any pattern matches "."
        return any(
            fnmatch.fnmatch(".", p) or re.fullmatch(p, ".", re.IGNORECASE)
            for p in patterns
        )
    for part in rel_parts:
        for pattern in patterns:
            try:
                if fnmatch.fnmatch(part, pattern):
                    return True
                if re.fullmatch(pattern, part, re.IGNORECASE):
                    return True
            except re.error:
                # Invalid regex — treat as glob only (already tried above)
                pass
    return False


# ── Output path ───────────────────────────────────────────────────────────────

def build_output_path(nd2_path, root_input, output_dir, suffix="_comp"):
    stem   = nd2_path.stem
    parent = nd2_path.parent
    if output_dir is None:
        return parent / f"{stem}{suffix}.tiff"
    if parent.resolve() == root_input.resolve():
        filename = f"{stem}{suffix}.tiff"
    else:
        filename = f"{parent.name}_{stem}{suffix}.tiff"
    return output_dir / filename


# ── Overwrite policy ──────────────────────────────────────────────────────────

class OverwritePolicy:
    def __init__(self):
        self._overwrite_all = False
        self._skip_all      = False

    def should_write(self, path):
        if not path.exists():       return True
        if self._overwrite_all:     return True
        if self._skip_all:          return False
        while True:
            choice = input(
                f"\n  File already exists: {path.name}\n"
                "  [o] Overwrite  [s] Skip  [a] Overwrite all  [n] Skip all  [q] Quit: "
            ).strip().lower()
            if choice == "o": return True
            if choice == "s": return False
            if choice == "a": self._overwrite_all = True;  return True
            if choice == "n": self._skip_all      = True;  return False
            if choice == "q": print("Aborted."); sys.exit(0)
            print("  Please enter o, s, a, n, or q.")


# ── Split channel helper ──────────────────────────────────────────────────────

def save_split_channels(data, channels_meta, fluorescent_idx, td_idx,
                        out_path, dry_run, logger, suffix="_comp"):
    """Save each channel as a 16-bit greyscale TIFF next to the composite."""
    stem    = out_path.stem
    if stem.endswith(suffix):
        stem = stem[: -len(suffix)]
    out_dir = out_path.parent
    for i in fluorescent_idx + td_idx:
        plane_u16 = np.clip(data[i], 0, UINT16_MAX).astype(np.uint16)
        safe      = re.sub(r"[^\w\-]", "_", channels_meta[i]["name"])
        ch_path   = out_dir / f"{stem}_{safe}.tiff"
        if not dry_run:
            tifffile.imwrite(ch_path, plane_u16,
                             photometric="minisblack", compression="deflate")
        logger.info(f"    {'DRY-RUN ' if dry_run else ''}split -> {ch_path.name}")


# ── LUT helpers ───────────────────────────────────────────────────────────────

def parse_lut_ch(lut_ch_list):
    """Parse a list of 'NAME:min:max' strings into a dict keyed by lower-case name.

    Each field can be '*' or '' to mean "use global/percentile default":
      'DAPI:200:4000'   → fix both black and white point
      'GFP:*:3000'      → auto black point, fixed white point
      'mCherry:150:*'   → fixed black point, auto white point
    """
    result = {}
    for spec in (lut_ch_list or []):
        parts = spec.split(":")
        if len(parts) != 3:
            raise argparse.ArgumentTypeError(
                f"--lut-ch '{spec}' must be in NAME:min:max format "
                f"(use * to keep the global/percentile default for that end)."
            )
        name, lo, hi = parts
        name = name.strip()
        if not name:
            raise argparse.ArgumentTypeError(f"--lut-ch '{spec}': channel name is empty.")

        def _parse_bound(s, field, spec):
            s = s.strip()
            if s in ("", "*"):
                return None
            try:
                v = float(s)
            except ValueError:
                raise argparse.ArgumentTypeError(
                    f"--lut-ch '{spec}': {field} value '{s}' is not a number or '*'."
                )
            if v < 0:
                raise argparse.ArgumentTypeError(
                    f"--lut-ch '{spec}': {field} value must be >= 0."
                )
            return v

        result[name.lower()] = (
            _parse_bound(lo, "min", spec),
            _parse_bound(hi, "max", spec),
        )
    return result


def resolve_channel_lut(channel_name, lut_ch_map, global_min, global_max):
    """Return (lut_min, lut_max) for *channel_name*, merging per-channel and global."""
    ch_lo, ch_hi = lut_ch_map.get(channel_name.lower(), (None, None))
    lo = ch_lo if ch_lo is not None else global_min
    hi = ch_hi if ch_hi is not None else global_max
    return lo, hi




def process_nd2(input_path, out_path, low_pct, high_pct, dry_run, logger, args):
    result = {"file": str(input_path), "status": "ok", "note": ""}

    with nd2.ND2File(input_path) as f:
        axes       = f.sizes
        n_channels = axes.get("C", 1)

        # ── Parse channel metadata ────────────────────────────────────
        channels_meta  = []
        pixel_size_um  = None
        try:
            for ch in (f.metadata.channels or []):
                name = ch.channel.name
                rgb  = extract_rgb_from_color(ch.channel.color)
                try:
                    flags = list(ch.microscope.modalityFlags or [])
                except Exception:
                    flags = []
                channels_meta.append({"name": name, "rgb": rgb, "flags": flags})
            if f.metadata.channels:
                cal = f.metadata.channels[0].volume.axesCalibration
                if cal and len(cal) >= 1 and float(cal[0]) > 0:
                    pixel_size_um = float(cal[0])
        except Exception:
            pass

        while len(channels_meta) < n_channels:
            i = len(channels_meta)
            channels_meta.append({
                "name": f"Ch{i+1}",
                "rgb":  _fallback_color(i, n_channels),
                "flags": [],
            })

        has_z = "Z" in axes and axes["Z"] > 1
        logger.info(f"  Axes    : {dict(axes)}")
        logger.info(f"  Channels: {[c['name'] for c in channels_meta]}")
        if pixel_size_um:
            logger.info(f"  Px size : {pixel_size_um:.4f} um/px")

        data = f.asarray().astype(np.float64)

    # ── Squeeze trivial axes ──────────────────────────────────────────
    axis_names   = list(axes.keys())
    keep         = {"C", "Y", "X"}
    if has_z:
        keep.add("Z")
    squeeze_axes = [i for i, (n, s) in enumerate(axes.items()) if s == 1 and n not in keep]
    data         = np.squeeze(data, axis=tuple(squeeze_axes))
    axis_names   = [n for n, s in axes.items() if s > 1 or n in keep]

    # ── MIP ───────────────────────────────────────────────────────────
    if has_z and "Z" in axis_names:
        z_idx = axis_names.index("Z")
        data  = mip(data, z_axis=z_idx)
        axis_names.pop(z_idx)
        logger.info(f"  Z-stack : MIP applied ({axes['Z']} slices -> 1 plane)")

    if "C" not in axis_names:
        data       = data[np.newaxis, ...]
        axis_names = ["C"] + axis_names
    data = np.moveaxis(data, axis_names.index("C"), 0)
    # data: (C, H, W)

    # ── Classify channels ─────────────────────────────────────────────
    fluorescent_idx = [i for i, ch in enumerate(channels_meta)
                       if not is_brightfield(ch["name"], ch.get("flags", []))]
    td_idx          = [i for i, ch in enumerate(channels_meta)
                       if     is_brightfield(ch["name"], ch.get("flags", []))]

    td_names   = [channels_meta[i]["name"] for i in td_idx]
    kept_names = [channels_meta[i]["name"] for i in fluorescent_idx]
    if td_names:
        logger.info(f"  TD/BF   : {td_names}")
    logger.info(f"  Fluor.  : {kept_names}")

    if not fluorescent_idx:
        msg = "All channels are brightfield — skipping file."
        logger.warning(f"  WARNING : {msg}")
        result.update({"status": "skipped", "note": msg})
        return result

    # ── Build additive composite ──────────────────────────────────────
    h, w      = data.shape[1], data.shape[2]
    composite = np.zeros((h, w, 3), dtype=np.float64)

    lut_ch_map   = getattr(args, "_lut_ch_map", {})
    global_min   = getattr(args, "lut_min", None)
    global_max   = getattr(args, "lut_max", None)

    for i in fluorescent_idx:
        ch_name      = channels_meta[i]["name"]
        ch_lut_min, ch_lut_max = resolve_channel_lut(ch_name, lut_ch_map, global_min, global_max)
        norm         = lut_stretch(data[i], low_pct, high_pct, ch_lut_min, ch_lut_max)
        r, g, b      = channels_meta[i]["rgb"]
        composite[..., 0] += norm * r
        composite[..., 1] += norm * g
        composite[..., 2] += norm * b
        lut_info = (
            f"min={ch_lut_min:.0f}" if ch_lut_min is not None else f"min=p{low_pct}",
            f"max={ch_lut_max:.0f}" if ch_lut_max is not None else f"max=p{high_pct}",
        )
        logger.info(f"    + {ch_name:<20s}  color=({r:.2f},{g:.2f},{b:.2f})  "
                    f"lut=[{lut_info[0]}, {lut_info[1]}]")

    # ── Optional TD overlay ───────────────────────────────────────────
    if args.include_td and td_idx:
        for i in td_idx:
            ch_name = channels_meta[i]["name"]
            ch_lut_min, ch_lut_max = resolve_channel_lut(ch_name, lut_ch_map, global_min, global_max)
            td_norm = lut_stretch(data[i], low_pct, high_pct, ch_lut_min, ch_lut_max)
            composite[..., 0] += td_norm * args.td_opacity
            composite[..., 1] += td_norm * args.td_opacity
            composite[..., 2] += td_norm * args.td_opacity
            logger.info(f"    + {ch_name:<20s}  TD overlay @ {args.td_opacity:.2f}")

    composite = np.clip(composite, 0.0, 1.0)

    # ── PIL overlays (scale bar, channel labels) ──────────────────────
    if args.scale_bar or args.channel_labels:
        composite = draw_overlays(composite, pixel_size_um,
                                  channels_meta, fluorescent_idx, args)

    composite_u16 = (composite * UINT16_MAX).astype(np.uint16)

    # ── Save composite ────────────────────────────────────────────────
    if dry_run:
        logger.info(f"  DRY-RUN : would save -> {out_path}")
        result["note"] = "dry-run"
    else:
        out_path.parent.mkdir(parents=True, exist_ok=True)
        tifffile.imwrite(out_path, composite_u16,
                         photometric="rgb", compression="deflate")
        logger.info(f"  Saved   : {out_path}")

    # ── Split channels ────────────────────────────────────────────────
    if args.split:
        save_split_channels(data, channels_meta, fluorescent_idx, td_idx,
                            out_path, dry_run, logger, getattr(args, "suffix", "_comp"))

    return result


# ── Entry point ───────────────────────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Create 16-bit composite TIFFs from ND2 files (recursive).",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    # I/O
    parser.add_argument("input", type=Path,
                        help="ND2 file or root folder (searched recursively).")
    parser.add_argument("--output", "-o", type=Path, default=None,
                        help="Output directory. Default: next to each source file.")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview without writing any files.")
    # Contrast / LUT
    parser.add_argument("--low",  type=float, default=0,
                        help="Lower percentile for auto contrast stretch (default: 0). "
                             "Ignored for any channel where --lut-min is set.")
    parser.add_argument("--high", type=float, default=100,
                        help="Upper percentile for auto contrast stretch (default: 100). "
                             "Ignored for any channel where --lut-max is set.")
    parser.add_argument("--lut-min", type=float, default=None, metavar="VALUE",
                        help="Global absolute LUT black point (raw counts, e.g. 200). "
                             "Overrides --low for all channels. "
                             "Per-channel --lut-ch takes priority over this.")
    parser.add_argument("--lut-max", type=float, default=None, metavar="VALUE",
                        help="Global absolute LUT white point (raw counts, e.g. 4000). "
                             "Overrides --high for all channels. "
                             "Per-channel --lut-ch takes priority over this.")
    parser.add_argument("--lut-ch", metavar="NAME:min:max",
                        action="append", dest="lut_ch", default=[],
                        help="Per-channel absolute LUT. Format: 'NAME:min:max'. "
                             "Use * to keep the global/percentile default for either end. "
                             "Can be repeated. Examples: "
                             "--lut-ch 'DAPI:200:3000'  "
                             "--lut-ch 'GFP:*:2500'  "
                             "--lut-ch 'mCherry:150:*'")
    # TD overlay
    parser.add_argument("--include-td", action="store_true",
                        help="Blend TD/brightfield channel as a grey overlay.")
    parser.add_argument("--td-opacity", type=float, default=0.3,
                        help="Opacity of the TD overlay 0-1 (default: 0.3).")
    # Split channels
    parser.add_argument("--split", action="store_true",
                        help="Save each channel as a separate greyscale TIFF.")
    # Scale bar
    parser.add_argument("--scale-bar", action="store_true",
                        help="Burn a physical scale bar onto the composite.")
    parser.add_argument("--scale-bar-size", type=float, default=None,
                        help="Scale bar length in um (default: auto).")
    parser.add_argument("--scale-bar-position", default="bottom-right",
                        choices=["bottom-right", "bottom-left", "top-right", "top-left"],
                        help="Scale bar corner (default: bottom-right).")
    parser.add_argument("--scale-bar-color", default="white",
                        choices=["white", "black"],
                        help="Scale bar colour (default: white).")
    # Channel labels
    parser.add_argument("--channel-labels", action="store_true",
                        help="Overlay channel names in their channel colour.")
    parser.add_argument("--label-position", default="top-left",
                        choices=["top-left", "top-right", "bottom-left", "bottom-right"],
                        help="Channel label corner (default: top-left).")
    # Folder filtering
    parser.add_argument("--folder-pattern", "-f", metavar="PATTERN",
                        action="append", dest="folder_patterns", default=[],
                        help=(
                            "Only process ND2 files whose parent folder name matches "
                            "PATTERN (glob or regex). Can be repeated for multiple patterns "
                            "(OR logic). E.g.  -f 'JSP*'  or  -f '^JSP[0-9]+'. "
                            "Omit to process all folders."
                        ))
    # Output suffix
    parser.add_argument("--suffix", default="_comp",
                        help="String appended to the file stem before .tiff (default: _comp). "
                             "E.g. --suffix _MIP  →  myfile_MIP.tiff")

    args = parser.parse_args()

    # Parse and validate --lut-ch entries up front
    try:
        args._lut_ch_map = parse_lut_ch(args.lut_ch)
    except argparse.ArgumentTypeError as exc:
        parser.error(str(exc))

    input_path = args.input.resolve()
    output_dir = args.output.resolve() if args.output else None

    if not input_path.exists():
        sys.exit(f"Error: path does not exist: {input_path}")

    # Warn early if Pillow is missing but overlays requested
    if (args.scale_bar or args.channel_labels) and not PIL_AVAILABLE:
        print("WARNING: --scale-bar / --channel-labels require Pillow.  pip install Pillow")

    # Collect ND2 files
    if input_path.is_file():
        if input_path.suffix.lower() != ".nd2":
            sys.exit(f"Error: expected a .nd2 file, got: {input_path.name}")
        nd2_files  = [input_path]
        root_input = input_path.parent
    elif input_path.is_dir():
        nd2_files  = sorted(input_path.rglob("*.nd2"))
        if not nd2_files:
            nd2_files = sorted(input_path.rglob("*.ND2"))
        if not nd2_files:
            sys.exit(f"No .nd2 files found under: {input_path}")
        root_input = input_path
    else:
        sys.exit(f"Error: not a file or directory: {input_path}")

    # Apply folder-pattern filter
    if args.folder_patterns:
        nd2_files_filtered = [f for f in nd2_files
                              if _folder_matches(f, root_input, args.folder_patterns)]
        if not nd2_files_filtered:
            patterns_str = ", ".join(repr(p) for p in args.folder_patterns)
            sys.exit(
                f"No .nd2 files matched folder pattern(s) {patterns_str} "
                f"under: {root_input}"
            )
        nd2_files = nd2_files_filtered

    # Logging
    log_dir = (output_dir if output_dir else root_input)
    log_dir.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_path  = log_dir / f"nd2_composite_{timestamp}.log"

    logger = logging.getLogger("nd2_composite")
    logger.setLevel(logging.INFO)
    ch = logging.StreamHandler()
    ch.setFormatter(logging.Formatter("%(message)s"))
    logger.addHandler(ch)
    if not args.dry_run:
        fh = logging.FileHandler(log_path, encoding="utf-8")
        fh.setFormatter(logging.Formatter("%(asctime)s  %(message)s", "%H:%M:%S"))
        logger.addHandler(fh)

    mode = "DRY-RUN" if args.dry_run else "PROCESSING"
    logger.info("=" * 60)
    logger.info(f"  nd2_composite  [{mode}]  {timestamp}")
    logger.info(f"  Input : {root_input}")
    logger.info(f"  Output: {output_dir or '(next to source files)'}")
    if args.folder_patterns:
        logger.info(f"  Filter: {', '.join(args.folder_patterns)}")
    logger.info(f"  Suffix: {args.suffix}")
    # LUT summary
    if args.lut_min is not None or args.lut_max is not None:
        logger.info(f"  LUT   : global min={args.lut_min or 'auto'}, max={args.lut_max or 'auto'}")
    else:
        logger.info(f"  LUT   : percentile low={args.low}, high={args.high}")
    if args._lut_ch_map:
        for ch, (lo, hi) in args._lut_ch_map.items():
            logger.info(f"  LUT ch: {ch}  min={lo if lo is not None else 'auto'}, "
                        f"max={hi if hi is not None else 'auto'}")
    logger.info(f"  Files : {len(nd2_files)}")
    logger.info("=" * 60)

    policy  = OverwritePolicy()
    results = []

    for nd2_file in tqdm(nd2_files, desc="Compositing", unit="file"):
        out_path = build_output_path(nd2_file, root_input, output_dir, args.suffix)
        tqdm.write(f"\n{'-'*60}\n {nd2_file.relative_to(root_input)}")
        logger.info(f"\n{'-'*60}")
        logger.info(f"  File: {nd2_file.relative_to(root_input)}")

        if not args.dry_run and not policy.should_write(out_path):
            logger.info(f"  SKIPPED (exists): {out_path}")
            results.append({"file": str(nd2_file), "status": "skipped", "note": "exists"})
            continue

        try:
            result = process_nd2(nd2_file, out_path, args.low, args.high,
                                 args.dry_run, logger, args)
        except Exception as exc:
            tqdm.write(f"  ERROR: {exc}")
            logger.error(f"  ERROR: {exc}")
            result = {"file": str(nd2_file), "status": "error", "note": str(exc)}

        results.append(result)

    n_ok = sum(1 for r in results if r["status"] == "ok")
    n_sk = sum(1 for r in results if r["status"] == "skipped")
    n_er = sum(1 for r in results if r["status"] == "error")

    logger.info(f"\n{'='*60}")
    logger.info(f"  Done.  {n_ok} saved  |  {n_sk} skipped  |  {n_er} errors")
    if not args.dry_run:
        logger.info(f"  Log: {log_path}")
    logger.info("=" * 60)
    if n_er:
        for r in results:
            if r["status"] == "error":
                logger.info(f"    {Path(r['file']).name}: {r['note']}")


if __name__ == "__main__":
    main()
