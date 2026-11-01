"""Builds App Store screenshots from raw app captures, a style, a slide layout, and captions.

Execute it. Read it only to add a new visual element.

  uv run --with pillow --with numpy python compose.py <project-dir> [locale ...] [--out <dir>] [--only <slide>]

<project-dir> holds:
  style.json                     the look: colours, font, background, headline, chips, phone
                                 (references/style-spec.md). Paths in it are relative to this file.
  slides.json                    the layout of each slide: capture, phone, text place, callouts, chips
  captions.json                  {locale: {slide: {"lines": [...], "chips": [...], "badges": [...]}}}
  captures/<locale>/<name>.png   raw simulator screens (for example 1320x2868)
  captures/<locale>/boxes.json   optional {capture: {key: [x0, y0, x1, y1]}} of UI parts per locale
Output: <out>/<locale>/<slide>.png at the canvas size of style.json (default <project-dir>/screenshots).

A slide is: the background, a headline, a phone with the capture, then callouts (UI parts lifted
out of the phone, larger, on a card) and chips (floating cards: a tool icon and a label).
"""
import copy
import json
import os
import sys

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

from PIL import features

# Arabic needs Pillow's raqm layout (HarfBuzz shaping). The Pillow wheels include raqm but load
# fribidi at run time: brew install fribidi, then run with DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib.
HAS_RAQM = features.check("raqm")

RTL_LANGS = ("ar", "he", "fa", "ur")

# The defaults reproduce the dark "dot grid, glow, pill word" look. style.json overrides any key.
DEFAULT_STYLE = {
    "canvas": [1320, 2868],
    "background": {
        "color": "#0C0C0E",
        "gradient": None,                       # ["#top", "#bottom"] replaces the flat colour
        "glow": {"color": "#960E14", "alpha": 150, "radius": [620, 760], "blur": 260},
        "dots": {"spacing": 30, "radius": 1.6, "alpha": 34, "color": "#FFFFFF"},
    },
    "font": {"path": None, "weight": 850, "cjk": {}},
    "headline": {
        "size": 158, "cjk_size": 140,          # CJK glyphs are taller: a smaller size, more line space
        "line_height": 1.02, "cjk_line_height": 1.17,
        "margin_x": 86, "align": "left",
        "colors": ["#FFFFFF", "#5C5C63"],      # the plain lines take these colours in turn
        "accent": "pill",                       # the accent line: "pill", "color", or "none"
        "accent_line": -1,                      # which line takes the accent: -1 = the last, 0 = the first
        "line_scale": None,                     # per-line size factors, e.g. [1, 0.55]; None = all 1
        "accent_color": None,                   # for "color"; None = the fill of the slide pill
        "pill_tilt": 3,
        "top": 210, "top_with_icon": 300, "bottom_margin": 250,
    },
    "pills": {
        "red": ["#E31B23", "#FFFFFF"], "yellow": ["#FFD60A", "#111111"], "blue": ["#0A84FF", "#111111"],
        "green": ["#34D359", "#111111"], "orange": ["#FF6B00", "#111111"], "white": ["#FFFFFF", "#111111"],
    },
    "chip": {"fill": "#FFFFFF", "ink": "#111111", "font_size": 64, "height": 176, "icon": 116, "shadow_alpha": 190},
    "callout": {"fill": "#FFFFFF", "radius": 34, "pad": 14, "shadow_alpha": 170},
    "badge": {"colors": [["#FFD60A", "#111111"], ["#FFFFFF", "#111111"]]},
    "phone": {
        "default": "flat",                      # "flat" (drawn here) or a mockup name in "mockups"
        "mockups": None,                        # folder with <name>_body/_mask/_island.png and <name>.json
        "shadow": 0.55,
        "flat": {"body": "#1C1C1E", "rim": "#48484A", "bezel": 0.028, "radius": 0.15, "island": True},
    },
    "icon": {"path": None, "size": 190, "glow": None},
    "fade": True,                               # fade the phone into the background under the text
}


def fail(msg):
    print(f"compose: {msg}", file=sys.stderr)
    sys.exit(1)


def deep_merge(base, over):
    out = copy.deepcopy(base)
    for k, v in (over or {}).items():
        out[k] = deep_merge(out[k], v) if isinstance(v, dict) and isinstance(out.get(k), dict) else v
    return out


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))


