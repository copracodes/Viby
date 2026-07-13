#!/usr/bin/env python3
"""Regenerate every Viby icon asset from the master brand tile.

    python tools/gen_icons.py          (needs: opencv-python, numpy)

The master (`assets-design/adio_logo1.jpg`) is a *pre-composed presentation
tile* — the mark sits on a charcoal rounded square, itself on a light page with
a drop shadow. It is never shipped whole. This script deconstructs it:

  1. isolate the tile (largest dark blob), sample its true charcoal,
  2. isolate the glyph (largest bright blob inside the tile),
  3. supersample the *grayscale* so the boundary is sub-pixel rather than a
     threshold staircase, contour-trace it, simplify (RDP keeps nodes where
     curvature demands them — the tapered tips — and drops them along lazy
     arcs), and fit Catmull-Rom cubics,
  4. emit the glyph as a VectorDrawable path, plus every raster it's needed in.

Fidelity is *measured*, not eyeballed: --check prints the IoU of the traced
path against the source glyph mask (last run: 0.9844; the residual is the
antialiased edge, not the trace).

Geometry that matters:
  * Adaptive icon — the 108dp viewport shows only its central 72dp, and 66dp is
    the limit content must stay inside, NOT a target. Sizing the glyph to 66
    would fill 92% of the visible icon; the master has the mark at 70.6% of the
    tile, so the glyph is scaled to that share of the 72dp visible area (~51dp),
    which clears circle / squircle / rounded-square masks with room to spare.
  * Splash (androidx core-splashscreen) reuses the adaptive foreground: with no
    icon background the splash mark must sit inside a 192dp circle on a 288dp
    canvas (2/3); at 51/108 = 47% it does.
  * Notification small-icon — Android renders it from the ALPHA only and tints
    it, so it is a flat silhouette on transparency (a filled tile would show as
    a solid blob).
  * Play Store master — full-bleed square with NO alpha; Play applies its own
    corner mask, so a pre-rounded tile would get double-rounded.
"""
import os
import sys

import cv2
import numpy as np

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SRC = os.path.join(ROOT, "assets-design", "adio_logo1.jpg")
RES = os.path.join(ROOT, "android", "app", "src", "main", "res")
DESIGN = os.path.join(ROOT, "assets-design")
BRAND = os.path.join(ROOT, "assets", "brand")

SS = 8          # supersample factor for the trace
RDP_EPS = 8.0   # simplification tolerance, in supersampled px
SAFE_ZONE = 66.0
VIEWPORT = 108.0


