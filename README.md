# StridePlan

A native iPhone running-plan app in Swift and SwiftUI. You browse training plans, personalise one around your week, and follow guided workouts with GPS tracking, voice cues, a Live Activity and Apple Health sync.

> **Name:** "StridePlan" is a placeholder. See [Renaming](#renaming).

---

## Requirements

| | |
|---|---|
| Xcode | 16.0 or later (the project uses synchronized folders, object version 77) |
| iOS | 17.0+, iPhone only, portrait |
| Swift | 5.10+ (language mode 5) |
| Dependencies | Garmin's [Connect IQ iOS SDK](https://github.com/garmin/connectiq-companion-app-sdk-ios) (Swift package, resolved by Xcode) |

## Getting started

1. Open `StridePlan.xcodeproj`.
2. Set signing in **`Config/Shared.xcconfig`**:
   ```
   BUNDLE_ID_PREFIX = com.yourcompany.strideplan
   DEVELOPMENT_TEAM = ABCDE12345
   ```
   You can also pick a team under *Signing & Capabilities* for each target.
3. Choose the **StridePlan** scheme and an iPhone simulator, then press Run (⌘R).
4. Run the tests with ⌘U.

### Trying a run in the Simulator

The Simulator always uses `GPXReplayLocationService`, which replays `Resources/GPX/SampleRun.gpx`: a 6.2 km loop with intervals and a few deliberately bad GPS fixes. On a real device, turn on **Settings → Testing → Simulate GPS** to get the same replay.

Xcode's own *Debug → Simulate Location* also works with any GPX file if you switch the app back to `CoreLocationService`.

## Capabilities and Info.plist

These are already set up in the project. Here is what each target uses, in case you rebuild it by hand.

**App target (`StridePlan`)**

| Capability | Where |
|---|---|
| Background Modes → *Location updates*, *Audio*, *Uses Bluetooth LE accessories* | `UIBackgroundModes` in `Config/StridePlan-Info.plist` |
| HealthKit | `Config/StridePlan.entitlements` (`com.apple.developer.healthkit`) |
| Live Activities | `NSSupportsLiveActivities = YES` in the Info.plist |

Usage strings in `Config/StridePlan-Info.plist`:

| Key | Purpose |
|---|---|
| `NSLocationWhenInUseUsageDescription` | GPS distance, pace and route during runs |
| `NSHealthShareUsageDescription` | Read heart rate for run summaries |
| `NSHealthUpdateUsageDescription` | Save runs as workouts with routes |
| `NSBluetoothAlwaysUsageDescription` | Talk to a Garmin watch (Connect IQ SDK) |

For Garmin, the Info.plist also registers the `strideplan-ciq` URL scheme, which Garmin Connect uses to return the chosen watch, and lists `gcm-ciq` under `LSApplicationQueriesSchemes`.

Xcode merges the remaining keys (display name, launch screen, portrait-only) from the `INFOPLIST_KEY_*` build settings.

**Widget extension (`StridePlanLiveActivity`)** shows the Lock Screen and Dynamic Island Live Activity. Its Info.plist is `Config/LiveActivity-Info.plist`, which sets `NSExtensionPointIdentifier = com.apple.widgetkit-extension`. Push notifications are *not* needed, because the app updates the activity locally.

**Background behaviour.** Location keeps running with the screen locked because of `allowsBackgroundLocationUpdates` and a `CLBackgroundActivitySession`. Voice cues use an `AVAudioSession` set to `.playback` / `.voicePrompt` with `.duckOthers`, so music gets quieter during a cue instead of stopping.

**Permissions are requested in context:**
- **Location:** when you start your first run.
- **Notifications:** when you start a plan.
- **HealthKit:** optional, during onboarding or in Settings.

## Project structure

```
StridePlan/                 App target (synchronized folder)
  App/                      App entry, root TabView, AppServices (dependency container), RunLauncher
  Features/
    Onboarding/             Welcome + profile questions
    Catalog/                Plan browser, filters, plan detail with mileage chart
    PlanSetup/              Dates, run days, long-run day, goal time, confirmation
    Today/                  Today card, week progress ring, up next
    Schedule/               Whole-plan week list, swap / move / skip, weekly summary chart
    WorkoutDetail/          Structured steps with target paces
    RunTracking/            RunSession (engine), running screen, manual logging
    History/                Run summary (map, splits, pace chart, compliance), history + stats
    Progress/               Missed-week adaptation sheet
    Settings/               Units, voice, reminders, zones, HealthKit, plan management, export
  Services/                 PlanLoader, PaceCalculator, ScheduleGenerator, WorkoutEngine, RunMetricsTracker,
                            LocationService (+ GPX replay), HealthKitService, VoiceCoachService,
                            NotificationService, LiveActivityService, PlanManager, DataExporter, Haptics,
                            GarminService / GarminSync / GarminProtocol (watch connection)
  Models/                   Plan template structs (Codable), pace zones, SwiftData models
  DesignSystem/             Theme, zone colors, reusable components
  Preview/                  In-memory SwiftData seed for SwiftUI previews
  Resources/Plans/*.json    Bundled plan catalog (14 plans)
  Resources/GPX/            Sample route for GPS replay
Shared/                     Compiled into both app and widget (ActivityAttributes, brand + zone palette)
LiveActivity/               Widget extension (Lock Screen + Dynamic Island)
Tests/                      XCTest unit tests (hosted by the app)
Garmin/                     Connect IQ watch app (Monkey C). See Garmin/README.md
Config/                     Info.plists, entitlements, Shared.xcconfig
scripts/                    Plan generator/validator, project generator, icon + GPX generators
```

### Architecture notes

- **MVVM-ish feature folders.** Views stay thin. Mutations of the schedule go through `PlanManager`, and the live run goes through the `@Observable` `RunSession`.
- **Hardware is behind protocols:** `LocationProviding`, `HealthServicing`, `VoiceCoaching`, `NotificationScheduling`, `RunActivityControlling` and `HapticsProviding`. `AppServices.live()` wires up the real implementations, and `AppServices.preview` (the environment default) wires up mocks, so previews and tests never touch hardware.
- **Pure logic is separated from Apple frameworks.** `PaceCalculator`, `ScheduleGenerator`, `WorkoutEngine`, `RunMetricsTracker`, `PlanLoader`/`PlanValidator` and `GPXParser` depend only on Foundation, so they're fast to test.
- **SwiftData stores user data:** `UserProfile`, `ActivePlan`, `ScheduledWorkout` and `RunRecord`. Larger value types (zones, splits, route, step results) are stored as JSON `Data` behind typed accessors, which keeps the schema simple. Plan templates are never persisted; they're loaded from the bundle.
- **Pace zones** use the VDOT model (Daniels/Gilbert oxygen-cost and drop-off curves). Training zones are fractions of VDOT, race pace comes from the goal time, and a Riegel predictor is included. With no reference time, every target falls back to an RPE effort cue.
- **Scheduling.** Training weeks are rolling 7-day windows from the start date. With a race date, the plan is back-scheduled so the race lands on that day. Within a week:
  - the race goes on race day, and the long run on your chosen long-run day;
  - quality sessions are spread as far as possible from the long run and from each other;
  - easy runs fill the remaining days.

  If you pick fewer days than the plan needs, the lowest-priority sessions are dropped (cross-training first, then recovery, then easy runs), and you're told which.

## Adding a new plan

1. Create `StridePlan/Resources/Plans/<plan-id>.json`. The file name must match `id`. Because the folder is synchronized, Xcode bundles the file automatically, with no code changes needed.
2. Follow the schema below. Distances are in **meters** and times in **seconds**.

```json
{
  "id": "10k-beginner-10w",
  "title": "10K – Beginner",
  "goal": "tenK",                       // couchTo5K | fiveK | tenK | halfMarathon | marathon | baseBuilding
  "level": "beginner",                  // beginner | intermediate | advanced
  "weeks": 10,
  "runsPerWeek": { "min": 3, "max": 3 },
  "description": "Step up from 5K to 10K…",
  "phases": [{ "name": "Base", "weeks": [1, 4] }, { "name": "Build", "weeks": [5, 9] }, { "name": "Taper", "weeks": [10, 10] }],
  "schedule": [
    { "week": 1, "workouts": [
      { "id": "w1-easy-1", "type": "easy", "title": "Easy 4 km", "notes": "Conversational pace.",
        "steps": [{ "kind": "run", "duration": { "type": "distance", "value": 4000 }, "zone": "easy" }] },
      { "id": "w1-intervals", "type": "intervals", "title": "6 × 400 m",
        "steps": [
          { "kind": "warmup", "duration": { "type": "time", "value": 600 }, "zone": "easy" },
          { "kind": "repeat", "count": 6, "steps": [
            { "kind": "run", "duration": { "type": "distance", "value": 400 }, "zone": "interval" },
            { "kind": "recover", "duration": { "type": "time", "value": 90 }, "zone": "recovery" } ] },
          { "kind": "cooldown", "duration": { "type": "time", "value": 600 }, "zone": "easy" } ] }
    ] }
  ]
}
```

| Field | Values |
|---|---|
| Workout `type` | `easy`, `recovery`, `long`, `tempo`, `intervals`, `hills`, `fartlek`, `progression`, `race`, `crossTrain`, `rest` |
| Step `kind` | `warmup`, `run`, `recover`, `cooldown`, `walk`, `repeat` (repeats nest, with `count` + `steps`) |
| `zone` | `walk`, `recovery`, `easy`, `steady`, `tempo`, `threshold`, `interval`, `repetition`, `race` |
| Optional fields | `isLongRun` (defaults to `true` for `long`), `notes`, and `note` on a step |

`rest` days are implicit and don't need entries. A race plan's final workout should have `"type": "race"`, so race-date back-scheduling has something to anchor to.

3. Run the tests. `PlanCatalogTests` decodes every bundled plan and runs `PlanValidator`, which checks:
   - weeks are numbered sequentially and match `weeks`;
   - workout IDs are unique;
   - every run has executable steps;
   - each week's run count fits `runsPerWeek`;
   - phases cover every week exactly once;
   - race plans end in a race of the goal distance.

### Using the plan generator (optional)

`scripts/generate_plans.py` produced the 14 bundled plans from compact week tables, and it checks training load as it goes:

- no week more than 10% above the previous peak;
- a cutback week at least every 4 weeks;
- a high share of easy running;
- a taper before the race.

```bash
python3 scripts/generate_plans.py --check   # report only
python3 scripts/generate_plans.py           # rewrite the JSON files it owns
```

Hand-written JSON plans can live alongside the generated ones.

## Testing

| Suite | Covers |
|---|---|
| `PaceCalculatorTests` | VDOT vs published tables, inverse velocity, race prediction, Riegel, zone ordering, goal vs reference precedence, effort fallback, compliance, formatting |
| `ScheduleGeneratorTests` | Start-date mapping, weekday selection, long-run day, race-date back-scheduling (including a race on an unselected weekday), spacing of quality sessions, priority-based dropping, one workout per day across every bundled plan |
| `WorkoutStepTests` | Repeat → flat-list expansion (nested, zero counts), estimates, summaries, step engine progression/skip/finish |
| `PlanCatalogTests` | Every bundled JSON decodes and validates; the catalog covers every goal and level; the schema example decodes |
| `RunMetricsTrackerTests` | Distance and rolling pace, bad-accuracy / teleport / stale rejection, pause handling, GPS dropout bridging, splits |
| `GPXReplayTests` | Bundled GPX → tracker + engine end to end, the same path the Simulator uses |

Every screen has a `#Preview` that uses `PreviewData`: an in-memory store seeded with a runner three weeks into the intermediate half-marathon plan, plus mock services.

## Renaming

1. Edit `AppBrand` in `Shared/Brand.swift` (name, tagline, accent color) and the `AccentColor` asset.
2. Edit `APP_DISPLAY_NAME` and `BUNDLE_ID_PREFIX` in `Config/Shared.xcconfig`.
3. Optionally rename the targets/folders and rerun `python3 scripts/generate_xcodeproj.py` after updating its constants.
4. Update the usage strings in `Config/StridePlan-Info.plist`, which mention the name.

## Garmin watches

StridePlan has a companion Connect IQ app in `Garmin/`. Connect a watch in **Settings → Garmin** (this goes through the Garmin Connect app). Then open StridePlan on the watch, or tap **Send to Garmin** on a workout. The watch gets the next 7 days of runs with your pace targets and guides you through each step. It records a normal Garmin activity and sends the run back, where it lands in History and completes the scheduled workout. Garmin runs aren't saved to Apple Health again, because Garmin Connect already does that. See [Garmin/README.md](Garmin/README.md) for building, installing and the message format.

## Data export

**Settings → Your data → Export** writes a pretty-printed JSON file with your profile, pace zones, plans, scheduled workouts and every run (splits, step results and route), then offers it through the share sheet.

## Out of scope for v1 (structured for later)

- Accounts and sync: services are protocol-based, and SwiftData models carry stable IDs.
- Social features, payments, an Apple Watch app (the `RunSession`/`WorkoutEngine` split is designed to move to watchOS), and AI-generated plans (plans are plain data, so a generator only has to emit the JSON schema).

## Scripts

| Script | Purpose |
|---|---|
| `scripts/generate_plans.py` | Writes and validates the plan JSON files |
| `scripts/generate_xcodeproj.py` | Regenerates `StridePlan.xcodeproj` (deterministic IDs) |
| `scripts/build_watch.sh` | Builds the Garmin watch app (`.prg` for one device, or the store `.iq`) |
| `scripts/make_icon.py` | Placeholder 1024 px app icon (needs Pillow) |
| `scripts/make_sample_gpx.py` | Sample GPX route used for GPS replay |