class Style:
    def __init__(self, path):
        self.dir = os.path.dirname(os.path.abspath(path))
        self.s = deep_merge(DEFAULT_STYLE, json.load(open(path, encoding="utf-8")))
        self.W, self.H = self.s["canvas"]
        if not self.s["font"]["path"]:
            fail("style.json needs font.path (a TTF/OTF file, for example an OFL Google Font).")
        self._fonts = {}
        self._warned = set()

    def path(self, p):
        p = os.path.expanduser(p)
        return p if os.path.isabs(p) else os.path.join(self.dir, p)

    def font(self, size, locale, weight=None):
        cjk = {**self.s["font"]["cjk"], **self.s["font"].get("rtl", {})}
        lang = locale.split("-")[0]
        src = cjk.get(locale) or cjk.get(lang) or self.s["font"]["path"]
        if src == self.s["font"]["path"] and lang in ("ja", "ko", "zh") and locale not in self._warned:
            print(f"compose: warning: no CJK font for {locale} in font.cjk; the Latin font shows boxes.", file=sys.stderr)
            self._warned.add(locale)
        key = (src, size, weight)
        if key not in self._fonts:
            f = ImageFont.truetype(self.path(src), size)
            try:
                axes = f.get_variation_axes()
            except (OSError, AttributeError):
                axes = []  # a static font has no axes; its weight is fixed
            if axes:
                want = weight or self.s["font"]["weight"]
                # Set the weight axis by name and keep the other axes (opsz, wdth) at their default.
                vals = []
                for a in axes:
                    name = a.get("name", b"")
                    name = name.decode("latin-1") if isinstance(name, bytes) else str(name)
                    v = max(a["minimum"], min(a["maximum"], want)) if name.lower() in ("weight", "wght") else a["default"]
                    vals.append(v)
                f.set_variation_by_axes(vals)
            self._fonts[key] = f
        return self._fonts[key]

    def is_cjk(self, locale):
        return locale.split("-")[0] in ("ja", "ko", "zh")

    def is_rtl(self, locale):
        return locale.split("-")[0] in RTL_LANGS

    def vis(self, text, locale):
        """Checks that a right-to-left locale can be drawn. raqm does the shaping and the order."""
        if not text or not self.is_rtl(locale):
            return text
        if not HAS_RAQM:
            fail("right-to-left text needs Pillow raqm: brew install fribidi, then set "
                 "DYLD_FALLBACK_LIBRARY_PATH=/opt/homebrew/lib")
        return text  # raqm shapes the letters and orders them right to left


