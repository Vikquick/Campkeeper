"""Draw the Campkeeper logo (original artwork: night sky, tent and campfire).

    python tools/make_logo.py            # writes docs/media/logo.png (512x512)
"""
import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "docs" / "media" / "logo.png"
SIZE, SS = 512, 4  # final size, supersampling factor
S = SIZE * SS


def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(len(a)))


def radial(size, center, radius, inner, outer):
    img = Image.new("RGBA", (size, size))
    px = img.load()
    cx, cy = center
    for y in range(0, size, SS):
        for x in range(0, size, SS):
            t = min(1.0, math.hypot(x - cx, y - cy) / radius)
            c = lerp(inner, outer, t)
            for dy in range(SS):
                for dx in range(SS):
                    px[x + dx, y + dy] = c
    return img


def flame(cx, base, width, height, bend=0.0, n=120):
    """Teardrop flame: round bottom at `base`, tip `height` above, tip bent sideways by `bend`."""
    pts = []
    for i in range(n):
        t = 2 * math.pi * i / n
        x = math.sin(t) * math.sin(t / 2) ** 1.6
        y = math.cos(t)                       # 1 = tip, -1 = bottom
        up = (y + 1) / 2                      # 0 bottom .. 1 tip
        px = cx + x * width + bend * up ** 2 * width
        py = base - up * height
        pts.append((px, py))
    return pts


def main():
    rnd = random.Random(7)
    sky = radial(S, (S * 0.5, S * 0.78), S * 0.95, (64, 38, 70, 255), (10, 14, 34, 255))
    d = ImageDraw.Draw(sky)

    # stars
    for _ in range(70):
        x, y = rnd.uniform(0, S), rnd.uniform(0, S * 0.55)
        r = rnd.choice((1.2, 1.6, 2.2, 3.0)) * SS
        a = rnd.randint(120, 255)
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 244, 220, a))

    # warm glow around the fire
    glow = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    fx, fy = S * 0.56, S * 0.80
    for i in range(40, 0, -1):
        r = S * 0.012 * i
        gd.ellipse((fx - r, fy - r * 0.8, fx + r, fy + r * 0.8), fill=(255, 140, 40, 7))
    glow = glow.filter(ImageFilter.GaussianBlur(S * 0.02))
    sky = Image.alpha_composite(sky, glow)
    d = ImageDraw.Draw(sky)

    # ground: two hills
    d.ellipse((-S * 0.4, S * 0.76, S * 0.9, S * 1.5), fill=(20, 26, 30, 255))
    d.ellipse((S * 0.35, S * 0.80, S * 1.5, S * 1.5), fill=(26, 32, 34, 255))

    # tent (left), lit on the side facing the fire
    tx, ty, tw, th = S * 0.27, S * 0.86, S * 0.36, S * 0.33
    apex = (tx, ty - th)
    d.polygon([apex, (tx - tw / 2, ty), (tx, ty)], fill=(120, 70, 40, 255))
    d.polygon([apex, (tx, ty), (tx + tw / 2, ty)], fill=(214, 128, 58, 255))
    d.polygon([(tx, ty - th * 0.45), (tx - tw * 0.10, ty), (tx + tw * 0.12, ty)], fill=(40, 22, 18, 255))
    d.line([apex, (apex[0], apex[1] - S * 0.04)], fill=(214, 128, 58, 255), width=int(S * 0.008))

    # logs
    lw = S * 0.035
    for (x1, y1, x2, y2) in ((fx - S * 0.13, fy + S * 0.05, fx + S * 0.11, fy - S * 0.01),
                             (fx + S * 0.13, fy + S * 0.05, fx - S * 0.11, fy - S * 0.01)):
        d.line([(x1, y1), (x2, y2)], fill=(92, 52, 30, 255), width=int(lw))
        for (x, y) in ((x1, y1), (x2, y2)):
            d.ellipse((x - lw / 2, y - lw / 2, x + lw / 2, y + lw / 2), fill=(160, 104, 62, 255))

    # flames, back to front
    base = fy + S * 0.01
    d.polygon(flame(fx - S * 0.055, base, S * 0.075, S * 0.24, bend=-0.6), fill=(214, 52, 32, 255))
    d.polygon(flame(fx + S * 0.06, base, S * 0.07, S * 0.21, bend=0.7), fill=(214, 52, 32, 255))
    d.polygon(flame(fx, base, S * 0.11, S * 0.36, bend=0.25), fill=(240, 96, 30, 255))
    d.polygon(flame(fx + S * 0.005, base, S * 0.075, S * 0.25, bend=-0.3), fill=(255, 168, 40, 255))
    d.polygon(flame(fx, base, S * 0.042, S * 0.15, bend=0.2), fill=(255, 236, 140, 255))

    # sparks
    for _ in range(9):
        x = fx + rnd.uniform(-S * 0.12, S * 0.12)
        y = fy - S * 0.3 - rnd.uniform(0, S * 0.18)
        r = rnd.uniform(2, 4) * SS
        d.ellipse((x - r, y - r, x + r, y + r), fill=(255, 190, 80, 230))

    # rounded corners
    mask = Image.new("L", (S, S), 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, S - 1, S - 1), radius=int(S * 0.12), fill=255)
    sky.putalpha(mask)

    OUT.parent.mkdir(parents=True, exist_ok=True)
    sky.resize((SIZE, SIZE), Image.LANCZOS).save(OUT)
    print(f"wrote {OUT}")


if __name__ == "__main__":
    main()
