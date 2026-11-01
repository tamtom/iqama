"""Side-by-side view of the final icon candidates: large, and at Home Screen sizes on dark and light."""
import sys
from PIL import Image, ImageDraw, ImageFont

names = sys.argv[1:] or ["final-A.png", "final-B.png", "final-C.png"]
col = 460
out = Image.new("RGB", (40 + col * len(names), 760), "#1c1c1e")
d = ImageDraw.Draw(out)
font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 34)


def masked(path, n):
    im = Image.open(path).convert("RGB").resize((n, n), Image.LANCZOS)
    m = Image.new("L", (n, n), 0)
    ImageDraw.Draw(m).rounded_rectangle((0, 0, n - 1, n - 1), radius=round(n * 0.2237), fill=255)
    return im, m


for i, p in enumerate(names):
    x = 40 + i * col
    im, m = masked(p, 400)
    out.paste(im, (x, 40), m)
    for row, bg in enumerate(("#101014", "#E9E6F0")):
        y = 480 + row * 120
        d.rounded_rectangle((x, y, x + 400, y + 100), radius=24, fill=bg)
        for j, n in enumerate((60, 40)):
            s, mm = masked(p, n)
            out.paste(s, (x + 60 + j * 140, y + (100 - n) // 2), mm)
    d.text((x, 715), p.removesuffix(".png").replace("final-", ""), font=font, fill="white")
out.save("finals-compare.png")
