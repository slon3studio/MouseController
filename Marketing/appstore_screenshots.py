"""Builds App Store screenshots from raw simulator captures.

iPhone: 1320x2868 (6.9") and 1206x2622 (6.1"/6.3"). Mac: 2880x1800.
Raw captures (1206x2622 simulator screenshots and the rendered Mac window)
are expected in the folder passed as the first argument.
"""

import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

RAW = sys.argv[1]
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "appstore")
FONT = "/System/Library/Fonts/SFNS.ttf"

BG = (11, 12, 16)
GLOW = (22, 52, 92)
ACCENT = (55, 138, 221)
WHITE = (255, 255, 255)
BEZEL = (44, 44, 46)
BEZEL_EDGE = (72, 72, 76)


def font(size, weight="Regular"):
    f = ImageFont.truetype(FONT, size)
    f.set_variation_by_name(weight)
    return f


def background(size, glow_box):
    canvas = Image.new("RGB", size, BG)
    glow = Image.new("RGB", size, BG)
    ImageDraw.Draw(glow).ellipse(glow_box, fill=GLOW)
    blur = max(size) // 9
    return Image.blend(canvas, glow.filter(ImageFilter.GaussianBlur(blur)), 1)


def rounded_mask(size, radius):
    mask = Image.new("L", size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, size[0] - 1, size[1] - 1], radius, fill=255)
    return mask


def screen(name, ripple=False):
    shot = Image.open(os.path.join(RAW, f"{name}.png")).convert("RGB")
    if ripple:
        # The app draws this ring under a finger; a still capture can't
        # include a live touch, so it's added here at the same size.
        d = ImageDraw.Draw(shot, "RGBA")
        cx, cy, r = 700, 1050, 69
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=ACCENT + (40,), outline=ACCENT + (255,), width=5)
        for i, (tx, ty) in enumerate([(430, 1500), (520, 1330), (610, 1180)]):
            rr = 16 - i * 3
            d.ellipse([tx - rr, ty - rr, tx + rr, ty + rr], fill=ACCENT + (70 + i * 50,))
    return shot