# --------------------------------------------------------------------------
# 1-3. extract + trace
# --------------------------------------------------------------------------
def extract():
    img = cv2.imread(SRC)
    if img is None:
        sys.exit(f"missing master art: {SRC}")
    gray = cv2.cvtColor(img, cv2.COLOR_BGR2GRAY)

    # the tile: the largest dark region on the light page
    dark = (gray < 110).astype(np.uint8)
    _, labels, stats, _ = cv2.connectedComponentsWithStats(dark, 8)
    ti = 1 + np.argmax(stats[1:, cv2.CC_STAT_AREA])
    x, y, tw, th, _ = stats[ti]
    tile_mask = (labels == ti).astype(np.uint8)[y:y + th, x:x + tw]
    tile_gray = gray[y:y + th, x:x + tw]
    tile_bgr = img[y:y + th, x:x + tw]

    # the tile's footprint (its rounded corners are page-coloured, and the glyph
    # itself isn't "dark"), so "inside the tile" is one solid blob
    solid = cv2.morphologyEx(tile_mask, cv2.MORPH_CLOSE, np.ones((61, 61), np.uint8))
    solid = cv2.dilate(solid, np.ones((5, 5), np.uint8))

    rough = ((tile_gray > 150) & (solid > 0)).astype(np.uint8)
    _, lab2, st2, _ = cv2.connectedComponentsWithStats(rough, 8)
    gi = 1 + np.argmax(st2[1:, cv2.CC_STAT_AREA])   # the glyph, not the corners
    glyph = (lab2 == gi).astype(np.uint8)

    # the tile's true colour: dark pixels well inside it, away from the glyph
    body = (cv2.erode(solid, np.ones((9, 9), np.uint8), iterations=2) > 0) & \
           (cv2.dilate(glyph, np.ones((7, 7), np.uint8)) == 0)
    bgr = np.median(tile_bgr[body], axis=0).astype(int)
    tile_hex = "#%02X%02X%02X" % (bgr[2], bgr[1], bgr[0])

    # corner radius, measured directly (an area-based estimate picks up the
    # mockup's drop shadow and comes out far too large)
    radius_frac = float(int(np.argmax(tile_mask[0] > 0)) / tw)

    gx, gy, gw, gh = cv2.boundingRect(glyph)
    glyph_frac = float(max(gw, gh) / tw)          # the mark's share of the tile

    # supersample the GRAYSCALE so the traced boundary lands on the antialiased
    # edge instead of a hard staircase
    g = np.where(glyph > 0, tile_gray, 0).astype(np.float32)
    big = cv2.resize(g, None, fx=SS, fy=SS, interpolation=cv2.INTER_CUBIC)
    hi = cv2.morphologyEx((big > 150).astype(np.uint8), cv2.MORPH_CLOSE,
                          np.ones((3, 3), np.uint8))

    contours, hierarchy = cv2.findContours(hi, cv2.RETR_CCOMP, cv2.CHAIN_APPROX_NONE)
    traced = []
    for i, c in enumerate(contours):
        if cv2.contourArea(c) < SS * SS * 4:      # speckle
            continue
        pts = c[:, 0, :].astype(np.float64)
        k = 9                                      # kill threshold/JPEG jitter
        kern = np.ones(k) / k
        xs = np.convolve(np.r_[pts[-k:, 0], pts[:, 0], pts[:k, 0]], kern, 'same')[k:-k]
        ys = np.convolve(np.r_[pts[-k:, 1], pts[:, 1], pts[:k, 1]], kern, 'same')[k:-k]
        sm = np.stack([xs, ys], 1).astype(np.float32).reshape(-1, 1, 2)
        simp = cv2.approxPolyDP(sm, RDP_EPS, True)[:, 0, :].astype(np.float64)
        traced.append((simp, hierarchy[0][i][3] != -1))   # (points, is_hole)
    return traced, tile_hex, radius_frac, glyph_frac, glyph


def _catmull_rom(pts):
    n = len(pts)
    for i in range(n):
        p0, p1 = pts[(i - 1) % n], pts[i]
        p2, p3 = pts[(i + 1) % n], pts[(i + 2) % n]
        yield p1 + (p2 - p0) / 6.0, p2 - (p3 - p1) / 6.0, p2


def fit(contours, view, content):
    """Scale the glyph so its longest side is `content`, centred in `view`."""
    allp = np.vstack([p for p, _ in contours])
    mn, mx = allp.min(0), allp.max(0)
    scale = content / (mx - mn).max()
    centre = (mn + mx) / 2.0
    return [((p - centre) * scale + view / 2, hole) for p, hole in contours]


def path_data(placed):
    def f(v):
        return f"{v:.2f}".rstrip("0").rstrip(".")
    subs = []
    for pts, _ in placed:
        segs = list(_catmull_rom(pts))
        d = [f"M{f(pts[0][0])},{f(pts[0][1])}"]
        for c1, c2, p2 in segs[:-1]:
            d.append(f"C{f(c1[0])},{f(c1[1])} {f(c2[0])},{f(c2[1])} {f(p2[0])},{f(p2[1])}")
        c1, c2, _ = segs[-1]
        d.append(f"C{f(c1[0])},{f(c1[1])} {f(c2[0])},{f(c2[1])} {f(pts[0][0])},{f(pts[0][1])}")
        subs.append(" ".join(d) + " Z")
    return " ".join(subs)


