from PIL import Image, ImageDraw, ImageFilter, ImageFont

import os
ROOT = os.path.dirname(os.path.abspath(__file__))
FONT = "/System/Library/Fonts/SFNS.ttf"

BG = (11, 12, 16)
CARD = (27, 29, 34)
PAD = (21, 23, 28)
ACCENT = (55, 138, 221)
WHITE = (255, 255, 255)
MUTED = (140, 144, 152)


def font(size, weight="Regular"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return mask


# --- Screenshots (captured against a demo Mac named "MacBook Pro"), plus a touch ripple on the pad.

connect = Image.open(f"{ROOT}/screens/connect.png").convert("RGB")

trackpad = Image.open(f"{ROOT}/screens/trackpad.png").convert("RGB")
d = ImageDraw.Draw(trackpad, "RGBA")

# A finger-touch ripple like the app draws, so the pad doesn't look empty.
cx, cy, r = 700, 1050, 80
d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT + (90,), outline=ACCENT + (255,), width=10)
for i, (tx, ty) in enumerate([(430, 1500), (520, 1330), (610, 1180)]):
    rr = 20 - i * 4
    d.ellipse([tx - rr, ty - rr, tx + rr, ty + rr], fill=ACCENT + (60 + i * 50,))


def phone(screen, height):
    width = round(screen.width * height / screen.height)
    shot = screen.resize((width, height), Image.Resampling.LANCZOS)
    bezel = 12
    frame = Image.new("RGBA", (width + bezel * 2, height + bezel * 2), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        [0, 0, frame.width - 1, frame.height - 1], 62, fill=(44, 44, 46), outline=(70, 70, 74), width=2
    )
    frame.paste(shot, (bezel, bezel), rounded_mask(shot.size, 50))
    return frame


# --- Canvas: 1080x1350 is Instagram's portrait feed format.

W, H = 1080, 1350
canvas = Image.new("RGB", (W, H), BG)

glow = Image.new("RGB", (W, H), BG)
ImageDraw.Draw(glow).ellipse([140, 420, 940, 1160], fill=(22, 52, 92))
canvas = Image.blend(canvas, glow.filter(ImageFilter.GaussianBlur(160)), 1)

draw = ImageDraw.Draw(canvas)

draw.text((W // 2, 92), "MOUSECONTROLLER", font=font(30, "Semibold"), fill=ACCENT, anchor="mm")
draw.text((W // 2, 168), "Your iPhone is now", font=font(66, "Bold"), fill=WHITE, anchor="mm")
draw.text((W // 2, 244), "your Mac’s trackpad.", font=font(66, "Bold"), fill=WHITE, anchor="mm")

back = phone(connect, 700)
front = phone(trackpad, 760)

# Shadow under the front phone so the two separate.
shadow = Image.new("RGBA", (W, H), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([520, 350, 520 + front.width, 350 + front.height], 62, fill=(0, 0, 0, 170))
canvas.paste(shadow.filter(ImageFilter.GaussianBlur(30)), (0, 0), shadow.filter(ImageFilter.GaussianBlur(30)))

canvas.paste(back, (175, 380), back)
canvas.paste(front, (505, 325), front)

draw = ImageDraw.Draw(canvas)

chips = ["Trackpad & gestures", "Keyboard & shortcuts", "Volume & media", "Encrypted pairing"]
chip_font = font(28, "Medium")
rows = [chips[:2], chips[2:]]
y = 1150
for row in rows:
    widths = [draw.textlength(c, font=chip_font) + 56 for c in row]
    x = (W - (sum(widths) + 16 * (len(row) - 1))) / 2
    for label, w in zip(row, widths):
        draw.rounded_rectangle([x, y, x + w, y + 58], 29, fill=CARD, outline=(46, 49, 56), width=2)
        draw.text((x + w / 2, y + 29), label, font=chip_font, fill=WHITE, anchor="mm")
        x += w + 16
    y += 72

draw.text((W // 2, 1308), "Download on the App Store", font=font(26, "Regular"), fill=MUTED, anchor="mm")

canvas.save(f"{ROOT}/instagram_post.png", optimize=True)
print("saved", canvas.size)
