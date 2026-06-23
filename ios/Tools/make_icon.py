#!/usr/bin/env python3
"""Generate the Tesla Dash app icon: a chrome Tesla "T" emblem with a red
electric glow on a dark radial-gradient background.

Renders at high supersample then downsamples for crisp edges. Outputs:
  - TeslaDash/Resources/Assets.xcassets/AppIcon.appiconset/icon-1024.png (opaque)
  - TeslaDash/Resources/Assets.xcassets/Emblem.imageset/emblem.png (transparent, in-app)
"""
from __future__ import annotations

import math
import os

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

S = 4               # supersample factor
BASE = 1024
N = BASE * S        # working resolution
CX = N / 2

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.join(HERE, "..", "TeslaDash", "Resources", "Assets.xcassets")


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(len(a)))


def quad_bezier(p0, p1, p2, steps):
    pts = []
    for i in range(steps + 1):
        t = i / steps
        mt = 1 - t
        x = mt * mt * p0[0] + 2 * mt * t * p1[0] + t * t * p2[0]
        y = mt * mt * p0[1] + 2 * mt * t * p1[1] + t * t * p2[1]
        pts.append((x, y))
    return pts


def radial_background():
    """Dark charcoal -> black radial gradient with a warm red glow behind the
    emblem. Returns an opaque RGB image at NxN."""
    yy, xx = np.mgrid[0:N, 0:N].astype(np.float32)
    cx = cy = N / 2.0
    r = np.sqrt((xx - cx) ** 2 + (yy - cy) ** 2)
    rmax = math.sqrt(2) * N / 2.0
    tr = np.clip(r / rmax, 0, 1)

    # Base vertical sheen: slightly lighter at top.
    top = np.array([26, 28, 34], np.float32)
    bot = np.array([8, 9, 12], np.float32)
    ty = (yy / N)[..., None]
    base = top * (1 - ty) + bot * ty

    # Radial darkening toward the corners (vignette).
    vig = (1.0 - 0.55 * tr)[..., None]
    base = base * vig

    # Red electric glow centered, gaussian falloff.
    glow_sigma = N * 0.28
    glow = np.exp(-(r ** 2) / (2 * glow_sigma ** 2))[..., None]
    red = np.array([229, 26, 34], np.float32)
    base = base + red * glow * 0.50

    arr = np.clip(base, 0, 255).astype(np.uint8)
    return Image.fromarray(arr, "RGB")


def emblem_mask():
    """White-on-black L mask of the Tesla 'T' emblem at NxN."""
    m = Image.new("L", (N, N), 0)
    d = ImageDraw.Draw(m)

    # All coordinates in 1024-space, centered, then scaled by S.
    # Vertical shift so the glyph sits visually centered.
    dy = 6

    def P(pts):
        return [((x) * S, (y + dy) * S) for (x, y) in pts]

    # --- Crossbar (wide wings, gentle droop): smooth bezier edges. ---
    top_edge = quad_bezier((262, 408), (512, 372), (762, 408), 56)
    bot_edge = quad_bezier((772, 446), (512, 410), (252, 446), 56)
    bar = top_edge + bot_edge
    d.polygon(P(bar), fill=255)

    # --- Top nub: a broad short peak sitting on the bar center. ---
    nub = [(512, 332), (548, 404), (476, 404)]
    d.polygon(P(nub), fill=255)

    # --- Stem: a short, sturdy tapering blade below the bar. ---
    stem = [(478, 404), (546, 404), (528, 678), (496, 678)]
    d.polygon(P(stem), fill=255)

    # Gently round the bottom corners of the stem (small cap, not a ball).
    d.ellipse(P([(496, 668), (528, 690)]), fill=255)

    return m


def chrome_fill():
    """Vertical chrome gradient image (RGB) at NxN for the emblem face."""
    yy = np.linspace(0, 1, N, dtype=np.float32)[:, None]
    # Chrome ramp: bright highlight near top, mid steel, soft sheen lower.
    top = np.array([250, 251, 255], np.float32)
    mid = np.array([196, 202, 214], np.float32)
    low = np.array([150, 157, 170], np.float32)
    # Two-stop blend.
    g = np.where(yy < 0.5,
                 top * (1 - yy * 2) + mid * (yy * 2),
                 mid * (1 - (yy - 0.5) * 2) + low * ((yy - 0.5) * 2))
    arr = np.repeat(g[:, None, :], N, axis=1)
    return Image.fromarray(np.clip(arr, 0, 255).astype(np.uint8), "RGB")


def build_emblem_layer():
    """Return (rgba emblem with red rim glow) at NxN, transparent background."""
    mask = emblem_mask()

    # Red rim glow: blur the mask, tint red, place beneath the chrome face.
    glow_mask = mask.filter(ImageFilter.GaussianBlur(N * 0.012))
    glow = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    red_layer = Image.new("RGBA", (N, N), (255, 38, 46, 255))
    glow = Image.composite(red_layer, glow, glow_mask)
    # Strengthen with a wider, softer halo.
    halo_mask = mask.filter(ImageFilter.GaussianBlur(N * 0.03))
    halo = Image.composite(Image.new("RGBA", (N, N), (255, 30, 38, 180)),
                           Image.new("RGBA", (N, N), (0, 0, 0, 0)), halo_mask)

    # Chrome face clipped to the crisp mask.
    chrome = chrome_fill().convert("RGBA")
    face = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    face = Image.composite(chrome, face, mask)

    # Top highlight streak across the upper third for a polished look.
    hl = Image.new("L", (N, N), 0)
    hd = ImageDraw.Draw(hl)
    hd.ellipse([N * 0.30, N * 0.20, N * 0.70, N * 0.40], fill=70)
    hl = hl.filter(ImageFilter.GaussianBlur(N * 0.02))
    hl = Image.composite(hl, Image.new("L", (N, N), 0), mask)
    white = Image.new("RGBA", (N, N), (255, 255, 255, 255))
    face = Image.composite(white, face, hl)

    out = Image.new("RGBA", (N, N), (0, 0, 0, 0))
    out = Image.alpha_composite(out, halo)
    out = Image.alpha_composite(out, glow)
    out = Image.alpha_composite(out, face)
    return out


def main():
    bg = radial_background().convert("RGBA")
    emblem = build_emblem_layer()

    # Scale emblem down a touch so it breathes within the icon.
    scale = 0.92
    ew = int(N * scale)
    em = emblem.resize((ew, ew), Image.LANCZOS)
    off = (N - ew) // 2
    canvas = bg.copy()
    canvas.alpha_composite(em, (off, off))

    icon = canvas.convert("RGB").resize((BASE, BASE), Image.LANCZOS)

    appicon_dir = os.path.join(ASSETS, "AppIcon.appiconset")
    os.makedirs(appicon_dir, exist_ok=True)
    icon.save(os.path.join(appicon_dir, "icon-1024.png"), "PNG")

    # Transparent emblem for in-app branding.
    emb = emblem.resize((512, 512), Image.LANCZOS)
    imageset_dir = os.path.join(ASSETS, "Emblem.imageset")
    os.makedirs(imageset_dir, exist_ok=True)
    emb.save(os.path.join(imageset_dir, "emblem.png"), "PNG")

    print("Wrote", os.path.join(appicon_dir, "icon-1024.png"))
    print("Wrote", os.path.join(imageset_dir, "emblem.png"))


if __name__ == "__main__":
    main()