def rasterise(placed, view, size, ss=4):
    """Antialiased alpha mask of the glyph at `size` px."""
    R = size * ss
    canvas = np.zeros((R, R), np.uint8)
    for pts, hole in placed:
        poly = [pts[0]]
        for c1, c2, p2 in _catmull_rom(pts):
            p0 = poly[-1]
            t = np.linspace(0, 1, 16)[1:, None]
            poly.extend((1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * c1 +
                        3 * (1 - t) * t ** 2 * c2 + t ** 3 * p2)
        cv2.fillPoly(canvas, [(np.array(poly) / view * R).astype(np.int32)],
                     0 if hole else 255)
    return cv2.resize(canvas, (size, size), interpolation=cv2.INTER_AREA)


def check(contours, src_mask):
    """IoU of the traced path against the source glyph mask.

    Both are fitted to the same large canvas first, so this measures the trace,
    not the resolution the icon happens to be drawn at.
    """
    R, C = 1024, 940
    got = rasterise(fit(contours, float(R), float(C)), float(R), R) > 127
    ys, xs = np.nonzero(src_mask)
    mn = np.array([xs.min(), ys.min()], float)
    mx = np.array([xs.max(), ys.max()], float)
    sc = C / (mx - mn).max()
    M = np.array([[sc, 0, R / 2 - (mn[0] + mx[0]) / 2 * sc],
                  [0, sc, R / 2 - (mn[1] + mx[1]) / 2 * sc]], np.float32)
    ref = cv2.warpAffine(src_mask * 255, M, (R, R), flags=cv2.INTER_CUBIC) > 127
    return (ref & got).sum() / (ref | got).sum()


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("  ", os.path.relpath(path, ROOT))


def main():
    contours, tile_hex, radius_frac, glyph_frac, src_mask = extract()
    bg_bgr = tuple(int(tile_hex[i:i + 2], 16) for i in (5, 3, 1))
    print(f"master: tile {tile_hex}  corner r={radius_frac:.3f}  "
          f"mark={glyph_frac:.3f} of tile")

    # --- adaptive foreground + themed (monochrome) layer --------------------
    content = round(glyph_frac * 72.0, 1)          # the master's proportion
    assert content <= SAFE_ZONE, "glyph would breach the adaptive safe zone"
    placed = fit(contours, VIEWPORT, content)
    d = path_data(placed)
    print(f"adaptive: glyph {content}dp of the 72dp visible area "
          f"(safe-zone limit {SAFE_ZONE:.0f}dp), path {len(d)} chars")
    if "--check" in sys.argv:
        print(f"trace fidelity: IoU={check(contours, src_mask):.4f}")

    header = ("<?xml version=\"1.0\" encoding=\"utf-8\"?>\n"
              "<!-- GENERATED by tools/gen_icons.py from "
              "assets-design/adio_logo1.jpg — do not hand-edit. -->\n")
    vector = ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
              '    android:width="{w}dp"\n'
              '    android:height="{w}dp"\n'
              '    android:viewportWidth="{w}"\n'
              '    android:viewportHeight="{w}"{extra}>\n'
              '    <path\n'
              '        android:fillColor="#FFFFFFFF"\n'
              '        android:pathData="{d}" />\n'
              '</vector>\n')

    write(os.path.join(RES, "drawable", "ic_launcher_foreground.xml"),
          header +
          "<!-- The brand mark, inside the adaptive-icon safe zone: the 108dp\n"
          "     viewport's outer 20% is masked away by the launcher, so the mark\n"
          "     survives circle, squircle and rounded-square masks unclipped.\n"
          "     Also the splash mark (see values/styles.xml). -->\n" +
          vector.format(w=108, extra="", d=d))

    write(os.path.join(RES, "drawable", "ic_launcher_monochrome.xml"),
          header +
          "<!-- Themed-icon layer (Android 13+): the same glyph, same safe zone.\n"
          "     The system tints it from the wallpaper palette, so only the alpha\n"
          "     matters — it must stay a flat silhouette with no background. -->\n" +
          vector.format(w=108, extra="", d=d))

    # --- notification small icon (24dp, 2dp padding) ------------------------
    d24 = path_data(fit(contours, 24.0, 20.0))
    write(os.path.join(RES, "drawable", "ic_stat_viby.xml"),
          header +
          "<!-- Playback-notification small icon. Android draws small-icons from\n"
          "     the ALPHA channel only and re-tints them, so this is a flat\n"
          "     silhouette on transparency — a filled tile would render as a solid\n"
          "     blob. Referenced by AudioServiceConfig.androidNotificationIcon. -->\n" +
          vector.format(w=24, extra='\n    android:tint="#FFFFFFFF"', d=d24))

    # --- colours ------------------------------------------------------------
    write(os.path.join(RES, "values", "colors.xml"),
          '<?xml version="1.0" encoding="utf-8"?>\n<resources>\n'
          '    <!-- The brand tile\'s charcoal, sampled from the master artwork\n'
          '         (assets-design/adio_logo1.jpg) by tools/gen_icons.py. Flat — no\n'
          '         gradient — so the mark stays sharp down to 48dp, and identical in\n'
          '         light and dark so cold start never flashes white. -->\n'
          f'    <color name="ic_launcher_background">{tile_hex}</color>\n'
          f'    <color name="splash_background">{tile_hex}</color>\n'
          '</resources>\n')

    # --- legacy rasters (pre-API 26) ---------------------------------------
    def tile(size, circular, alpha):
        ss = 4
        R = size * ss
        m = np.zeros((R, R), np.uint8)
        if circular:
            cv2.circle(m, (R // 2, R // 2), R // 2, 255, -1)
        else:
            r = int(radius_frac * R)
            cv2.rectangle(m, (r, 0), (R - r, R), 255, -1)
            cv2.rectangle(m, (0, r), (R, R - r), 255, -1)
            for cx, cy in ((r, r), (R - r, r), (r, R - r), (R - r, R - r)):
                cv2.circle(m, (cx, cy), r, 255, -1)
        rgb = np.zeros((size, size, 3), np.uint8)
        rgb[:] = bg_bgr
        a = alpha.astype(np.float32) / 255.0
        rgb = (rgb * (1 - a[..., None]) + 255 * a[..., None]).astype(np.uint8)
        return np.dstack([rgb, cv2.resize(m, (size, size), interpolation=cv2.INTER_AREA)])

    for dpi, px in (("mdpi", 48), ("hdpi", 72), ("xhdpi", 96),
                    ("xxhdpi", 144), ("xxxhdpi", 192)):
        a = rasterise(fit(contours, float(px), glyph_frac * px), float(px), px)
        for name, circular in (("ic_launcher.png", False),
                               ("ic_launcher_round.png", True)):
            out = os.path.join(RES, f"mipmap-{dpi}", name)
            os.makedirs(os.path.dirname(out), exist_ok=True)
            cv2.imwrite(out, tile(px, circular, a))
        print(f"   mipmap-{dpi}/ic_launcher{{,_round}}.png ({px}px)")

    # --- Play Store master: full-bleed square, no alpha ---------------------
    a512 = rasterise(fit(contours, 512.0, glyph_frac * 512), 512.0, 512)
    store = np.zeros((512, 512, 3), np.uint8)
    store[:] = bg_bgr
    g = a512.astype(np.float32) / 255.0
    store = (store * (1 - g[..., None]) + 255 * g[..., None]).astype(np.uint8)
    os.makedirs(os.path.join(DESIGN, "store"), exist_ok=True)
    cv2.imwrite(os.path.join(DESIGN, "store", "play_icon_512.png"), store)
    cv2.imwrite(os.path.join(DESIGN, "store", "tile_preview_512.png"),
                tile(512, False, a512))
    print("   assets-design/store/play_icon_512.png (+ masked preview)")

    # --- in-app mark (Flutter asset: white glyph on transparency) -----------
    for scale, folder in ((1, ""), (2, "2.0x"), (3, "3.0x")):
        px = 96 * scale
        a = rasterise(fit(contours, float(px), px * 0.92), float(px), px)
        out = os.path.join(BRAND, folder, "viby_mark.png")
        os.makedirs(os.path.dirname(out), exist_ok=True)
        cv2.imwrite(out, np.dstack([np.full((px, px, 3), 255, np.uint8), a]))
    print("   assets/brand/viby_mark.png (+ 2.0x, 3.0x)")

    # --- design master ------------------------------------------------------
    write(os.path.join(DESIGN, "ic_launcher_master.svg"),
          '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 108 108" '
          'width="108" height="108">\n'
          '  <!-- Viby brand mark, traced from adio_logo1.jpg by '
          'tools/gen_icons.py. -->\n'
          f'  <rect width="108" height="108" rx="{radius_frac * 108:.1f}" '
          f'fill="{tile_hex}"/>\n'
          f'  <path fill="#FFFFFF" d="{d}"/>\n'
          '</svg>\n')


if __name__ == "__main__":
    main()