def phone(shot, screen_width, bezel):
    height = round(shot.height * screen_width / shot.width)
    radius = round(165 * screen_width / shot.width)
    shot = shot.resize((screen_width, height), Image.Resampling.LANCZOS)
    frame = Image.new("RGBA", (screen_width + bezel * 2, height + bezel * 2), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle(
        [0, 0, frame.width - 1, frame.height - 1], radius + bezel,
        fill=BEZEL, outline=BEZEL_EDGE, width=max(2, bezel // 8),
    )
    frame.paste(shot, (bezel, bezel), rounded_mask(shot.size, radius))
    return frame


def paste_with_shadow(canvas, item, pos, blur):
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    alpha = item.split()[3].point(lambda a: 150 if a else 0)
    shadow_shape = Image.new("RGBA", item.size, (0, 0, 0, 255))
    shadow.paste(shadow_shape, (pos[0], pos[1] + blur // 2), alpha)
    shadow = shadow.filter(ImageFilter.GaussianBlur(blur))
    canvas.paste(shadow, (0, 0), shadow)
    canvas.paste(item, pos, item)


def headline(draw, center_x, top, lines, size, label_size):
    draw.text((center_x, top), "MOUSECONTROLLER", font=font(label_size, "Semibold"), fill=ACCENT, anchor="mm")
    y = top + label_size * 2.3
    for line in lines:
        draw.text((center_x, y), line, font=font(size, "Bold"), fill=WHITE, anchor="mm")
        y += size * 1.18


# --- iPhone ----------------------------------------------------------------

IPHONE = [
    ("3_pad", True, ["Your iPhone is now", "your Mac’s trackpad"]),
    ("1_connect", False, ["Finds your Mac", "automatically"]),
    ("2_pair", False, ["Pair with a code.", "Encrypted connection."]),
    ("4_sound", False, ["Volume and music", "at your fingertips"]),
    ("6_keys", False, ["Type and use", "shortcuts on your Mac"]),
    ("7_settings", False, ["Gestures and speed,", "set your way"]),
]


def iphone_screenshot(raw_name, ripple, lines):
    W, H = 1320, 2868
    canvas = background((W, H), [60, 900, 1260, 2500]).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    headline(draw, W // 2, 150, lines, 96, 40)

    device = phone(screen(raw_name, ripple), 960, 22)
    paste_with_shadow(canvas, device, ((W - device.width) // 2, 560), 40)
    return canvas.convert("RGB")


# --- Mac -------------------------------------------------------------------

def mac_window(content_path, width_px):
    content = Image.open(content_path).convert("RGB")
    points_w = 520
    scale = width_px / points_w
    content = content.resize((width_px, round(content.height * width_px / content.width)), Image.Resampling.LANCZOS)

    title_h = round(28 * scale)
    radius = round(10 * scale)
    win = Image.new("RGBA", (width_px, content.height + title_h), (0, 0, 0, 0))
    body = Image.new("RGB", win.size, (30, 30, 30))
    body.paste(content, (0, title_h))

    d = ImageDraw.Draw(body)
    d.rectangle([0, 0, width_px, title_h], fill=(42, 42, 44))
    d.line([0, title_h - 1, width_px, title_h - 1], fill=(20, 20, 20), width=max(1, round(scale / 2)))
    for i, color in enumerate([(255, 95, 87), (254, 188, 46), (40, 200, 64)]):
        cx = round((20 + i * 20) * scale)
        r = round(6 * scale)
        cy = title_h // 2
        d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=color)
    d.text((width_px // 2, title_h // 2), "MouseController", font=font(round(13 * scale), "Semibold"),
           fill=(200, 200, 204), anchor="mm")

    win.paste(body, (0, 0), rounded_mask(win.size, radius))
    ImageDraw.Draw(win).rounded_rectangle([0, 0, win.width - 1, win.height - 1], radius,
                                          outline=(80, 80, 84), width=max(2, round(scale / 2)))
    return win


MAC = [
    ("3_pad", True, ["Your iPhone becomes your Mac’s trackpad"]),
    ("2_pair", False, ["Pair in seconds with a code"]),
    ("4_sound", False, ["Volume, music and shortcuts from your phone"]),
]


def mac_screenshot(raw_name, ripple, lines):
    W, H = 2880, 1800
    canvas = background((W, H), [300, 400, 2600, 1800]).convert("RGBA")
    draw = ImageDraw.Draw(canvas)
    headline(draw, W // 2, 130, lines, 104, 40)

    window = mac_window(os.path.join(RAW, "mac_window.png"), 1560)
    paste_with_shadow(canvas, window, (230, 640), 50)

    device = phone(screen(raw_name, ripple), 590, 16)
    paste_with_shadow(canvas, device, (W - device.width - 300, 390), 40)
    return canvas.convert("RGB")


# App Store Connect asks for different iPhone sizes depending on the slot:
# 6.9" (1320x2868) and 6.1"/6.3" "medium display" (1206x2622). Both have
# the same aspect ratio, so the medium set is a straight resize.
IPHONE_SIZES = {"iphone_6.9in": (1320, 2868), "iphone_6.3in": (1206, 2622)}

os.makedirs(OUT, exist_ok=True)
for folder in IPHONE_SIZES:
    os.makedirs(os.path.join(OUT, folder), exist_ok=True)
for i, (name, ripple, lines) in enumerate(IPHONE, 1):
    shot = iphone_screenshot(name, ripple, lines)
    for folder, size in IPHONE_SIZES.items():
        shot.resize(size, Image.Resampling.LANCZOS).save(os.path.join(OUT, folder, f"iphone_{i}.png"))
for i, (name, ripple, lines) in enumerate(MAC, 1):
    mac_screenshot(name, ripple, lines).save(os.path.join(OUT, f"mac_{i}.png"))
print("saved to", OUT)
