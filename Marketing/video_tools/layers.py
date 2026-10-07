"""Overlay images for the promo reel: phone frame, captions and end card.

Usage: python3 layers.py <output folder>
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

OUT = sys.argv[1]
HERE = os.path.dirname(os.path.abspath(__file__))
ICON = os.path.join(HERE, "../../MouseControllerPhone/Assets.xcassets/AppIcon.appiconset/MouseControllerIcon.png")
FONT = "/System/Library/Fonts/SFNS.ttf"

W, H = 1080, 1920
BG = (11, 12, 16)
ACCENT = (55, 138, 221)
WHITE = (255, 255, 255)
MUTED = (140, 144, 152)

# Phone screen rectangle on the canvas; compose.swift uses the same numbers.
SX, SY, SW, SH = 222, 450, 636, 1383
SCREEN_R = 88
BEZEL = 16

# Order matches the caption indices in compose.swift.
CAPTIONS = [
    ("Your iPhone is now", "your Mac’s trackpad."),
    ("Pair once with a code.", "Encrypted connection."),
    ("Smooth trackpad", "with real gestures."),
    ("Volume and music", "at your fingertips."),
    ("Type on your Mac", "right from your phone."),
    ("Gestures and speed,", "set your way."),
    ("Your couch just", "became your desk."),
]


def font(size, weight="Regular"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background():
    canvas = Image.new("RGB", (W, H), BG)
    glow = Image.new("RGB", (W, H), BG)
    ImageDraw.Draw(glow).ellipse([60, 560, 1020, 1640], fill=(22, 52, 92))
    return Image.blend(canvas, glow.filter(ImageFilter.GaussianBlur(190)), 1)


os.makedirs(OUT, exist_ok=True)

# Frame: background + phone bezel, with a transparent hole for the video.
frame = background().convert("RGBA")
d = ImageDraw.Draw(frame)
d.rounded_rectangle(
    [SX - BEZEL, SY - BEZEL, SX + SW + BEZEL, SY + SH + BEZEL],
    SCREEN_R + BEZEL, fill=(44, 44, 46), outline=(72, 72, 76), width=3,
)
hole = Image.new("L", (W, H), 255)
ImageDraw.Draw(hole).rounded_rectangle([SX, SY, SX + SW, SY + SH], SCREEN_R, fill=0)
frame.putalpha(hole)
d = ImageDraw.Draw(frame)
d.text((W // 2, 1886), "MouseController  ·  Download on the App Store", font=font(30), fill=MUTED, anchor="mm")
frame.save(f"{OUT}/frame.png")

# Captions: transparent full-canvas images, so placement needs no math.
for i, (line1, line2) in enumerate(CAPTIONS):
    cap = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(cap)
    d.text((W // 2, 92), "MOUSECONTROLLER", font=font(30, "Semibold"), fill=ACCENT, anchor="mm")
    d.text((W // 2, 210), line1, font=font(72, "Bold"), fill=WHITE, anchor="mm")
    d.text((W // 2, 300), line2, font=font(72, "Bold"), fill=WHITE, anchor="mm")
    cap.save(f"{OUT}/cap_{i}.png")

# End card.
end = background().convert("RGBA")
icon = Image.open(ICON).convert("RGBA").resize((300, 300), Image.Resampling.LANCZOS)
mask = Image.new("L", icon.size, 0)
ImageDraw.Draw(mask).rounded_rectangle([0, 0, 299, 299], 68, fill=255)
end.paste(icon, ((W - 300) // 2, 560), mask)
d = ImageDraw.Draw(end)
d.text((W // 2, 990), "MouseController", font=font(88, "Bold"), fill=WHITE, anchor="mm")
d.text((W // 2, 1080), "Control your Mac from your iPhone", font=font(40), fill=MUTED, anchor="mm")
pill_font = font(40, "Semibold")
label = "Download on the App Store"
pw = d.textlength(label, font=pill_font) + 100
d.rounded_rectangle([(W - pw) / 2, 1200, (W + pw) / 2, 1300], 50, fill=ACCENT)
d.text((W // 2, 1250), label, font=pill_font, fill=WHITE, anchor="mm")
end.save(f"{OUT}/endcard.png")

print("ok")
