# StridePlan for Garmin

A Connect IQ watch app (Monkey C) that runs the workouts planned in the StridePlan iPhone app and sends the recorded runs back.

- **Workouts go to the watch.** When the watch app opens, it asks the phone for workouts. The phone answers with today's and the next 6 days' runs, with your personal pace targets. **Send to Garmin** on a workout pushes the list right away and prompts the watch to open the app. The workouts are stored on the watch, so you can run without your phone.
- **The run is recorded on the watch.** StridePlan guides you step by step: a zone-coloured band with the step and target pace, the time or distance left, and your live pace coloured against the target. You get a buzz and tone at each step change, and a buzz when you drift off pace for more than 30 seconds (one long buzz means ease off, two short buzzes mean pick it up). The run is saved as a normal running activity, so it reaches Garmin Connect (and Strava, Apple Health and so on) through your usual sync. Each step is also a lap.
- **Results come back to the app.** When you save, the watch sends the phone the summary, per-step totals, splits, a pace/heart-rate trace and the route. The phone saves it to History, marks the scheduled workout as completed, and shows step-by-step compliance like a phone-tracked run. The watch keeps the run until the phone confirms it, so nothing is lost if the phone isn't nearby: it resends on the next launch, or when you choose **Send runs to phone**.

## Buttons

| Button | Before the run | Running | Paused |
|---|---|---|---|
| START | Start recording | Pause and open the menu (Resume / Save / Discard) | Open the menu |
| BACK / LAP | Back to the workout list | Next step (lap) | Open the menu |

Taps on the screen are ignored during a run.

## Building

You need the Connect IQ SDK (`monkeyc` on `PATH`), the device files for your watch, and a developer key. The build script explains how to make the key.

```bash
scripts/build_watch.sh fr265     # → Garmin/build/StridePlan-fr265.prg
scripts/build_watch.sh store     # → Garmin/build/StridePlan.iq (all devices, for the store)
```

**Device files** come from Garmin's SDK Manager (a GUI) after signing in with a Garmin account. On a machine without a display, the community [`connect-iq-sdk-manager`](https://github.com/lindell/connect-iq-sdk-manager-cli) CLI does the same thing:

```bash
connect-iq-sdk-manager agreement accept
connect-iq-sdk-manager login                                   # your Garmin account
connect-iq-sdk-manager sdk set 9.2.0
connect-iq-sdk-manager device download --manifest=Garmin/manifest.xml
export PATH="$(connect-iq-sdk-manager sdk current-path --bin):$PATH"
```

## Installing on your watch

- **Sideload, for testing:** connect the watch over USB and copy the `.prg` into `GARMIN/APPS/`. Then unplug it; the app appears in the watch's apps list.
- **Connect IQ Store:** upload `StridePlan.iq` at [apps.garmin.com/developer](https://apps.garmin.com/developer). A **beta** app is visible only to your account and installs through the Garmin Connect app like any other. Once the app is published, the iPhone app's **Install StridePlan on the watch** button opens its store page.

The iPhone app talks to the watch through the Garmin Connect app (Garmin's Connect IQ iOS SDK). Pair the watch in **Settings → Garmin → Connect a Garmin watch** in StridePlan.

## Messages

Every message is a dictionary with a `"t"` (type) key. The phone side is `StridePlan/Services/GarminProtocol.swift` (unit-tested); constants here are in `source/Store.mc`.

| Type | Direction | Contents |
|---|---|---|
| `hello` | watch → phone | `pending`: runs waiting to be sent |
| `workouts` | phone → watch | `units` (`km`/`mi`), `cues` (zone key → effort text), `list` of `{id, day (yyyymmdd), title, steps}` |
| `run` | watch → phone | `id`, `wid` (workout id, empty for a free run), `title`, `start`/`end` (Unix s), `dist` (m), `time` (moving s), `hr` (avg, 0 = none), `steps` `[[s, m, skipped]…]`, `splits` `[[m, s]…]`, `parts` (chunk count) |
| `chunk` | watch → phone | `id`, `seq` (0…parts-1), `kind` `route` (flat `lat, lon, alt, s since start`) or `samples` (flat `m, moving s, s/km, hr`), `data` |
| `ack` | phone → watch | `id`: the phone has saved the run, so the watch deletes it |

A step is `[kind, title, zoneKey, zoneName, durationType (0 time / 1 distance), value (s or m), fastPace, slowPace]`. Paces are in seconds per km, and 0 means effort-based.

The workout `id` is `yyyymmdd-orderInDay-templateWorkoutID`, which lets the phone find the scheduled workout again when the run comes back. To keep memory low on smaller watches, route points are recorded every 5 s and pace samples every 10 s. Beyond 600 points the buffer drops every other point and doubles the interval.
