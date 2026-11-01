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
The script owns every "v2-*.json" file (stale ones are deleted). The original plans are frozen
JSON marked "retired": hidden from the catalog but still loadable for runners already on them.
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

def run_walk(wid, reps, run_s, walk_s, title=None, cooldown=300):
    def label(s):
        return f"{s // 60} min" if s % 60 == 0 else f"{s} s"
    return workout(wid, "easy", title or f"Run {label(run_s)} / Walk {label(walk_s)} × {reps}", [
        step("warmup", t(300), "walk", "Brisk walk to warm up"),
        rep(reps, [step("run", t(run_s), "easy"), step("walk", t(walk_s), "walk")]),
        step("cooldown", t(cooldown), "walk"),
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

# ---------------------------------------------------------------------------
# Plans
# ---------------------------------------------------------------------------

# Plan library v2: every plan family (goal + level) comes in several lengths. IDs carry a "v2-"
# prefix so they never collide with the original hand-written plans, which stay in the bundle
# (marked "retired") so runners already following one keep a working schedule.

ID_PREFIX = "v2-"
LENGTHS = [8, 10, 12]
MARATHON_LENGTHS = {"beginner": [16, 18], "intermediate": [12, 16, 18], "advanced": [12, 16, 18]}


def plan(pid, title, goal, level, rpw, desc, phases, weeks):
    return {"id": pid, "title": title, "goal": goal, "level": level, "weeks": len(weeks),
            "runsPerWeek": {"min": rpw[0], "max": rpw[1]}, "description": desc,
            "phases": [{"name": n, "weeks": [a, b]} for n, a, b in phases],
            "schedule": [{"week": i + 1, "workouts": w} for i, w in enumerate(weeks)]}

def W(n):
    """Prefix helper: W(3)('easy-1') -> 'w3-easy-1'."""
    return lambda s: f"w{n}-{s}"

def half_km(x):
    return max(0.5, round(x * 2) / 2)


# ---------------------------------------------------------------------------
# Couch to 5K: short run/walk sessions (about 20 minutes in week 1) that grow gently.
# Rows are (reps, run seconds, walk seconds) or "cNN" for a continuous NN-minute run.
# ---------------------------------------------------------------------------

C25K_LADDER = [
    [(6, 30, 90)] * 3,                                   # 1: 3 min running in 20 min
    [(8, 30, 90)] * 3,                                   # 2
    [(6, 60, 90)] * 3,                                   # 3
    [(7, 60, 90), (7, 60, 90), (8, 60, 90)],             # 4
    [(6, 90, 90)] * 3,                                   # 5
    [(5, 120, 90)] * 3,                                  # 6
    [(4, 180, 90)] * 3,                                  # 7
    [(4, 240, 90), (4, 240, 90), (3, 300, 120)],         # 8
    [(3, 300, 90), (3, 300, 90), (2, 480, 120)],         # 9
    [(2, 600, 120), (2, 600, 120), "c15"],               # 10
    ["c20", "c22", "c25"],                               # 11
    ["c20", "c15", "race"],                              # 12
]
C25K_ROWS = {12: list(range(12)), 10: [0, 2, 4, 5, 6, 7, 8, 9, 10, 11], 8: [0, 2, 4, 6, 8, 9, 10, 11]}
C25K_PHASES = {12: [("Foundation", 1, 4), ("Build", 5, 9), ("Finish", 10, 12)],
               10: [("Foundation", 1, 3), ("Build", 4, 8), ("Finish", 9, 10)],
               8: [("Foundation", 1, 3), ("Build", 4, 6), ("Finish", 7, 8)]}
C25K_PACE_NOTE = {
    12: "The gentlest build: ideal if you're new to exercise or returning after a long break.",
    10: "A steady build for brand-new runners.",
    8: "A quicker build if you already walk briskly for 30 minutes most days.",
}


def couch_to_5k(n):
    weeks = []
    for i, row in enumerate(C25K_ROWS[n]):
        w = W(i + 1)
        out = []
        for j, s in enumerate(C25K_LADDER[row]):
            sid = w(f"run-{j + 1}")
            if s == "race":
                out.append(workout(w("5k"), "race", "Your First 5K", [step("run", d(5000), "race")],
                                   "Run at an easy, comfortable effort. Short walk breaks are completely "
                                   "fine: finishing is the goal. You've earned this!"))
            elif isinstance(s, str):
                out.append(continuous(sid, int(s[1:])))
            else:
                out.append(run_walk(sid, *s, cooldown=180))
        weeks.append(out)
    desc = ("From your first steps to running 5K. Sessions start at about 20 minutes with 30-second "
            "jogs and grow a little each week. Repeat any week that feels hard.")
    p = plan(f"{ID_PREFIX}couch-to-5k-beginner-{n}w", "Couch to 5K", "couchTo5K", "beginner", (3, 3),
             desc, C25K_PHASES[n], weeks)
    p["fitNote"] = C25K_PACE_NOTE[n]
    return p


# ---------------------------------------------------------------------------
# Periodised plan engine for every other family.
# ---------------------------------------------------------------------------

LEVEL_SCALE = {"beginner": 0.75, "intermediate": 1.0, "advanced": 1.25}

# Per goal and level: runs/week, long run start->peak km, easy run start->peak km, recovery run km.
FAMILIES = {
    ("fiveK", "beginner"):      dict(runs=3, long=(4, 6.5), easy=(3, 4.5)),
    ("fiveK", "intermediate"):  dict(runs=4, long=(6.5, 9.5), easy=(5, 6.5)),
    ("fiveK", "advanced"):      dict(runs=5, long=(11, 15), easy=(7, 9), rec=(5, 6)),
    ("tenK", "beginner"):       dict(runs=3, long=(5, 9.5), easy=(4, 5.5)),
    ("tenK", "intermediate"):   dict(runs=4, long=(8, 13), easy=(5, 7)),
    ("tenK", "advanced"):       dict(runs=5, long=(13, 19), easy=(8, 10), rec=(5, 7)),
    ("halfMarathon", "beginner"):     dict(runs=3, long=(7, 16), easy=(4, 6)),
    ("halfMarathon", "intermediate"): dict(runs=4, long=(10, 19), easy=(5.5, 7.5)),
    ("halfMarathon", "advanced"):     dict(runs=5, long=(15, 22), easy=(9, 11), rec=(6, 7)),
    ("marathon", "beginner"):     dict(runs=4, long=(11, 30), easy=(5, 8)),
    ("marathon", "intermediate"): dict(runs=5, long=(16, 32), easy=(7, 10), rec=(5, 7)),
    ("marathon", "advanced"):     dict(runs=5, long=(19, 32), easy=(10, 13), rec=(6, 8)),
    ("baseBuilding", "beginner"):     dict(runs=3, long=(4, 7), easy=(3, 4.5)),
    ("baseBuilding", "intermediate"): dict(runs=4, long=(9, 14), easy=(5, 6.5)),
    ("baseBuilding", "advanced"):     dict(runs=5, long=(13, 18), easy=(8, 10), rec=(6, 7)),
}

GOAL_INFO = {
    "fiveK": dict(slug="5k", name="5K", race=5000, taper=1),
    "tenK": dict(slug="10k", name="10K", race=10000, taper=1),
    "halfMarathon": dict(slug="half-marathon", name="Half Marathon", race=21097.5, taper=2),
    "marathon": dict(slug="marathon", name="Marathon", race=42195, taper=3),
    "baseBuilding": dict(slug="general-fitness", name="General Fitness", race=None, taper=0),
}

DESCRIPTIONS = {
    ("fiveK", "beginner"): "Three runs a week to take you from running regularly to a confident, well-paced 5K.",
    ("fiveK", "intermediate"): "Sharpen your 5K with classic track intervals, tempo runs and a solid aerobic base.",
    ("fiveK", "advanced"): "High-quality speed work for experienced racers chasing a new 5K personal best.",
    ("tenK", "beginner"): "Step up from 5K to 10K with three runs a week and gentle introductions to faster running.",
    ("tenK", "intermediate"): "Four runs a week mixing tempo, kilometre repeats and steady long runs for a faster 10K.",
    ("tenK", "advanced"): "Threshold-heavy training for seasoned runners targeting a 10K personal best.",
    ("halfMarathon", "beginner"): "Your first 21.1 km. Patient long-run progression with just enough quality to feel strong on race day.",
    ("halfMarathon", "intermediate"): "Build to a confident half with tempo work and progressive long runs with race-pace finishes.",
    ("halfMarathon", "advanced"): "A demanding block of threshold work and race-specific long runs for experienced half marathoners.",
    ("marathon", "beginner"): "Patient weeks to your first marathon finish, built around a steadily growing long run.",
    ("marathon", "intermediate"): "For runners with a marathon or several halves behind them. Race-pace long runs and threshold work.",
    ("marathon", "advanced"): "Big weeks, marathon-pace long runs and sustained threshold work for experienced marathoners.",
    ("baseBuilding", "beginner"): "Make running a habit. Easy, consistent mileage that builds durability without burnout.",
    ("baseBuilding", "intermediate"): "Raise your aerobic engine between race blocks: mostly easy miles with light, playful speed.",
    ("baseBuilding", "advanced"): "High-volume aerobic building for experienced runners, with hills and progression runs to stay sharp.",
}

G_LONG, G_EASY = 1.10, 1.07   # max growth per progression week


def quality_menu(goal, level, phase, f, w):
    """Candidate quality sessions for a week; f is progress through the build (0..1)."""
    L = LEVEL_SCALE[level]
    n = lambda lo, hi: max(3, round((lo + (hi - lo) * f) * L))
    m = lambda lo, hi: max(8, round((lo + (hi - lo) * f) * L))
    blocks = 2 if level == "beginner" else 3
    if phase == "base" or goal == "baseBuilding":
        menu = [fartlek(w("fartlek"), n(6, 10)), hills(w("hills"), n(5, 8))]
        if goal in ("marathon", "baseBuilding", "halfMarathon"):
            menu.append(progression(w("progression"), half_km(6 + 3 * f * L)))
        return menu
    table = {
        ("fiveK", "build"): [intervals(w("intervals"), n(6, 10), 400), tempo(w("tempo"), m(12, 20)),
                             intervals(w("intervals"), n(4, 6), 800, recover=120)],
        ("fiveK", "peak"): [intervals(w("intervals"), n(3, 5), 1000, recover=150),
                            intervals(w("intervals"), n(8, 12), 400, zone="repetition"),
                            tempo(w("tempo"), m(15, 20))],
        ("tenK", "build"): [tempo(w("tempo"), m(15, 25)), intervals(w("intervals"), n(5, 7), 800, recover=120),
                            tempo(w("threshold"), m(8, 10), zone="threshold", blocks=2)],
        ("tenK", "peak"): [intervals(w("intervals"), n(4, 6), 1000, recover=120),
                           tempo(w("threshold"), m(10, 12), zone="threshold", blocks=blocks),
                           tempo(w("tempo"), m(20, 25))],
        ("halfMarathon", "build"): [tempo(w("tempo"), m(20, 30)), intervals(w("intervals"), n(4, 6), 1000, recover=120),
                                    tempo(w("threshold"), m(10, 12), zone="threshold", blocks=2)],
        ("halfMarathon", "peak"): [tempo(w("threshold"), m(10, 15), zone="threshold", blocks=blocks),
                                   tempo(w("tempo"), m(25, 35)), intervals(w("intervals"), n(3, 5), 1600, recover=150)],
        ("marathon", "build"): [tempo(w("tempo"), m(20, 30)), progression(w("progression"), half_km(8 + 4 * f * L)),
                                tempo(w("threshold"), m(10, 12), zone="threshold", blocks=2)],
        ("marathon", "peak"): [tempo(w("tempo"), m(25, 40)), tempo(w("threshold"), m(12, 15), zone="threshold", blocks=blocks),
                               progression(w("progression"), half_km(10 + 4 * f * L))],
    }
    return table[(goal, phase)]


def engine_plan(goal, level, n):
    cfg, info = FAMILIES[(goal, level)], GOAL_INFO[goal]
    taper = info["taper"]
    build = n - taper
    cutbacks = {wk for wk in range(4, build + 1, 4) if wk != build or not info["race"]}
    progress_weeks = [wk for wk in range(1, build + 1) if wk not in cutbacks]
    steps = max(1, len(progress_weeks) - 1)

    def ramp(lo, hi, g):
        start = max(lo, hi / g ** steps)
        r = (hi / start) ** (1 / steps)
        return {wk: start * r ** j for j, wk in enumerate(progress_weeks)}

    long_v = ramp(*cfg["long"], G_LONG)
    easy_v = ramp(*cfg["easy"], G_EASY)
    rec_v = ramp(*cfg["rec"], G_EASY) if "rec" in cfg else None
    fast_finish = goal in ("halfMarathon", "marathon") and level != "beginner"

    weeks, last_prog, k, peak_km, prev_long = [], progress_weeks[0], 0, 0.0, 0.0

    def render(specs):
        out = []
        for kind, wid, km in specs:
            if kind == "easy":
                out.append(easy(wid, km))
            elif kind == "strides":
                out.append(easy_strides(wid, km))
            elif kind == "recovery":
                out.append(recovery(wid, km))
            elif kind == "long_ff":
                out.append(long_run(wid, km, half_km(km * 0.25), "race"))
            else:
                out.append(long_run(wid, km))
        return out
    base_end = max(1, round(build * 0.4))
    for wk in range(1, n + 1):
        w = W(wk)
        out = []
        runs = cfg["runs"]
        if wk <= build and wk not in cutbacks:          # progression week
            last_prog = wk
            f = progress_weeks.index(wk) / steps
            phase = "base" if wk <= base_end else ("build" if f < 0.75 or goal == "baseBuilding" else "peak")
            long_km, easy_km = long_v[wk], easy_v[wk]
            rec_km = rec_v[wk] if rec_v else None
            menu = quality_menu(goal, level, phase, f, w)
            q = menu[k % len(menu)]
            k += 1
            if goal == "baseBuilding" and level == "beginner":
                q = None
            ff = fast_finish and phase == "peak" and k % 2 == 0
        elif wk <= build:                               # cutback week
            f = progress_weeks.index(last_prog) / steps
            long_km, easy_km = long_v[last_prog] * 0.68, easy_v[last_prog] * 0.75
            rec_km = rec_v[last_prog] * 0.75 if rec_v else None
            q = (None if goal == "baseBuilding" and level == "beginner"
                 else fartlek(w("fartlek"), 4 if level == "beginner" else 6))
            ff = False
        elif wk < n:                                    # taper week (not race week)
            scale = [0.8, 0.65][wk - build - 1] if taper == 3 else 0.7
            long_km, easy_km = long_v[last_prog] * scale, easy_v[last_prog] * (scale + 0.1)
            rec_km = rec_v[last_prog] * scale if rec_v else None
            q = (intervals(w("intervals"), 5, 800, recover=120) if goal in ("fiveK", "tenK")
                 else tempo(w("tempo"), 20 if level != "beginner" else 15))
            ff = False
        else:                                           # race week
            out = [easy(w(f"easy-{j + 1}"), min(5, half_km(easy_v[last_prog] * 0.6))) for j in range(runs - 2)]
            if rec_v:
                out[-1] = recovery(w("recovery"), 4)
            out.append(fartlek(w("fartlek"), 4, cd=300) if goal in ("fiveK", "tenK") else tempo(w("tempo"), 10))
            out.append(race(w("race"), info["race"]))
            weeks.append(out)
            continue

        n_easy = runs - 1 - (1 if q else 0) - (1 if rec_km else 0)
        strides_ok = level != "beginner" or wk > build // 2
        specs = []   # [kind, id, km] for the adjustable runs; quality stays fixed
        for j in range(n_easy):
            km = half_km(easy_km * (0.9 if j else 1.0))
            if j == n_easy - 1 and n_easy > 1 and strides_ok:
                specs.append(["strides", w("strides"), km])
            else:
                specs.append(["easy", w(f"easy-{j + 1}"), km])
        if rec_km:
            specs.append(["recovery", w("recovery"), half_km(rec_km)])
        specs.append(["long_ff" if ff else "long", w("long"), half_km(long_km)])
        fixed = [q] if q else []
        # Keep weekly volume within ~8% of the biggest week so far by trimming easy runs, then the long run.
        # The long run is never cut below last week's, so it keeps progressing.
        while peak_km and week_load(render(specs) + fixed)[0] > peak_km * 1.10 + 0.4:
            easy_specs = [sp for sp in specs if sp[0] in ("easy", "strides", "recovery") and sp[2] > 2.5]
            if easy_specs:
                max(easy_specs, key=lambda sp: sp[2])[2] -= 0.5
            elif specs[-1][2] - 0.5 >= prev_long:
                specs[-1][2] -= 0.5
            else:
                break
        workouts = render(specs)
        out = workouts[:-1] + fixed + workouts[-1:]
        weeks.append(out)
        if wk <= build:
            peak_km = max(peak_km, week_load(out)[0])
            if wk not in cutbacks:
                prev_long = specs[-1][2]

    # Phases
    phases = [("Base", 1, base_end)]
    if build > base_end:
        phases.append(("Build", base_end + 1, build))
    if taper:
        phases.append(("Taper", build + 1, n))
    phases = [p for p in phases if p[1] <= p[2]]

    title = f"{info['name']} – {level.capitalize()}"
    p = plan(f"{ID_PREFIX}{info['slug']}-{level}-{n}w", title, goal, level, (cfg["runs"], cfg["runs"]),
             "", phases, weeks)
    p["description"] = DESCRIPTIONS[(goal, level)]
    week1_km = week_load(weeks[0])[0]
    p["fitNote"] = (f"Suits runners already doing about {round(week1_km)} km "
                    f"({round(week1_km / 1.609)} mi) a week.")
    return p


PLANS = [lambda n=n: couch_to_5k(n) for n in LENGTHS]
for (goal, level) in FAMILIES:
    for n in (MARATHON_LENGTHS[level] if goal == "marathon" else LENGTHS):
        PLANS.append(lambda g=goal, l=level, n=n: engine_plan(g, l, n))


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
    written = set()
    for fn in PLANS:
        p = fn()
        written.add(f"{p['id']}.json")
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
    if not check_only:
        for name in os.listdir(OUT):
            if name.startswith(ID_PREFIX) and name not in written:
                os.remove(os.path.join(OUT, name))
    print(f"{len(written)} plans")
    sys.exit(1 if failed else 0)


if __name__ == "__main__":
    main()
