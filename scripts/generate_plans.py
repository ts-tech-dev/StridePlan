#!/usr/bin/env python3
"""
Authoring helper for the bundled plan catalog.

The app only reads the JSON in StridePlan/Resources/Plans. This script is a convenience for
writing those files consistently and checking training-load rules:
  * weekly volume never rises more than 10% above the previous peak week
  * a cutback week at least every 4 weeks (before the taper)
  * roughly 80% of running time at easy/recovery effort
  * race plans taper into a final race

Usage:  python3 scripts/generate_plans.py            # writes JSON + prints a load report
        python3 scripts/generate_plans.py --check    # only validates, writes nothing
Hand-written plans can live alongside generated ones; this script only overwrites files it owns.
"""
import json
import os
import sys

OUT = os.path.join(os.path.dirname(__file__), "..", "StridePlan", "Resources", "Plans")

# Rough paces (sec/km) used only for the load report.
REPORT_PACE = {"walk": 600, "recovery": 420, "easy": 380, "steady": 330, "tempo": 310,
               "threshold": 300, "interval": 280, "repetition": 265, "race": 320}
EASY_ZONES = {"walk", "recovery", "easy"}

# ---------------------------------------------------------------------------
# Step + workout builders
# ---------------------------------------------------------------------------

def t(seconds):
    return {"type": "time", "value": seconds}

def d(meters):
    return {"type": "distance", "value": meters}

def step(kind, duration, zone, note=None):
    s = {"kind": kind, "duration": duration, "zone": zone}
    if note:
        s["note"] = note
    return s

def rep(count, steps):
    return {"kind": "repeat", "count": count, "steps": steps}

def fmt_km(km):
    return f"{km:g} km"

def workout(wid, wtype, title, steps, notes, long_run=False):
    w = {"id": wid, "type": wtype, "title": title}
    if long_run:
        w["isLongRun"] = True
    w["notes"] = notes
    w["steps"] = steps
    return w

def easy(wid, km, notes="Conversational pace — you should be able to speak in full sentences."):
    return workout(wid, "easy", f"Easy {fmt_km(km)}", [step("run", d(km * 1000), "easy")], notes)

def easy_strides(wid, km, strides=6):
    return workout(wid, "easy", f"Easy {fmt_km(km)} + strides", [
        step("run", d(km * 1000), "easy"),
        rep(strides, [step("run", t(20), "repetition", "Smooth, quick stride — not a sprint"),
                      step("recover", t(60), "walk")]),
    ], "Easy running finished with relaxed strides to keep your legs quick and your form tidy.")

def recovery(wid, km):
    return workout(wid, "recovery", f"Recovery {fmt_km(km)}", [step("run", d(km * 1000), "recovery")],
                   "Keep this genuinely slow. The goal is blood flow, not fitness — slower than you think.")

def long_run(wid, km, finish_km=0, finish_zone="steady", notes=None):
    if finish_km:
        steps = [step("run", d((km - finish_km) * 1000), "easy"),
                 step("run", d(finish_km * 1000), finish_zone, f"Finish at {finish_zone} effort")]
        title = f"Long Run {fmt_km(km)} ({finish_km:g} fast finish)"
        notes = notes or ("Start relaxed and finish strong. Practising race-pace running on tired legs "
                          "builds confidence and teaches pacing discipline.")
    else:
        steps = [step("run", d(km * 1000), "easy")]
        title = f"Long Run {fmt_km(km)}"
        notes = notes or ("The cornerstone of your week. Keep it easy, fuel and hydrate as you would on "
                          "race day, and focus on time on your feet.")
    return workout(wid, "long", title, steps, notes, long_run=True)

def tempo(wid, minutes, zone="tempo", wu=600, cd=600, blocks=1, block_rest=120):
    main = step("run", t(minutes * 60), zone) if blocks == 1 else rep(blocks, [
        step("run", t(minutes * 60), zone), step("recover", t(block_rest), "recovery")])
    title = f"Tempo {minutes} min" if blocks == 1 else f"{blocks} × {minutes} min {zone.capitalize()}"
    notes = ("Comfortably hard: you could say a few words, but not hold a conversation. Tempo running "
             "raises the pace you can hold before fatigue builds up.") if zone == "tempo" else (
            "Threshold work at a hard-but-controlled effort. Even pacing matters more than speed — "
            "the last rep should feel like the first.")
    return workout(wid, "tempo", title, [
        step("warmup", t(wu), "easy"), main, step("cooldown", t(cd), "easy")], notes)

