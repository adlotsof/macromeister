"""Compose Play Store assets from emulator screenshots.

Outputs into play_store/:
  feature_graphic.png   1024x500 (Play requirement)
  icon_512.png          512x512 listing icon
  framed/sN_*.png       1080x1920 framed screenshots (Play aspect limit 9:16)
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import os

BASE = os.path.dirname(os.path.abspath(__file__))
OUT = os.path.join(BASE, "framed")
os.makedirs(OUT, exist_ok=True)

GREEN = (46, 204, 113)
GREEN_HI = (80, 230, 150)
BG0 = (12, 14, 18)
BG1 = (22, 26, 33)
TEXT = (235, 240, 245)
DIM = (150, 158, 170)

F_BOLD = "/System/Library/Fonts/SFNS.ttf"


def font(size, bold=True):
    return ImageFont.truetype(F_BOLD, size)


def gradient_bg(w, h, glow_center=None, glow_radius=500):
    img = Image.new("RGB", (w, h), BG0)
    d = ImageDraw.Draw(img)
    # subtle vertical gradient
    for y in range(h):
        t = y / h
        c = tuple(int(BG0[i] + (BG1[i] - BG0[i]) * t) for i in range(3))
        d.line([(0, y), (w, y)], fill=c)
    # green glow
    if glow_center:
        glow = Image.new("L", (w, h), 0)
        gd = ImageDraw.Draw(glow)
        cx, cy = glow_center
        gd.ellipse([cx - glow_radius, cy - glow_radius, cx + glow_radius, cy + glow_radius],
                   fill=38)
        glow = glow.filter(ImageFilter.GaussianBlur(120))
        tint = Image.new("RGB", (w, h), (20, 90, 55))
        img = Image.composite(Image.blend(img, tint, 0.5), img, glow)
    return img


def rounded(im, radius):
    mask = Image.new("L", im.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, im.size[0] - 1, im.size[1] - 1],
                                           radius=radius, fill=255)
    out = Image.new("RGBA", im.size)
    out.paste(im, (0, 0), mask)
    return out


def phone_frame(im, target_w, corner=48):
    """Dark phone bezel around a screenshot; returns RGBA."""
    s = target_w / im.size[0]
    shot = im.resize((target_w, int(im.size[1] * s)), Image.LANCZOS)
    shot = rounded(shot, corner)
    pad = 14
    w, h = shot.size[0] + pad * 2, shot.size[1] + pad * 2
    bezel = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bd = ImageDraw.Draw(bezel)
    bd.rounded_rectangle([0, 0, w - 1, h - 1], radius=corner + pad,
                         fill=(32, 36, 44, 255), outline=(70, 78, 92, 255), width=2)
    bezel.paste(shot, (pad, pad), shot)
    return bezel


def framed_shot(src, caption, out_name, accent_sub=None):
    W, H = 1080, 1920
    bg = gradient_bg(W, H, glow_center=(W // 2, int(H * 0.55)))
    d = ImageDraw.Draw(bg)
    # caption
    f1 = font(76)
    tw = d.textlength(caption, font=f1)
    d.text(((W - tw) / 2, 130), caption, font=f1, fill=TEXT)
    y = 130 + 100
    if accent_sub:
        f2 = font(44)
        sw = d.textlength(accent_sub, font=f2)
        d.text(((W - sw) / 2, y + 10), accent_sub, font=f2, fill=GREEN_HI)
        y += 80
    # phone
    screen = Image.open(src).convert("RGB")
    target_w = 700
    frame = phone_frame(screen, target_w)
    # shadow under phone
    sh = Image.new("RGBA", (frame.size[0] + 80, 60), (0, 0, 0, 0))
    ImageDraw.Draw(sh).ellipse([40, 0, sh.size[0] - 40, 60], fill=(0, 0, 0, 110))
    sh = sh.filter(ImageFilter.GaussianBlur(18))
    bg.paste(sh, ((W - sh.size[0]) // 2, H - 250), sh)
    bg.paste(frame, ((W - frame.size[0]) // 2, y + 60), frame)
    bg.convert("RGB").save(os.path.join(OUT, out_name), quality=95)
    print("wrote", out_name)


# ---- screenshots ----
S = os.path.join(BASE, "screens")
framed_shot(os.path.join(S, "1_dashboard.png"), "Know what's left, today",
            "s1_dashboard.png", "Adaptive daily calorie target")
framed_shot(os.path.join(S, "2_log.png"), "Log every meal in seconds",
            "s2_log.png", "Breakfast, lunch, dinner, snacks")
framed_shot(os.path.join(S, "3_quickadd.png"), "Quick add, search, barcodes",
            "s3_quickadd.png", "Or just describe it — AI estimates it")
framed_shot(os.path.join(S, "3_program.png"), "A program that adapts to you",
            "s4_program.png", "Coach-adjusted targets after every check-in")
framed_shot(os.path.join(S, "4_more.png"), "Your data, under your control",
            "s5_more.png", "Recipes, habits, backups and exports")

# ---- feature graphic 1024x500 ----
W, H = 1024, 500
bg = gradient_bg(W, H, glow_center=(760, 260), glow_radius=280)
d = ImageDraw.Draw(bg)
# kcal ring motif right side
cx, cy, r = 790, 250, 150
ring_bg = Image.new("RGBA", (W, H), (0, 0, 0, 0))
rd = ImageDraw.Draw(ring_bg)
rd.arc([cx - r, cy - r, cx + r, cy + r], 0, 360, fill=(38, 46, 58, 255), width=26)
rd.arc([cx - r, cy - r, cx + r, cy + r], -90, 125, fill=GREEN + (255,), width=26)
d.text((cx - 62, cy - 46), "1421", font=font(64), fill=TEXT)
d.text((cx - 46, cy + 26), "kcal left", font=font(30), fill=DIM)
bg = Image.alpha_composite(bg.convert("RGBA"), ring_bg)
d = ImageDraw.Draw(bg)
# title + tagline
d.text((70, 150), "MacroTrack", font=font(88), fill=TEXT)
d.text((74, 268), "Calorie & macro tracking", font=font(40), fill=GREEN_HI)
d.text((74, 330), "with an adaptive coach", font=font(40), fill=GREEN_HI)
# macro dots
for i, (label, col) in enumerate([("P", GREEN), ("C", (96, 165, 250)), ("F", (251, 191, 36))]):
    x = 76 + i * 64
    d.ellipse([x, 402, x + 26, 428], fill=col)
    d.text((x + 32, 402), label, font=font(26), fill=DIM)
bg.convert("RGB").save(os.path.join(BASE, "feature_graphic.png"), quality=95)
print("wrote feature_graphic.png")

# ---- icon 512x512 ----
S = 512
icon = Image.new("RGB", (S, S), (14, 17, 22))
di = ImageDraw.Draw(icon)
# subtle radial glow
glow = Image.new("L", (S, S), 0)
ImageDraw.Draw(glow).ellipse([56, 56, S - 56, S - 56], fill=46)
glow = glow.filter(ImageFilter.GaussianBlur(60))
icon = Image.composite(Image.blend(icon, Image.new("RGB", (S, S), (18, 70, 45)), 0.6),
                       icon, glow)
di = ImageDraw.Draw(icon)
# ring with arc gap (matches the dashboard motif)
r = 150
cx = cy = S // 2
di.arc([cx - r, cy - r, cx + r, cy + r], 0, 360, fill=(38, 46, 58), width=40)
di.arc([cx - r, cy - r, cx + r, cy + r], -90, 110, fill=GREEN, width=40)
di.ellipse([cx - r - 40, cy - r - 40, cx + r + 40, cy + r + 40], outline=None)
# arc cap dot
import math
ang = math.radians(110 - 90)
px, py = cx + r * math.cos(ang), cy + r * math.sin(ang)
di.ellipse([px - 20, py - 20, px + 20, py + 20], fill=GREEN_HI)
icon.convert("RGB").save(os.path.join(BASE, "icon_512.png"))
print("wrote icon_512.png")