def background(st, glow_at):
    W, H, b = st.W, st.H, st.s["background"]
    if b.get("stops"):
        # [[pos, "#hex"], ...] top to bottom, pos 0..1
        pos = [p for p, _ in b["stops"]]
        cols = np.array([rgb(c) for _, c in b["stops"]], float)
        t = np.linspace(0, 1, H)
        col = np.stack([np.interp(t, pos, cols[:, i]) for i in range(3)], 1)
        im = Image.fromarray(np.broadcast_to(col[:, None, :], (H, W, 3)).astype(np.uint8))
    elif b.get("gradient"):
        top, bottom = (np.array(rgb(c), float) for c in b["gradient"])
        t = np.linspace(0, 1, H)[:, None, None]
        im = Image.fromarray(np.broadcast_to(top * (1 - t) + bottom * t, (H, W, 3)).astype(np.uint8))
    else:
        im = Image.new("RGB", (W, H), rgb(b["color"]))
    g = b.get("glow")
    if g and glow_at:
        m = Image.new("L", (W, H), 0)
        rx, ry = g["radius"]
        ImageDraw.Draw(m).ellipse((glow_at[0] - rx, glow_at[1] - ry, glow_at[0] + rx, glow_at[1] + ry), fill=g["alpha"])
        im = Image.composite(Image.new("RGB", (W, H), rgb(g["color"])), im, m.filter(ImageFilter.GaussianBlur(g["blur"])))
    for hill in b.get("hills") or []:
        # A soft ridge: base y (0..1 of H) plus a sum of sine waves [cycles, phase, amp px].
        xs = np.arange(W)
        ys = hill["base"] * H + sum(a * np.sin(2 * np.pi * (c * xs / W + ph)) for c, ph, a in hill["waves"])
        top = int(max(0, ys.min()))
        top_c, bot_c = (np.array(rgb(c), float) for c in hill["colors"])
        t = np.clip((np.arange(H) - top) / max(1, H - top), 0, 1)[:, None]
        layer = Image.fromarray(np.broadcast_to((top_c * (1 - t) + bot_c * t)[:, None, :], (H, W, 3)).astype(np.uint8))
        m = (np.arange(H)[:, None] >= ys[None, :]).astype(np.uint8) * 255
        im = Image.composite(layer, im, Image.fromarray(m, "L").filter(ImageFilter.GaussianBlur(1.2)))
    if b.get("grain"):
        rng = np.random.default_rng(7)
        n = rng.normal(0, b["grain"], (H, W, 1))
        im = Image.fromarray(np.clip(np.asarray(im, float) + n, 0, 255).astype(np.uint8))
    d = b.get("dots")
    if d:
        m = Image.new("L", (W, H), 0)
        dr = ImageDraw.Draw(m)
        s, r = d["spacing"], d["radius"]
        for y in range(s // 2, H, s):
            for x in range(s // 2, W, s):
                dr.ellipse((x - r, y - r, x + r, y + r), fill=d["alpha"])
        im = Image.composite(Image.new("RGB", (W, H), rgb(d["color"])), im, m)
    return im


def perspective_coeffs(src, dst):
    """The 8 coefficients that map each output point in dst to the input point in src."""
    rows, rhs = [], []
    for (x, y), (u, v) in zip(dst, src):
        rows.append([x, y, 1, 0, 0, 0, -u * x, -u * y]); rhs.append(u)
        rows.append([0, 0, 0, x, y, 1, -v * x, -v * y]); rhs.append(v)
    return np.linalg.solve(np.array(rows, float), np.array(rhs, float)).tolist()


def flat_phone(st, capture, height):
    """A drawn phone: a dark body with a thin rim, the capture as the screen, and a Dynamic Island."""
    f = st.s["phone"]["flat"]
    bezel = round(height * f["bezel"])
    sh = height - 2 * bezel
    sw = round(sh * capture.width / capture.height)
    bw = sw + 2 * bezel
    radius = round(bw * f["radius"])
    out = Image.new("RGBA", (bw, height), (0, 0, 0, 0))
    d = ImageDraw.Draw(out)
    d.rounded_rectangle((0, 0, bw - 1, height - 1), radius=radius, fill=rgb(f["body"]) + (255,))
    d.rounded_rectangle((1, 1, bw - 2, height - 2), radius=radius, outline=rgb(f["rim"]) + (255,), width=max(2, bezel // 5))
    screen = capture.convert("RGBA").resize((sw, sh), Image.LANCZOS)
    m = Image.new("L", (sw, sh), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, sw - 1, sh - 1), radius=max(0, radius - bezel), fill=255)
    out.paste(screen, (bezel, bezel), m)
    if f.get("island"):
        # iPhone 17 Pro Max: the island is about 126x37 pt on a 440 pt wide screen, 11 pt from the top.
        iw, ih, top = sw * 0.286, sw * 0.084, sw * 0.025
        x0 = bezel + (sw - iw) / 2
        d.rounded_rectangle((x0, bezel + top, x0 + iw, bezel + top + ih), radius=ih / 2, fill=(0, 0, 0, 255))
    quad = [(bezel, bezel), (bezel + sw, bezel), (bezel + sw, bezel + sh), (bezel, bezel + sh)]
    return out, quad


def mockup_phone(st, kind, mirror, capture, height):
    """A photographed phone from the mockup parts, with the capture warped into its screen."""
    folder = st.s["phone"]["mockups"]
    if not folder:
        fail(f"slide asks for phone '{kind}', but style.json has no phone.mockups folder. Use \"flat\" or run prep_mockup.py.")
    folder = st.path(folder)
    try:
        body = Image.open(os.path.join(folder, f"{kind}_body.png")).convert("RGBA")
        mask = Image.open(os.path.join(folder, f"{kind}_mask.png")).convert("L")
        island = Image.open(os.path.join(folder, f"{kind}_island.png")).convert("RGBA")
        quad = json.load(open(os.path.join(folder, f"{kind}.json")))["quad"]
    except FileNotFoundError as e:
        fail(f"mockup part missing: {e.filename}. Run prep_mockup.py for '{kind}'.")
    if mirror:
        bw = body.width
        body, mask, island = (i.transpose(Image.Transpose.FLIP_LEFT_RIGHT) for i in (body, mask, island))
        tl, tr, br, bl = quad
        quad = [(bw - tr[0], tr[1]), (bw - tl[0], tl[1]), (bw - bl[0], bl[1]), (bw - br[0], br[1])]
    s = height / body.height
    size = (round(body.width * s), height)
    body, mask, island = (i.resize(size, Image.LANCZOS) for i in (body, mask, island))
    quad = [(x * s, y * s) for x, y in quad]
    cw, ch = capture.size
    coeffs = perspective_coeffs([(0, 0), (cw, 0), (cw, ch), (0, ch)], quad)
    screen = capture.convert("RGBA").transform(size, Image.PERSPECTIVE, coeffs, Image.BICUBIC)
    out = body.copy()
    out.paste(screen, (0, 0), mask)
    out.alpha_composite(island)
    return out, quad


def card_tile(card, radius, shadow_alpha, rot, drop=30, blur=36):
    """A card with a soft drop shadow, rotated. Returns the tile and its margin."""
    margin = 90
    tile = Image.new("RGBA", (card.width + 2 * margin, card.height + 2 * margin), (0, 0, 0, 0))
    shadow = Image.new("RGBA", tile.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((margin, margin + drop, margin + card.width, margin + card.height + drop),
                                             radius=radius, fill=(0, 0, 0, shadow_alpha))
    tile.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(blur)))
    tile.alpha_composite(card, (margin, margin))
    if rot:
        tile = tile.rotate(rot, resample=Image.BICUBIC, expand=True)
    return tile, margin


def paste_center(canvas, tile, at, clamp_margin=None):
    x = at[0] - tile.width / 2
    if clamp_margin is not None:  # keep the card inside the canvas
        x = min(max(x, 40 - clamp_margin), canvas.width - 40 + clamp_margin - tile.width)
    layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    layer.paste(tile, (round(x), round(at[1] - tile.height / 2)), tile)
    canvas.alpha_composite(layer)


def callout(st, canvas, capture, box, scale, at, rot, ring):
    """One UI part of the capture, larger, on a rounded card with a shadow."""
    c = st.s["callout"]
    part = capture.crop(box).convert("RGBA")
    part = part.resize((round(part.width * scale), round(part.height * scale)), Image.LANCZOS)
    pad, radius = c["pad"], c["radius"]
    card = Image.new("RGBA", (part.width + 2 * pad, part.height + 2 * pad), (0, 0, 0, 0))
    ImageDraw.Draw(card).rounded_rectangle((0, 0, card.width - 1, card.height - 1), radius=radius + pad,
                                           fill=rgb(c["fill"]) + (255,))
    m = Image.new("L", part.size, 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, part.width - 1, part.height - 1), radius=radius, fill=255)
    card.paste(part, (pad, pad), m)
    if ring:
        ImageDraw.Draw(card).rounded_rectangle((2, 2, card.width - 3, card.height - 3), radius=radius + pad,
                                               outline=pill_colors(st, ring)[0] + (255,), width=8)
    tile, _ = card_tile(card, radius + pad, c["shadow_alpha"], rot)
    paste_center(canvas, tile, at)


def chip(st, canvas, icon, label, locale, at, rot, ring):
    """One floating tool card: a tool icon and a large label."""
    c = st.s["chip"]
    f = st.font(c["font_size"], locale, 800)
    label = st.vis(label, locale)
    tw = round(ImageDraw.Draw(canvas).textlength(label, font=f))
    side, ch = c["icon"], c["height"]
    icon = icon.convert("RGBA")
    k = side / max(icon.size)
    icon = icon.resize((round(icon.width * k), round(icon.height * k)), Image.LANCZOS)
    pad, gap = round(ch * 0.19), round(ch * 0.15)
    card = Image.new("RGBA", (pad + side + gap + tw + pad + 12, ch), (0, 0, 0, 0))
    d = ImageDraw.Draw(card)
    d.rounded_rectangle((0, 0, card.width - 1, ch - 1), radius=ch // 2, fill=rgb(c["fill"]) + (255,))
    if ring:
        d.rounded_rectangle((3, 3, card.width - 4, ch - 4), radius=ch // 2 - 3, outline=pill_colors(st, ring)[0] + (255,), width=9)
    card.alpha_composite(icon, (pad + (side - icon.width) // 2, (ch - icon.height) // 2))
    asc, desc = f.getmetrics()
    d.text((pad + side + gap, (ch - asc - desc) // 2 + 4), label, font=f, fill=rgb(c["ink"]))
    tile, margin = card_tile(card, ch // 2, c["shadow_alpha"], rot, drop=28, blur=34)
    paste_center(canvas, tile, at, clamp_margin=margin)


def pill_colors(st, name):
    if name not in st.s["pills"]:
        fail(f"pill '{name}' is not in style.json pills ({', '.join(st.s['pills'])}).")
    fill, ink = st.s["pills"][name]
    return rgb(fill), rgb(ink)


def headline(st, im, lines, locale, pill, top):
    """Draws the headline lines. One line (headline.accent_line) takes the accent of the style: a
    tilted pill, a colour, or nothing. headline.line_scale gives each line its own size, for a big
    keyword over a small sub-line. Returns (top, bottom)."""
    h = st.s["headline"]
    W, H = st.W, st.H
    draw = ImageDraw.Draw(im)
    cjk = st.is_cjk(locale)
    base = h["cjk_size"] if cjk else h["size"]
    scales = list(h.get("line_scale") or []) + [1] * len(lines)
    accent = h["accent"]
    ai = h.get("accent_line", -1) % len(lines) if accent != "none" else None
    if len(lines) == 1 and accent == "pill":
        accent = "color"  # one line on a pill reads as a button, not a headline
    # Shrink all lines together until the widest fits in the margins.
    k = 1.0
    while k > 0.4:
        fonts = [st.font(max(12, round(base * scales[i] * k)), locale) for i in range(len(lines))]
        if max(draw.textlength(t, font=f) for t, f in zip(lines, fonts)) <= W - 2 * h["margin_x"]:
            break
        k -= 0.04
    lhf = h["cjk_line_height"] if cjk else h["line_height"]
    rows = []  # (text, font, height, is_accent)
    for i, (t, f) in enumerate(zip(lines, fonts)):
        if i == ai and accent == "pill":
            asc, desc = f.getmetrics()
            rows.append((t, f, round(asc * 0.86 + desc * 0.5 + 2 * round(f.size * 0.14)) + 40, True))
        else:
            rows.append((t, f, round(f.size * lhf), i == ai))
    block_h = sum(r[2] for r in rows)
    y0 = top if top is not None else H - h["bottom_margin"] - block_h

    def x_for(width):
        return (W - width) / 2 if h["align"] == "center" else h["margin_x"]

    fill, ink = pill_colors(st, pill)
    y, plain_i = y0, 0
    for t, f, rh, is_accent in rows:
        tw = draw.textlength(t, font=f)
        if is_accent and accent == "pill":
            pad_x, pad_y = round(f.size * 0.26), round(f.size * 0.14)
            asc, desc = f.getmetrics()
            pw, ph = round(tw + 2 * pad_x), rh - 40
            tile = Image.new("RGBA", (pw + 40, ph + 40), (0, 0, 0, 0))
            td = ImageDraw.Draw(tile)
            td.rounded_rectangle((20, 20, 20 + pw, 20 + ph), radius=round(ph * 0.28), fill=fill + (255,))
            td.text((20 + pad_x, 20 + pad_y - round(asc * 0.16)), t, font=f, fill=ink)
            if h["pill_tilt"]:
                tile = tile.rotate(h["pill_tilt"], resample=Image.BICUBIC, expand=True)
            px = (W - tile.width) / 2 if h["align"] == "center" else h["margin_x"] - 28
            im.paste(tile, (round(px), y - 6), tile)
        elif is_accent:
            draw.text((x_for(tw), y), t, font=f, fill=rgb(h["accent_color"]) if h["accent_color"] else fill)
        else:
            draw.text((x_for(tw), y), t, font=f, fill=rgb(h["colors"][plain_i % len(h["colors"])]))
            plain_i += 1
        y += rh
    return y0, y


def runs_of(line, st=None, locale=None):
    parts = line.split("**")
    runs = [(t, i % 2 == 1) for i, t in enumerate(parts) if t]
    if st and st.is_rtl(locale):  # the first run is on the right: draw the runs from left to right
        runs = [(st.vis(t, locale), b) for t, b in reversed(runs)]
    return runs


def rich_headline(st, im, lines, locale, top):
    """Rise-style headline: plain words in a regular weight, **marked** words in bold, one colour."""
    h = st.s["headline"]
    W, H = st.W, st.H
    draw = ImageDraw.Draw(im)
    scales = list(h.get("line_scale") or []) + [1] * len(lines)
    wr, wb = h.get("regular_weight", 400), h.get("bold_weight", 700)
    k = 1.0
    while k > 0.4:
        widths = []
        for i, line in enumerate(lines):
            size = max(12, round(h["size"] * scales[i] * k))
            widths.append(sum(draw.textlength(t, font=st.font(size, locale, wb if b else wr)) for t, b in runs_of(line, st, locale)))
        if max(widths) <= W - 2 * h["margin_x"]:
            break
        k -= 0.04
    y = top + (h.get("rtl_dy", 50) if st.is_rtl(locale) else 0)  # the Arabic glyphs sit higher in the line box
    color = rgb(h["colors"][0])
    for i, line in enumerate(lines):
        size = max(12, round(h["size"] * scales[i] * k))
        if h["align"] == "center":
            x = (W - widths[i]) / 2
        else:
            x = W - h["margin_x"] - widths[i] if st.is_rtl(locale) else h["margin_x"]
        for t, b in runs_of(line, st, locale):
            f = st.font(size, locale, wb if b else wr)
            draw.text((x, y), t, font=f, fill=color)
            x += draw.textlength(t, font=f)
        # Arabic needs more room: its marks reach above and below the Latin line.
        y += round(size * h["line_height"] * (h.get("rtl_line_scale", 1.2) if st.is_rtl(locale) else 1))
    return top, y


def kicker(st, im, text, locale, y):
    k = st.s.get("kicker") or {}
    f = st.font(k.get("size", 50), locale, k.get("weight", 600))
    draw = ImageDraw.Draw(im)
    track = k.get("tracking", 4)
    if st.is_rtl(locale):  # letter spacing breaks the joined Arabic letters
        text, track = st.vis(text, locale), 0
        y += k.get("rtl_dy", 36)  # the Arabic glyphs sit higher in the line box
        w = draw.textlength(text, font=f)
        hs = st.s["headline"]
        x = (st.W - w) / 2 if hs["align"] == "center" else st.W - hs["margin_x"] - w
        draw.text((x, y), text, font=f, fill=rgb(k.get("color", "#F28C38")))
        return
    w = sum(draw.textlength(ch, font=f) + track for ch in text) - track
    x = (st.W - w) / 2 if st.s["headline"]["align"] == "center" else st.s["headline"]["margin_x"]
    for ch in text:
        draw.text((x, y), ch, font=f, fill=rgb(k.get("color", "#F28C38")))
        x += draw.textlength(ch, font=f) + track


def disc(st, canvas, at, r, big, unit, label, locale):
    """A dark disc with a big number, a small unit, and a label: the Rise "6.3 hrs" callout."""
    d = st.s.get("disc") or {}
    card = Image.new("RGBA", (2 * r, 2 * r), (0, 0, 0, 0))
    dr = ImageDraw.Draw(card)
    dr.ellipse((0, 0, 2 * r - 1, 2 * r - 1), fill=rgb(d.get("fill", "#1C1C21")) + (255,))
    fb = st.font(round(r * 0.62), locale, d.get("big_weight", 400))
    fu = st.font(round(r * 0.17), locale, 500)
    fl = st.font(round(r * 0.22), locale, 500)
    ink = rgb(d.get("ink", "#FFFFFF"))
    bw = dr.textlength(big, font=fb)
    uw = dr.textlength(unit, font=fu) + (r * 0.05 if unit else 0)
    x0 = r - (bw + uw) / 2
    asc, _ = fb.getmetrics()
    by = r - asc * 0.78
    dr.text((x0, by), big, font=fb, fill=ink)
    if unit:
        dr.text((x0 + bw + r * 0.05, by + asc * 0.12), unit, font=fu, fill=ink)
    label = st.vis(label, locale)
    lw = dr.textlength(label, font=fl)
    dr.text((r - lw / 2, r + r * 0.2), label, font=fl, fill=ink)
    tile, _ = card_tile(card, r, d.get("shadow_alpha", 150), 0)
    paste_center(canvas, tile, at)


def badge(st, im, box, big, small, locale, fill, ink):
    draw = ImageDraw.Draw(im)
    draw.rounded_rectangle(box, radius=64, fill=fill)
    x0, y0, x1, y1 = box
    fb, fs = st.font(104, locale, 900), st.font(44, locale, 600)
    while draw.textlength(big, font=fb) > (x1 - x0) - 60 and fb.size > 40:
        fb = st.font(fb.size - 6, locale, 900)
    draw.text(((x0 + x1 - draw.textlength(big, font=fb)) / 2, y0 + 30), big, font=fb, fill=ink)
    draw.text(((x0 + x1 - draw.textlength(small, font=fs)) / 2, y1 - 84), small, font=fs, fill=ink)


class Project:
    def __init__(self, root):
        self.root = os.path.abspath(root)
        for name in ("style.json", "slides.json", "captions.json"):
            if not os.path.exists(os.path.join(self.root, name)):
                fail(f"{name} is missing in {self.root}.")
        self.style = Style(os.path.join(self.root, "style.json"))
        self.slides = json.load(open(os.path.join(self.root, "slides.json"), encoding="utf-8"))
        self.captions = json.load(open(os.path.join(self.root, "captions.json"), encoding="utf-8"))

    def capture(self, locale, name):
        p = os.path.join(self.root, "captures", locale, f"{name}.png")
        if not os.path.exists(p):
            fail(f"capture missing: {p}")
        return Image.open(p).convert("RGB")

    def box(self, locale, capture, key, fallback):
        p = os.path.join(self.root, "captures", locale, "boxes.json")
        boxes = json.load(open(p)) if os.path.exists(p) else {}
        found = boxes.get(capture, {}).get(key) if key else None
        if not found and not fallback:
            fail(f"no box '{key}' for capture '{capture}' in {p}, and no fallback box in slides.json.")
        return found or fallback

    def icon(self, locale, spec):
        """A chip icon: a file path, or [capture, key, x0, y0, x1, y1] cut from a capture."""
        if isinstance(spec, str):
            return Image.open(self.style.path(spec) if not os.path.isabs(spec) else spec)
        src, key, *box = spec
        return self.capture(locale, src).crop(self.box(locale, src, key, box))


def build(pr, locale, slide, cap):
    st, spec = pr.style, pr.slides[slide]
    if spec.get("style"):
        st = copy.copy(st)
        st.s = deep_merge(pr.style.s, spec["style"])
        st.W, st.H = st.s["canvas"]  # a slide may use another size, for example a portrait display
    W, H = st.W, st.H
    lines = cap["lines"]
    bg = background(st, spec.get("glow", [W // 2, H * 0.6]))
    capture = pr.capture(locale, spec.get("capture", slide))
    text = spec.get("text", "top")
    hs = st.s["headline"]
    text_top = None
    if text == "top":
        text_top = hs["top_with_icon"] if spec.get("icon") else hs["top"]
    canvas = bg.convert("RGBA")
    if spec.get("icon"):
        ic = st.s["icon"]
        if not ic["path"]:
            fail(f"slide {slide} has icon: true, but style.json has no icon.path.")
        n = ic["size"]
        icon = Image.open(st.path(ic["path"])).convert("RGBA").resize((n, n), Image.LANCZOS)
        r = round(n * 0.2237)  # the iOS icon corner radius ratio
        m = Image.new("L", icon.size, 0)
        ImageDraw.Draw(m).rounded_rectangle((0, 0, n - 1, n - 1), radius=r, fill=255)
        x, y = ((W - n) // 2, ic.get("top", 70)) if hs["align"] == "center" else (hs["margin_x"], 70)
        if ic.get("glow"):
            g = Image.new("RGBA", (W, H), (0, 0, 0, 0))
            ImageDraw.Draw(g).rounded_rectangle((x, y, x + n, y + n), radius=r, fill=rgb(ic["glow"]) + (160,))
            canvas.alpha_composite(g.filter(ImageFilter.GaussianBlur(40)))
        canvas.paste(icon, (x, y), m)
    kind = spec.get("phone", st.s["phone"]["default"])
    if kind != "none":
        if kind == "flat":
            ph, quad = flat_phone(st, capture, spec["height"])
        else:
            ph, quad = mockup_phone(st, kind, spec.get("mirror", False), capture, spec["height"])
        px = (W - ph.width) // 2 if spec.get("x") is None else spec["x"]
        py = spec.get("y", H - spec["height"])
        shadow = Image.new("RGBA", ph.size, (0, 0, 0, 0))
        shadow.putalpha(ph.split()[-1].point(lambda a: a * st.s["phone"]["shadow"]))
        sh = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        sh.paste(shadow, (px + 30, py + 50), shadow)
        canvas.alpha_composite(sh.filter(ImageFilter.GaussianBlur(50)))
        layer = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
        layer.paste(ph, (px, py), ph)
        canvas.alpha_composite(layer)
        if st.s["fade"] and text in ("top", "bottom"):
            # Fade the phone into the background under the headline (bottom) or at the canvas end (top).
            start, length = (H - 1250, 420) if text == "bottom" else (H - 260, 260)
            ramp = np.clip((np.arange(H) - start) / length, 0, 1) * 255
            fade = Image.fromarray(np.repeat(ramp.astype(np.uint8)[:, None], W, 1), "L")
            canvas.paste(bg.convert("RGBA"), (0, 0), fade)
        screen_x, screen_y = px + quad[0][0], py + quad[0][1]
        on_phone = (quad[1][0] - quad[0][0]) / capture.width
    else:
        screen_x = screen_y = 0
        on_phone = 1.0
    if text in ("top", "bottom"):
        if cap.get("kicker"):
            kicker(st, canvas, cap["kicker"], locale, text_top)
            text_top += st.s.get("kicker", {}).get("gap", 110)
        if hs["accent"] == "bold":
            rich_headline(st, canvas, lines, locale, text_top)
        else:
            headline(st, canvas, lines, locale, spec.get("pill", next(iter(st.s["pills"]))), text_top)
    for dspec, dtext in zip(spec.get("discs", []), cap.get("discs", [])):
        disc(st, canvas, dspec["at"], dspec.get("r", 300), *dtext, locale)
    for c in spec.get("callouts", []):
        box = pr.box(locale, spec.get("capture", slide), c.get("ref"), c.get("box"))
        x0, y0, x1, y1 = box
        at = c.get("at") or (screen_x + (x0 + x1) / 2 * on_phone, screen_y + (y0 + y1) / 2 * on_phone)
        callout(st, canvas, capture, box, c.get("scale", on_phone * 1.5), at, c.get("rot", 0), c.get("ring"))
    labels = cap.get("chips", [])
    if len(labels) < len(spec.get("chips", [])):
        print(f"compose: warning: {locale}/{slide} has {len(spec['chips'])} chips but {len(labels)} labels.", file=sys.stderr)
    for c, label in zip(spec.get("chips", []), labels):
        chip(st, canvas, pr.icon(locale, c["icon"]), label, locale, c["at"], c.get("rot", 0), c.get("ring"))
    if spec.get("badges"):
        b = cap.get("badges") or fail(f"{locale}/{slide} has badges: true but no badges in captions.json.")
        cols = st.s["badge"]["colors"]
        half = (W - 2 * hs["margin_x"] - 40) // 2
        for i in range(2):
            x0 = hs["margin_x"] + i * (half + 40)
            badge(st, canvas, (x0, H - 330, x0 + half, H - 70), b[i][0], b[i][1], locale, rgb(cols[i][0]), rgb(cols[i][1]))
    return canvas.convert("RGB")


def main(argv):
    out = only = None
    for flag in ("--out", "--only"):
        if flag in argv:
            i = argv.index(flag)
            if flag == "--out":
                out = argv[i + 1]
            else:
                only = argv[i + 1]
            argv = argv[:i] + argv[i + 2:]
    if not argv:
        fail("usage: compose.py <project-dir> [locale ...] [--out <dir>] [--only <slide>]")
    pr = Project(argv[0])
    locales = argv[1:] or ["en-US"]
    out = out or os.path.join(pr.root, "screenshots")
    for locale in locales:
        if locale not in pr.captions:
            fail(f"no captions for {locale} in captions.json.")
        os.makedirs(os.path.join(out, locale), exist_ok=True)
        for slide in pr.slides:
            if (only and slide != only) or slide not in pr.captions[locale]:
                continue
            path = os.path.join(out, locale, f"{slide}.png")
            build(pr, locale, slide, pr.captions[locale][slide]).save(path, optimize=True)
            print(path)


if __name__ == "__main__":
    main(sys.argv[1:])