def intervals(wid, reps, meters, zone="interval", recover=90, wu=600, cd=600):
    rec_zone = "recovery" if recover >= 60 else "walk"
    return workout(wid, "intervals", f"{reps} × {meters} m", [
        step("warmup", t(wu), "easy"),
        rep(reps, [step("run", d(meters), zone), step("recover", t(recover), rec_zone)]),
        step("cooldown", t(cd), "easy"),
    ], ("Short, fast repetitions with full control. These develop your aerobic ceiling and running "
        "economy. Jog the recoveries gently and keep every rep at the same pace."))

def time_intervals(wid, reps, seconds, zone="interval", recover=120, wu=600, cd=600):
    label = f"{seconds // 60} min" if seconds % 60 == 0 else f"{seconds} s"
    return workout(wid, "intervals", f"{reps} × {label}", [
        step("warmup", t(wu), "easy"),
        rep(reps, [step("run", t(seconds), zone), step("recover", t(recover), "recovery")]),
        step("cooldown", t(cd), "easy"),
    ], "Hard efforts with equal focus on relaxed shoulders and quick feet. Recover fully between reps.")

def hills(wid, reps, seconds=60, wu=900, cd=600):
    return workout(wid, "hills", f"{reps} × {seconds} s Hills", [
        step("warmup", t(wu), "easy"),
        rep(reps, [step("run", t(seconds), "interval", "Drive the arms, tall posture"),
                   step("recover", t(seconds + 30), "recovery", "Jog back down")]),
        step("cooldown", t(cd), "easy"),
    ], ("Find a steady incline. Hill reps build strength and power with less impact than flat speed "
        "work. Effort hard, not all-out."))

def fartlek(wid, reps, on=60, off=90, wu=600, cd=600):
    return workout(wid, "fartlek", f"Fartlek {reps} × {on} s", [
        step("warmup", t(wu), "easy"),
        rep(reps, [step("run", t(on), "tempo"), step("recover", t(off), "easy")]),
        step("cooldown", t(cd), "easy"),
    ], "Speed play: surge, then settle. Don't chase exact paces — run by feel and enjoy the variety.")

def progression(wid, km):
    third = round(km / 3, 1)
    last = round(km - 2 * third, 1)
    return workout(wid, "progression", f"Progression {fmt_km(km)}", [
        step("run", d(third * 1000), "easy"),
        step("run", d(third * 1000), "steady"),
        step("run", d(last * 1000), "tempo"),
    ], "Start easy and get gradually faster each third. A great way to practise finishing strong.")

def run_walk(wid, reps, run_s, walk_s, title=None):
    def label(s):
        return f"{s // 60} min" if s % 60 == 0 else f"{s} s"
    return workout(wid, "easy", title or f"Run {label(run_s)} / Walk {label(walk_s)} × {reps}", [
        step("warmup", t(300), "walk", "Brisk walk to warm up"),
        rep(reps, [step("run", t(run_s), "easy"), step("walk", t(walk_s), "walk")]),
        step("cooldown", t(300), "walk"),
    ], ("Run at a gentle, conversational jog and walk briskly in between. Finishing every interval "
        "matters far more than speed."))

def continuous(wid, minutes, title=None):
    return workout(wid, "easy", title or f"Run {minutes} min", [
        step("warmup", t(300), "walk", "Brisk walk to warm up"),
        step("run", t(minutes * 60), "easy"),
        step("cooldown", t(300), "walk"),
    ], "One continuous easy run. Slow down as much as you need to keep going — walking breaks are fine.")

def cross(wid, minutes):
    return workout(wid, "crossTrain", f"Cross-train {minutes} min", [],
                   "Optional low-impact cardio: cycling, swimming, elliptical or a brisk walk. Easy effort.")

