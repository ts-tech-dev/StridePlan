#!/usr/bin/env python3
"""Generates Resources/GPX/SampleRun.gpx: a ~6 km park loop at 1 Hz with pace changes and some noisy fixes."""
import math, os, random
from datetime import datetime, timedelta, timezone

random.seed(7)
out = os.path.join(os.path.dirname(__file__), "..", "StridePlan", "Resources", "GPX", "SampleRun.gpx")
center_lat, center_lon = 51.5073, -0.1657
r_lat, r_lon = 0.0060, 0.0098            # ellipse ≈ 4.2 km around
start = datetime(2026, 1, 1, 7, 0, 0, tzinfo=timezone.utc)

def pace_at(t):
    # 10 min easy, then 6 × (90 s fast / 90 s jog), then easy.
    if t < 600: return 380
    if t < 600 + 6 * 180: return 270 if (t - 600) % 180 < 90 else 420
    return 375

lines = ['<?xml version="1.0" encoding="UTF-8"?>',
         '<gpx version="1.1" creator="StridePlan sample" xmlns="http://www.topografix.com/GPX/1/1">',
         '<trk><name>Sample Run</name><trkseg>']
angle, t, meters = 0.0, 0, 0.0
circumference = 4200.0
while meters < 6200:
    speed = 1000 / pace_at(t)
    meters += speed
    angle = meters / circumference * 2 * math.pi
    lat = center_lat + r_lat * math.sin(angle) + random.gauss(0, 0.000012)
    lon = center_lon + r_lon * math.cos(angle) + random.gauss(0, 0.000018)
    hdop = 1.0
    if random.random() < 0.01:          # occasional bad fix that the tracker should reject
        lat += 0.0012; hdop = 12.0
    ts = (start + timedelta(seconds=t)).strftime("%Y-%m-%dT%H:%M:%SZ")
    lines.append(f'<trkpt lat="{lat:.6f}" lon="{lon:.6f}"><ele>{22 + 4 * math.sin(angle * 2):.1f}</ele>'
                 f'<time>{ts}</time><hdop>{hdop}</hdop></trkpt>')
    t += 1
lines += ['</trkseg></trk>', '</gpx>']
os.makedirs(os.path.dirname(out), exist_ok=True)
open(out, "w").write("\n".join(lines) + "\n")
print(f"wrote {out}: {t} points, {meters/1000:.2f} km")
