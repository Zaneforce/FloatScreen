#!/usr/bin/env python3
"""Generate FloatScreen app icon at all required sizes.

Draws two overlapping white window shapes on a blue-to-indigo gradient
squircle background. No SF Symbols used — all shapes are drawn from scratch.
"""

from PIL import Image, ImageDraw, ImageFilter
import json, os, math

SIZES = [16, 32, 64, 128, 256, 512, 1024]
OUT_DIR = os.path.join(os.path.dirname(__file__), "..",
                       "FloatScreen", "Assets.xcassets", "AppIcon.appiconset")


def lerp_color(c1, c2, t):
    return tuple(int(a + (b - a) * t) for a, b in zip(c1, c2))


def draw_rounded_rect(draw, rect, radius, **kwargs):
    x0, y0, x1, y1 = rect
    r = min(radius, (x1 - x0) / 2, (y1 - y0) / 2)
    draw.rounded_rectangle(rect, radius=r, **kwargs)


def draw_icon(size):
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    draw = ImageDraw.Draw(img)

    # Squircle background with gradient
    corner_r = size * 0.22
    # Draw gradient line by line
    top_color = (66, 133, 244)      # blue
    bot_color = (88, 64, 196)       # indigo
    for y in range(size):
        t = y / max(size - 1, 1)
        color = lerp_color(top_color, bot_color, t)
        draw.line([(0, y), (size - 1, y)], fill=color)

    # Mask to squircle
    mask = Image.new("L", (size, size), 0)
    mask_draw = ImageDraw.Draw(mask)
    mask_draw.rounded_rectangle(
        [0, 0, size - 1, size - 1], radius=int(corner_r), fill=255
    )
    img.putalpha(mask)

    # Window dimensions
    s = size  # shorthand
    w_width = int(s * 0.42)
    w_height = int(s * 0.38)
    title_h = max(int(s * 0.06), 2)

    # Back window (offset up-left)
    bx = int(s * 0.18)
    by = int(s * 0.22)
    wr = max(int(s * 0.04), 1)

    # Shadow for back window
    shadow = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        [bx + 2, by + 2, bx + w_width + 2, by + w_height + 2],
        radius=wr, fill=(0, 0, 0, 60)
    )
    if size >= 64:
        shadow = shadow.filter(ImageFilter.GaussianBlur(radius=max(size // 80, 1)))
    img = Image.alpha_composite(img, shadow)
    draw = ImageDraw.Draw(img)

    # Draw back window
    draw_rounded_rect(draw, [bx, by, bx + w_width, by + w_height],
                      wr, fill=(255, 255, 255, 200))
    # Title bar
    draw_rounded_rect(draw, [bx, by, bx + w_width, by + title_h],
                      wr, fill=(255, 255, 255, 240))
    # Title bar dots
    dot_r = max(int(s * 0.012), 1)
    dot_y = by + title_h // 2
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        cx = bx + int(s * 0.03) + i * int(s * 0.025)
        if dot_r >= 1:
            draw.ellipse([cx - dot_r, dot_y - dot_r, cx + dot_r, dot_y + dot_r],
                         fill=c)

    # Front window (offset down-right)
    fx = int(s * 0.38)
    fy = int(s * 0.36)

    # Shadow for front window
    shadow2 = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    sd2 = ImageDraw.Draw(shadow2)
    sd2.rounded_rectangle(
        [fx + 3, fy + 3, fx + w_width + 3, fy + w_height + 3],
        radius=wr, fill=(0, 0, 0, 80)
    )
    if size >= 64:
        shadow2 = shadow2.filter(ImageFilter.GaussianBlur(radius=max(size // 60, 1)))
    img = Image.alpha_composite(img, shadow2)
    draw = ImageDraw.Draw(img)

    # Draw front window
    draw_rounded_rect(draw, [fx, fy, fx + w_width, fy + w_height],
                      wr, fill=(255, 255, 255, 240))
    # Title bar
    draw_rounded_rect(draw, [fx, fy, fx + w_width, fy + title_h],
                      wr, fill=(255, 255, 255, 255))
    # Title bar dots
    dot_y = fy + title_h // 2
    for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
        cx = fx + int(s * 0.03) + i * int(s * 0.025)
        if dot_r >= 1:
            draw.ellipse([cx - dot_r, dot_y - dot_r, cx + dot_r, dot_r + dot_y],
                         fill=c)

    return img


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    contents_images = []

    for sz in SIZES:
        for scale in [1, 2]:
            px = sz * scale
            img = draw_icon(px)
            filename = f"icon_{sz}x{sz}@{scale}x.png"
            filepath = os.path.join(OUT_DIR, filename)
            img.save(filepath, "PNG")
            contents_images.append({
                "filename": filename,
                "idiom": "mac",
                "scale": f"{scale}x",
                "size": f"{sz}x{sz}"
            })
            print(f"  Generated {filename} ({px}x{px})")

    contents = {
        "images": contents_images,
        "info": {"author": "xcode", "version": 1}
    }
    with open(os.path.join(OUT_DIR, "Contents.json"), "w") as f:
        json.dump(contents, f, indent=2)

    # Preview at 256px
    preview = draw_icon(256)
    preview_path = os.path.join(os.path.dirname(__file__), "..", "icon_preview.png")
    preview.save(preview_path, "PNG")
    print(f"\n  Preview saved to {preview_path}")


if __name__ == "__main__":
    main()