RACE_NAMES = {5000: "5K", 10000: "10K", 21097.5: "Half Marathon", 42195: "Marathon"}

def race(wid, meters, title=None):
    name = RACE_NAMES[meters]
    return workout(wid, "race", title or f"Race Day: {name}", [
        step("warmup", t(600), "easy", "Gentle jog and a few strides") if meters <= 10000 else
        step("warmup", t(300), "easy", "Walk and jog lightly"),
        step("run", d(meters), "race"),
    ], (f"This is what you trained for. Start controlled, settle into goal pace, and save something "
        f"for the last part. Enjoy your {name}!"))

def race_cooldown_free(wid, meters, title):
    return workout(wid, "race", title, [step("run", d(meters), "race")],
                   "Run the full distance at a comfortable, steady effort. You've earned this!")

# ---------------------------------------------------------------------------
# Plans
# ---------------------------------------------------------------------------

def plan(pid, title, goal, level, rpw, desc, phases, weeks):
    return {"id": pid, "title": title, "goal": goal, "level": level, "weeks": len(weeks),
            "runsPerWeek": {"min": rpw[0], "max": rpw[1]}, "description": desc,
            "phases": [{"name": n, "weeks": [a, b]} for n, a, b in phases],
            "schedule": [{"week": i + 1, "workouts": w} for i, w in enumerate(weeks)]}

def W(n):
    """Prefix helper: W(3)('easy-1') -> 'w3-easy-1'."""
    return lambda s: f"w{n}-{s}"


def couch_to_5k():
    progression_ = [  # (reps, run, walk) per week; three sessions each
        [(8, 60, 90)] * 3,
        [(6, 90, 120)] * 3,
        [(4, 180, 90), (4, 180, 90), (5, 150, 90)],
        [(3, 300, 150), (3, 300, 150), (3, 300, 120)],
        [(3, 300, 120), (2, 480, 300), None],   # None → continuous 20 min
        [(2, 600, 180), (2, 600, 120), "c22"],
        ["c25", "c25", "c25"],
        ["c28", "c28", "c28"],
        ["c30", "c20", "race"],
    ]
    weeks = []
    for i, sessions in enumerate(progression_):
        w = W(i + 1)
        out = []
        for j, s in enumerate(sessions):
            sid = w(f"run-{j + 1}")
            if s is None:
                out.append(continuous(sid, 20, "First 20-minute run"))
            elif s == "race":
                out.append(race_cooldown_free(w("5k"), 5000, "Your First 5K"))
            elif isinstance(s, str):
                out.append(continuous(sid, int(s[1:])))
            else:
                out.append(run_walk(sid, *s))
        weeks.append(out)
    return plan("couch-to-5k-beginner-9w", "Couch to 5K", "couchTo5K", "beginner", (3, 3),
                "From your first steps to running 5K without stopping. Gentle run/walk intervals "
                "that grow a little every week.",
                [("Foundation", 1, 3), ("Build", 4, 7), ("Finish", 8, 9)], weeks)


def five_k_beginner():
    spec = [  # (easy, quality, long)
        (3, ("fartlek", 6), 4), (3, ("fartlek", 8), 4.5), (3.5, ("hills", 5), 5), (3, ("fartlek", 6), 4),
        (4, ("tempo", 12), 5.5), (4, ("intervals", 6, 400), 6), (3.5, ("tempo", 15), 5), (3, ("intervals", 4, 400), None),
    ]
    weeks = []
    for i, (e, q, lr) in enumerate(spec):
        w = W(i + 1)
        wk = [easy(w("easy"), e), quality(w, q)]
        wk.append(long_run(w("long"), lr) if lr else race(w("race"), 5000))
        weeks.append(wk)
    return plan("5k-beginner-8w", "5K – Beginner", "fiveK", "beginner", (3, 3),
                "Three runs a week to take you from running regularly to a confident, well-paced 5K.",
                [("Base", 1, 4), ("Build", 5, 7), ("Taper", 8, 8)], weeks)


