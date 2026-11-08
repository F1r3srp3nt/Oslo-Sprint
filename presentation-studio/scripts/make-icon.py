"""Draws the Presentation Studio app icon (desktop/build/icon.png, 1024 px, and icon.icns).
The design matches the in-app logo: a cyan diamond on a midnight-navy rounded square.
Usage: python3 scripts/make-icon.py"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFilter

S = 1024
out = Path(__file__).resolve().parent.parent / 'desktop' / 'build'
out.mkdir(parents=True, exist_ok=True)

def lerp(a, b, t):
    return tuple(int(a[i] + (b[i] - a[i]) * t) for i in range(3))

# macOS icon grid: 824 px body centred in 1024 px, corner radius ~185 px.
body = Image.new('RGBA', (S, S), (0, 0, 0, 0))
grad = Image.new('RGBA', (S, S))
gd = ImageDraw.Draw(grad)
for y in range(S):
    gd.line([(0, y), (S, y)], fill=lerp((15, 42, 82), (6, 13, 28), y / S) + (255,))
mask = Image.new('L', (S, S), 0)
ImageDraw.Draw(mask).rounded_rectangle([100, 100, 924, 924], radius=185, fill=255)
body.paste(grad, (0, 0), mask)

# Soft shadow under the body.
shadow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
ImageDraw.Draw(shadow).rounded_rectangle([100, 118, 924, 942], radius=185, fill=(0, 0, 0, 110))
shadow = shadow.filter(ImageFilter.GaussianBlur(18))
icon = Image.alpha_composite(shadow, body)

# A slide outline behind the diamond.
d = ImageDraw.Draw(icon)
d.rounded_rectangle([250, 300, 774, 600], radius=26, outline=(103, 232, 249, 90), width=10)
d.line([(300, 660), (724, 660)], fill=(103, 232, 249, 70), width=12)
d.line([(360, 708), (664, 708)], fill=(103, 232, 249, 50), width=12)

# Glowing cyan diamond.
cx, cy, r = 512, 450, 190
diamond = [(cx, cy - r), (cx + r * 0.82, cy), (cx, cy + r), (cx - r * 0.82, cy)]
glow = Image.new('RGBA', (S, S), (0, 0, 0, 0))
ImageDraw.Draw(glow).polygon(diamond, fill=(34, 211, 238, 200))
glow = glow.filter(ImageFilter.GaussianBlur(40))
icon = Image.alpha_composite(icon, glow)
d = ImageDraw.Draw(icon)
d.polygon(diamond, fill=(34, 211, 238, 255))
d.polygon([(cx, cy - r), (cx + r * 0.82, cy), (cx, cy)], fill=(103, 232, 249, 255))  # light facet
d.polygon([(cx, cy), (cx - r * 0.82, cy), (cx, cy + r)], fill=(14, 165, 199, 255))  # dark facet

icon.save(out / 'icon.png')
icon.save(out / 'icon.icns', sizes=[(16, 16), (32, 32), (64, 64), (128, 128), (256, 256), (512, 512), (1024, 1024)])
print('wrote', out / 'icon.png', out / 'icon.icns')
