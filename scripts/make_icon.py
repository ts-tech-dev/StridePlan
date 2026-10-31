#!/usr/bin/env python3
"""Generates the placeholder app icon (1024×1024). Requires Pillow."""
import os
from PIL import Image, ImageDraw

S = 1024
out = os.path.join(os.path.dirname(__file__), "..", "StridePlan", "Resources", "Assets.xcassets", "AppIcon.appiconset", "AppIcon.png")

img = Image.new("RGB", (S, S))
top, bottom = (255, 92, 41), (255, 150, 52)
px = img.load()
for y in range(S):
    for x in range(S):
        t = (x + y) / (2 * S)
        px[x, y] = tuple(int(top[i] + (bottom[i] - top[i]) * t) for i in range(3))

d = ImageDraw.Draw(img)
white = (255, 255, 255)
# Forward chevron
w = 120
d.polygon([(330, 250), (330 + w, 250), (690 + w // 2, 512), (330 + w, 774), (330, 774), (690 - w // 2, 512)], fill=white)
# Speed lines
for i, y in enumerate((390, 512, 634)):
    length = 150 - abs(i - 1) * 50
    d.rounded_rectangle([170 - length + 150, y - 22, 300, y + 22], radius=22, fill=(255, 255, 255))
img.save(out)
print("wrote", out)