def quality(w, q):
    kind = q[0]
    if kind == "fartlek":
        return fartlek(w("fartlek"), q[1])
    if kind == "hills":
        return hills(w("hills"), q[1])
    if kind == "tempo":
        return tempo(w("tempo"), q[1])
    if kind == "threshold":
        return tempo(w("threshold"), q[1], zone="threshold", blocks=q[2] if len(q) > 2 else 1)
    if kind == "intervals":
        return intervals(w("intervals"), q[1], q[2], zone=q[3] if len(q) > 3 else "interval",
                         recover=q[4] if len(q) > 4 else 90)
    if kind == "time_intervals":
        return time_intervals(w("intervals"), q[1], q[2])
    if kind == "progression":
        return progression(w("progression"), q[1])
    raise ValueError(kind)


def generic_race_plan(pid, title, goal, level, rpw, desc, phases, race_m, spec):
    """spec rows: dict(easy=[km...], q=[quality...], long=km or (km, finish_km, zone), rec=km)"""
    weeks = []
    for i, row in enumerate(spec):
        w = W(i + 1)
        wk = []
        for j, km in enumerate(row.get("easy", [])):
            wk.append(easy(w(f"easy-{j + 1}"), km))
        if "strides" in row:
            wk.append(easy_strides(w("strides"), row["strides"]))
        if "rec" in row:
            wk.append(recovery(w("recovery"), row["rec"]))
        for q in row.get("q", []):
            wk.append(quality(w, q))
        if "cross" in row:
            wk.append(cross(w("cross"), row["cross"]))
        lr = row.get("long")
        if lr == "race":
            wk.append(race(w("race"), race_m))
        elif isinstance(lr, tuple):
            wk.append(long_run(w("long"), lr[0], lr[1], lr[2]))
        elif lr:
            wk.append(long_run(w("long"), lr))
        weeks.append(wk)
    return plan(pid, title, goal, level, rpw, desc, phases, weeks)


def five_k_intermediate():
    s = [
        dict(easy=[5, 5], q=[("fartlek", 8)], long=7),
        dict(easy=[5], strides=5, q=[("intervals", 6, 400)], long=7.5),
        dict(easy=[5.5], strides=5, q=[("tempo", 15)], long=8),
        dict(easy=[4, 4], q=[("fartlek", 6)], long=6.5),
        dict(easy=[6], strides=5, q=[("intervals", 8, 400)], long=8.5),
        dict(easy=[6], strides=5.5, q=[("tempo", 20)], long=9),
        dict(easy=[6], strides=5.5, q=[("intervals", 5, 800, "interval", 120)], long=9),
        dict(easy=[4], strides=4, q=[("intervals", 4, 400)], long="race"),
    ]
    return generic_race_plan("5k-intermediate-8w", "5K – Intermediate", "fiveK", "intermediate", (4, 4),
                             "Sharpen your 5K with classic track intervals, tempo runs and a solid aerobic base.",
                             [("Base", 1, 4), ("Build", 5, 7), ("Taper", 8, 8)], 5000, s)


def five_k_advanced():
    s = [
        dict(easy=[8, 7], rec=5, q=[("intervals", 8, 400, "interval", 75)], long=12),
        dict(easy=[8, 8], rec=5, q=[("threshold", 8, 3)], long=13),
        dict(easy=[8, 8], rec=6, q=[("intervals", 6, 800, "interval", 120)], long=14),
        dict(easy=[7, 6], rec=5, q=[("fartlek", 10)], long=11),
        dict(easy=[9, 8], rec=6, q=[("intervals", 5, 1000, "interval", 150)], long=14),
        dict(easy=[9, 8], rec=6, q=[("intervals", 12, 400, "repetition", 90)], long=15),
        dict(easy=[9, 8], rec=6, q=[("threshold", 10, 3)], long=15),
        dict(easy=[6, 6], rec=4, q=[("intervals", 6, 400, "interval", 90)], long="race"),
    ]
    return generic_race_plan("5k-advanced-8w", "5K – Advanced", "fiveK", "advanced", (5, 5),
                             "High-quality speed work for experienced racers chasing a new 5K personal best.",
                             [("Base", 1, 4), ("Peak", 5, 7), ("Taper", 8, 8)], 5000, s)


def ten_k_beginner():
    s = [
        dict(easy=[4], q=[("fartlek", 6)], long=5),
        dict(easy=[4], q=[("fartlek", 8)], long=6),
        dict(easy=[4.5], q=[("hills", 6)], long=6.5),
        dict(easy=[4], q=[("fartlek", 6)], long=5),
        dict(easy=[5], q=[("tempo", 15)], long=7),
        dict(easy=[5], q=[("intervals", 6, 400)], long=8),
        dict(easy=[5], q=[("tempo", 20)], long=9),
        dict(easy=[4], q=[("fartlek", 6)], long=7),
        dict(easy=[5], q=[("intervals", 5, 800, "interval", 120)], long=9),
        dict(easy=[4], q=[("tempo", 10)], long="race"),
    ]
    return generic_race_plan("10k-beginner-10w", "10K – Beginner", "tenK", "beginner", (3, 3),
                             "Step up from 5K to 10K with three runs a week and gentle introductions to faster running.",
                             [("Base", 1, 4), ("Build", 5, 9), ("Taper", 10, 10)], 10000, s)


def ten_k_intermediate():
    s = [
        dict(easy=[5, 5], q=[("fartlek", 8)], long=9),
        dict(easy=[6], strides=5, q=[("tempo", 15)], long=10),
        dict(easy=[5.5], strides=5, q=[("intervals", 6, 800, "interval", 120)], long=10),
        dict(easy=[5, 4], q=[("fartlek", 8)], long=8),
        dict(easy=[6.5], strides=5.5, q=[("tempo", 20)], long=12),
        dict(easy=[6.5], strides=5.5, q=[("intervals", 5, 1000, "interval", 150)], long=12),
        dict(easy=[7], strides=6, q=[("threshold", 10, 2)], long=13),
        dict(easy=[5, 5], q=[("hills", 8)], long=10),
        dict(easy=[7], strides=6, q=[("intervals", 6, 1000, "interval", 120)], long=13),
        dict(easy=[5], strides=4, q=[("tempo", 12)], long="race"),
    ]
    return generic_race_plan("10k-intermediate-10w", "10K – Intermediate", "tenK", "intermediate", (4, 4),
                             "Four runs a week mixing tempo, kilometre repeats and steady long runs for a faster 10K.",
                             [("Base", 1, 4), ("Build", 5, 9), ("Taper", 10, 10)], 10000, s)


def ten_k_advanced():
    s = [
        dict(easy=[9, 8], rec=6, q=[("threshold", 10, 3)], long=15),
        dict(easy=[9, 9], rec=6, q=[("intervals", 6, 1000, "interval", 120)], long=16),
        dict(easy=[10, 9], rec=6, q=[("threshold", 12, 3)], long=17),
        dict(easy=[8, 7], rec=5, q=[("fartlek", 10)], long=13),
        dict(easy=[10, 9], rec=7, q=[("intervals", 5, 1600, "interval", 150)], long=18),
        dict(easy=[10, 10], rec=7, q=[("threshold", 15, 2)], long=18),
        dict(easy=[10, 10], rec=7, q=[("intervals", 8, 1000, "interval", 90)], long=19),
        dict(easy=[7, 6], rec=5, q=[("tempo", 15)], long="race"),
    ]
    return generic_race_plan("10k-advanced-8w", "10K – Advanced", "tenK", "advanced", (5, 5),
                             "Threshold-heavy training for seasoned runners targeting a 10K personal best.",
                             [("Base", 1, 4), ("Peak", 5, 7), ("Taper", 8, 8)], 10000, s)


def half_beginner():
    s = [
        dict(easy=[4, 4], long=6),
        dict(easy=[4, 4], long=7),
        dict(easy=[4, 4.5], long=8),
        dict(easy=[4, 4], long=6),
        dict(easy=[4.5], q=[("fartlek", 6)], long=8),
        dict(easy=[5], q=[("tempo", 15)], long=9),
        dict(easy=[5], q=[("hills", 6)], long=10),
        dict(easy=[4, 4], long=8),
        dict(easy=[5], q=[("tempo", 20)], long=12),
        dict(easy=[4], q=[("fartlek", 8)], long=15),
        dict(easy=[4], q=[("tempo", 15)], long=10),
        dict(easy=[4], q=[("tempo", 10)], long="race"),
    ]
    return generic_race_plan("half-marathon-beginner-12w", "Half Marathon – Beginner", "halfMarathon", "beginner", (3, 4),
                             "Your first 21.1 km. Patient long-run progression with just enough quality to feel strong on race day.",
                             [("Base", 1, 4), ("Build", 5, 10), ("Taper", 11, 12)], 21097.5, s)


def half_intermediate():
    s = [
        dict(easy=[6, 5], q=[("fartlek", 8)], long=10),
        dict(easy=[6], strides=5, q=[("tempo", 20)], long=11),
        dict(easy=[6, 5], q=[("intervals", 6, 800, "interval", 120)], long=12),
        dict(easy=[5, 5], q=[("fartlek", 6)], long=10),
        dict(easy=[7, 5], q=[("tempo", 25)], long=13),
        dict(easy=[7], strides=5, q=[("intervals", 5, 1000, "interval", 120)], long=13),
        dict(easy=[7, 6], q=[("threshold", 10, 3)], long=(16, 4, "race")),
        dict(easy=[6, 5], q=[("hills", 8)], long=12),
        dict(easy=[8, 6], q=[("tempo", 30)], long=(18, 5, "race")),
        dict(easy=[7, 6], q=[("intervals", 6, 1000, "interval", 120)], long=(16, 6, "race")),
        dict(easy=[6, 5], q=[("tempo", 20)], long=12),
        dict(easy=[5], strides=4, q=[("tempo", 10)], long="race"),
    ]
    return generic_race_plan("half-marathon-intermediate-12w", "Half Marathon – Intermediate", "halfMarathon", "intermediate", (4, 5),
                             "Build to a confident half with tempo work and progressive long runs with race-pace finishes.",
                             [("Base", 1, 4), ("Build", 5, 10), ("Taper", 11, 12)], 21097.5, s)


def half_advanced():
    s = [
        dict(easy=[9, 8], rec=6, q=[("threshold", 10, 3)], long=16),
        dict(easy=[9, 9], rec=6, q=[("intervals", 6, 1000, "interval", 120)], long=17),
        dict(easy=[10, 9], rec=6, q=[("tempo", 30)], long=18),
        dict(easy=[8, 7], rec=5, q=[("fartlek", 10)], long=14),
        dict(easy=[10, 9], rec=7, q=[("threshold", 12, 3)], long=(19, 5, "race")),
        dict(easy=[10, 10], rec=7, q=[("intervals", 5, 1600, "interval", 150)], long=20),
        dict(easy=[11, 10], rec=7, q=[("tempo", 35)], long=(21, 8, "race")),
        dict(easy=[9, 8], rec=6, q=[("hills", 10)], long=16),
        dict(easy=[11, 10], rec=7, q=[("threshold", 15, 3)], long=(22, 10, "race")),
        dict(easy=[11, 10], rec=7, q=[("intervals", 6, 1600, "interval", 120)], long=(22, 6, "race")),
        dict(easy=[11, 10], rec=7, q=[("threshold", 20, 2)], long=(23, 12, "race")),
        dict(easy=[9, 8], rec=6, q=[("intervals", 8, 1000, "interval", 90)], long=18),
        dict(easy=[8, 7], rec=5, q=[("tempo", 20)], long=14),
        dict(easy=[6, 5], rec=4, q=[("tempo", 10)], long="race"),
    ]
    return generic_race_plan("half-marathon-advanced-14w", "Half Marathon – Advanced", "halfMarathon", "advanced", (5, 5),
                             "A demanding block of threshold and race-specific long runs for experienced half marathoners.",
                             [("Base", 1, 4), ("Build", 5, 8), ("Peak", 9, 12), ("Taper", 13, 14)], 21097.5, s)


def marathon_beginner():
    s = [
        dict(easy=[5, 5, 6], long=10),
        dict(easy=[5, 5, 6], long=11),
        dict(easy=[5, 6], q=[("fartlek", 6)], long=12),
        dict(easy=[5, 5, 5], long=10),
        dict(easy=[6, 6], q=[("tempo", 15)], long=14),
        dict(easy=[6, 6], q=[("hills", 6)], long=15),
        dict(easy=[6, 7], q=[("tempo", 20)], long=17),
        dict(easy=[5, 5, 6], long=13),
        dict(easy=[6, 7], q=[("tempo", 20)], long=19),
        dict(easy=[6, 8], q=[("progression", 8)], long=21),
        dict(easy=[7, 8], q=[("tempo", 25)], long=(24, 5, "race")),
        dict(easy=[6, 6], q=[("fartlek", 8)], long=18),
        dict(easy=[7, 8], q=[("tempo", 25)], long=26),
        dict(easy=[7, 8], q=[("progression", 10)], long=(28, 6, "race")),
        dict(easy=[7, 8], q=[("tempo", 30)], long=30),
        dict(easy=[6, 7], q=[("tempo", 20)], long=22),
        dict(easy=[5, 6], q=[("tempo", 15)], long=14),
        dict(easy=[5], q=[("tempo", 10)], long="race"),
    ]
    return generic_race_plan("marathon-beginner-18w", "Marathon – Beginner", "marathon", "beginner", (4, 4),
                             "Eighteen patient weeks to your first marathon finish, built around a steadily growing long run.",
                             [("Base", 1, 4), ("Build", 5, 12), ("Peak", 13, 15), ("Taper", 16, 18)], 42195, s)


def marathon_intermediate():
    s = [
        dict(easy=[8, 7], rec=5, q=[("tempo", 20)], long=16),
        dict(easy=[8, 7], rec=5, q=[("intervals", 6, 800, "interval", 120)], long=17),
        dict(easy=[9, 8], rec=6, q=[("tempo", 25)], long=19),
        dict(easy=[7, 7], rec=5, q=[("fartlek", 8)], long=15),
        dict(easy=[9, 8], rec=6, q=[("threshold", 10, 3)], long=(21, 6, "race")),
        dict(easy=[10, 8], rec=6, q=[("intervals", 5, 1000, "interval", 120)], long=23),
        dict(easy=[10, 9], rec=6, q=[("tempo", 30)], long=(25, 8, "race")),
        dict(easy=[8, 7], rec=5, q=[("hills", 8)], long=18),
        dict(easy=[10, 9], rec=7, q=[("threshold", 12, 3)], long=(27, 10, "race")),
        dict(easy=[11, 9], rec=7, q=[("intervals", 6, 1000, "interval", 120)], long=29),
        dict(easy=[11, 10], rec=7, q=[("tempo", 35)], long=(30, 13, "race")),
        dict(easy=[9, 8], rec=6, q=[("fartlek", 10)], long=22),
        dict(easy=[11, 10], rec=7, q=[("threshold", 15, 3)], long=32),
        dict(easy=[10, 8], rec=6, q=[("tempo", 25)], long=(24, 8, "race")),
        dict(easy=[8, 7], rec=5, q=[("tempo", 20)], long=16),
        dict(easy=[6], rec=4, q=[("tempo", 10)], long="race"),
    ]
    return generic_race_plan("marathon-intermediate-16w", "Marathon – Intermediate", "marathon", "intermediate", (5, 5),
                             "For runners with a marathon or several halves behind them. Race-pace long runs and threshold work.",
                             [("Base", 1, 4), ("Build", 5, 9), ("Peak", 10, 13), ("Taper", 14, 16)], 42195, s)


def base_beginner():
    s = [
        dict(easy=[3, 3], long=4),
        dict(easy=[3, 3.5], long=4.5),
        dict(easy=[3.5, 3.5], long=5),
        dict(easy=[3, 3], long=4),
        dict(easy=[3.5, 4], long=5.5),
        dict(easy=[4], strides=3.5, long=6),
    ]
    return generic_race_plan("base-building-beginner-6w", "Base Building – Beginner", "baseBuilding", "beginner", (3, 3),
                             "Make running a habit. Easy, consistent mileage that builds durability without burnout.",
                             [("Base", 1, 6)], 0, s)


def base_intermediate():
    s = [
        dict(easy=[6, 5], strides=5, long=10),
        dict(easy=[6, 6], strides=5, long=11),
        dict(easy=[6, 6], q=[("fartlek", 8)], long=12),
        dict(easy=[5, 5], strides=5, long=9),
        dict(easy=[6], strides=5, q=[("progression", 7)], long=12),
        dict(easy=[6], strides=5, q=[("hills", 8)], long=13),
        dict(easy=[6.5], strides=5.5, q=[("fartlek", 10)], long=14),
        dict(easy=[6, 5], strides=5, long=11),
    ]
    return generic_race_plan("base-building-intermediate-8w", "General Fitness – Intermediate", "baseBuilding", "intermediate", (4, 5),
                             "Raise your aerobic engine between race blocks: mostly easy miles with light, playful speed.",
                             [("Base", 1, 4), ("Build", 5, 8)], 0, s)


PLANS = [couch_to_5k, five_k_beginner, five_k_intermediate, five_k_advanced,
         ten_k_beginner, ten_k_intermediate, ten_k_advanced,
         half_beginner, half_intermediate, half_advanced,
         marathon_beginner, marathon_intermediate,
         base_beginner, base_intermediate]

# ---------------------------------------------------------------------------
# Load report
# ---------------------------------------------------------------------------

def flatten(steps):
    for s in steps:
        if s["kind"] == "repeat":
            for _ in range(s["count"]):
                yield from flatten(s["steps"])
        else:
            yield s

def week_load(workouts):
    km = secs = easy_secs = 0.0
    for w in workouts:
        for s in flatten(w["steps"]):
            pace = REPORT_PACE[s["zone"]]
            if s["duration"]["type"] == "time":
                sec = s["duration"]["value"]; dist = sec / pace
            else:
                dist = s["duration"]["value"] / 1000; sec = dist * pace
            if s["zone"] != "walk":
                km += dist
            secs += sec
            if s["zone"] in EASY_ZONES:
                easy_secs += sec
    return km, secs, easy_secs

def report(p):
    problems = []
    peak = 0
    since_cutback = 0
    loads = []
    total = easy_total = 0
    race_week = p["schedule"][-1]["workouts"][-1]["type"] == "race"
    for wk in p["schedule"]:
        workouts = wk["workouts"]
        if race_week and wk["week"] == p["weeks"]:
            workouts = [w for w in workouts if w["type"] != "race"]
        km, secs, easy_secs = week_load(workouts)
        loads.append(km)
        total += secs; easy_total += easy_secs
        # Couch to 5K progresses by run/walk time rather than distance, so it's exempt.
        if peak and km > peak * 1.10 + 0.6 and p["goal"] != "couchTo5K":  # small slack for rounding to 0.5 km
            problems.append(f"week {wk['week']} jumps to {km:.1f} km (peak {peak:.1f})")
        if peak and km < peak * 0.9:
            since_cutback = 0
        else:
            since_cutback += 1
        if since_cutback > 4 and p["goal"] != "couchTo5K":
            problems.append(f"no cutback in the 4 weeks up to week {wk['week']}")
        peak = max(peak, km)
    easy_pct = easy_total / total * 100
    if easy_pct < 72 and p["goal"] != "couchTo5K":
        problems.append(f"only {easy_pct:.0f}% easy")
    return loads, easy_pct, problems


def main():
    check_only = "--check" in sys.argv
    os.makedirs(OUT, exist_ok=True)
    failed = False
    for fn in PLANS:
        p = fn()
        loads, easy_pct, problems = report(p)
        status = "OK " if not problems else "!! "
        print(f"{status}{p['id']:<36} {p['weeks']:>2}w  easy {easy_pct:4.0f}%  km/wk: "
              + " ".join(f"{x:.0f}" for x in loads))
        for pr in problems:
            print("     -", pr)
        failed |= bool(problems)
        if not check_only:
            with open(os.path.join(OUT, f"{p['id']}.json"), "w") as f:
                json.dump(p, f, indent=2, ensure_ascii=False)
                f.write("\n")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
