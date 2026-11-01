import Toybox.Activity;
import Toybox.ActivityRecording;
import Toybox.Attention;
import Toybox.Lang;
import Toybox.Position;
import Toybox.Sensor;
import Toybox.Time;
import Toybox.Timer;
import Toybox.WatchUi;

enum RunState {
    STATE_READY,
    STATE_RUNNING,
    STATE_PAUSED,
    STATE_SAVED,
    STATE_DISCARDED
}

//! A guided run. Walks the workout's steps using the watch's own timer and distance, records a FIT activity that
//! syncs to Garmin Connect, and keeps splits, pace samples and a thinned route to send to the phone.
//! Step logic mirrors WorkoutEngine and RunSession in the iPhone app.
class RunModel {
    //! Route and sample buffers are thinned (every other point dropped) beyond this many points.
    const MAX_POINTS = 600;
    //! Seconds of movement used for the current pace.
    const PACE_WINDOW = 15;

    var title as String;
    var workoutId as String;
    //! Step arrays (see Proto.S_*); empty for a free run.
    var steps as Array;
    var units as String;
    var unitMeters as Float;
    var cues as Dictionary;
    var state as RunState = STATE_READY;
    var gpsReady as Boolean = false;
    var runId as String = "";

    var movingTime as Float = 0.0;
    var distance as Float = 0.0;
    //! Seconds per km over the last few seconds; null until there's enough movement.
    var currentPace as Float? = null;
    var heartRate as Number? = null;
    var averageHeartRate as Number? = null;

    var stepIndex as Number = 0;
    var stepStartTime as Float = 0.0;
    var stepStartDistance as Float = 0.0;
    //! `[seconds, meters, skipped (0/1)]` for each finished step.
    var stepTotals as Array = [];
    //! `[meters, seconds]` per split (1 km or 1 mi).
    var splits as Array = [];

    private var _splitStartTime as Float = 0.0;
    private var _splitStartDistance as Float = 0.0;
    //! Flat `[distance, movingTime, pace, heartRate]`.
    private var _samples as Array = [];
    private var _sampleEvery as Number = 10;
    private var _lastSampleTime as Float = -1000.0;
    //! Flat `[lat, lon, altitude, secondsSinceStart]`.
    private var _route as Array = [];
    private var _routeEvery as Number = 5;
    private var _lastRouteTime as Float = -1000.0;
    //! Flat `[movingTime, distance]` covering the pace window.
    private var _window as Array = [];
    private var _lastPaceAlert as Float = -1000.0;
    private var _startEpoch as Number = 0;
    private var _session as ActivityRecording.Session? = null;
    private var _timer as Timer.Timer;

    //! `workout` is a stored workout (see Store.workout) or null for a free run.
    function initialize(workout as Dictionary?) {
        units = Store.units();
        unitMeters = units.equals("mi") ? 1609.344 : 1000.0;
        cues = Store.cues();
        if (workout != null) {
            title = workout["title"] instanceof String ? workout["title"] as String : "Workout";
            workoutId = workout["id"] instanceof String ? workout["id"] as String : "";
            steps = workout["steps"] instanceof Array ? workout["steps"] as Array : [];
        } else {
            title = "Free Run";
            workoutId = "";
            steps = [];
        }
        Position.enableLocationEvents(Position.LOCATION_CONTINUOUS, method(:onPosition));
        if (Sensor has :setEnabledSensors) {
            Sensor.setEnabledSensors([Sensor.SENSOR_HEARTRATE]);
        }
        _timer = new Timer.Timer();
        _timer.start(method(:onTick), 1000, true);
    }

    function onPosition(info as Position.Info) as Void {
        gpsReady = info.accuracy != null && info.accuracy >= Position.QUALITY_USABLE;
    }

    // MARK: State

    function isActive() as Boolean {
        return state == STATE_RUNNING || state == STATE_PAUSED;
    }

    function isFreeRun() as Boolean {
        return steps.size() == 0;
    }

    function isWorkoutComplete() as Boolean {
        return steps.size() > 0 && stepIndex >= steps.size();
    }

    function currentStep() as Array? {
        return stepIndex < steps.size() ? steps[stepIndex] as Array : null;
    }

    function nextStep() as Array? {
        return stepIndex + 1 < steps.size() ? steps[stepIndex + 1] as Array : null;
    }

    //! Seconds or meters left in the current step.
    function stepRemaining() as Float {
        var step = currentStep();
        if (step == null) {
            return 0.0;
        }
        var done = step[Proto.S_DURATION_TYPE] == 0 ? movingTime - stepStartTime : distance - stepStartDistance;
        var left = step[Proto.S_DURATION].toFloat() - done;
        return left > 0 ? left : 0.0;
    }

    //! -1 faster than the target, 1 slower, 0 on target or no target.
    function compliance(tolerance as Number) as Number {
        var step = currentStep();
        if (step == null || currentPace == null || step[Proto.S_FAST] == 0) {
            return 0;
        }
        if (currentPace < step[Proto.S_FAST] - tolerance) {
            return -1;
        }
        if (currentPace > step[Proto.S_SLOW] + tolerance) {
            return 1;
        }
        return 0;
    }

    function averagePace() as Float? {
        return distance > 50 ? movingTime / distance * 1000.0 : null;
    }

    // MARK: Controls

    function start() as Void {
        if (state != STATE_READY) {
            return;
        }
        var session = ActivityRecording.createSession({
            :name => title,
            :sport => Activity.SPORT_RUNNING,
            :subSport => Activity.SUB_SPORT_GENERIC
        });
        session.start();
        _session = session;
        _startEpoch = Time.now().value();
        runId = "g" + _startEpoch;
        state = STATE_RUNNING;
        alert(true);
    }

    function pause() as Void {
        var session = _session;
        if (state == STATE_RUNNING && session != null) {
            session.stop();
            state = STATE_PAUSED;
            alert(false);
        }
    }

    function resume() as Void {
        var session = _session;
        if (state == STATE_PAUSED && session != null) {
            session.start();
            state = STATE_RUNNING;
            alert(false);
        }
    }

    //! The lap button: ends the current step early (or just marks a lap on a free run).
    function lap() as Void {
        if (state != STATE_RUNNING) {
            return;
        }
        if (currentStep() != null) {
            closeStep(true);
        }
        addLap();
        alert(false);
    }

    private function addLap() as Void {
        var session = _session;
        if (session != null) {
            session.addLap();
        }
    }

    //! Ends the run. Saved runs go to Garmin Connect via the watch's normal sync, and to the phone via the outbox.
    function finish(save as Boolean) as Void {
        if (state == STATE_SAVED || state == STATE_DISCARDED) {
            return;
        }
        _timer.stop();
        Position.enableLocationEvents(Position.LOCATION_DISABLE, method(:onPosition));
        var session = _session;
        if (session == null) {
            state = STATE_DISCARDED;
            return;
        }
        var info = Activity.getActivityInfo();
        if (info != null) {
            if (state == STATE_RUNNING) {
                update(info);
            }
            averageHeartRate = info.averageHeartRate;
        }
        if (session.isRecording()) {
            session.stop();
        }
        _session = null;
        if (!save) {
            session.discard();
            state = STATE_DISCARDED;
            return;
        }
        session.save();
        state = STATE_SAVED;

        // Close the step in progress (it counts unless barely started) and mark the rest as skipped.
        if (currentStep() != null) {
            closeStep(movingTime - stepStartTime < 5);
        }
        while (currentStep() != null) {
            closeStep(true);
        }
        var tail = distance - _splitStartDistance;
        if (tail > 50) {
            splits.add([tail, movingTime - _splitStartTime]);
        }
        storeForPhone();
        getApp().link.sendRun(runId);
    }

    // MARK: Updates

    function onTick() as Void {
        var info = Activity.getActivityInfo();
        if (info != null) {
            heartRate = info.currentHeartRate;
            if (state == STATE_RUNNING) {
                update(info);
            }
        }
        WatchUi.requestUpdate();
    }

    private function update(info as Activity.Info) as Void {
        var timer = info.timerTime;
        if (timer != null) {
            movingTime = timer / 1000.0;
        }
        var meters = info.elapsedDistance;
        if (meters != null) {
            distance = meters.toFloat();
        }
        updatePace();
        advanceSteps();
        recordSplits();

        if (currentPace != null && movingTime - _lastSampleTime >= _sampleEvery) {
            _samples.addAll([distance, movingTime, currentPace, heartRate != null ? heartRate : 0]);
            _lastSampleTime = movingTime;
            if (_samples.size() >= MAX_POINTS * 4) {
                _samples = thin(_samples);
                _sampleEvery *= 2;
            }
        }
        var location = info.currentLocation;
        if (location != null && movingTime - _lastRouteTime >= _routeEvery) {
            var degrees = location.toDegrees();
            var altitude = info.altitude;
            if (altitude == null) {
                altitude = 0.0;
            }
            _route.addAll([degrees[0].toFloat(), degrees[1].toFloat(), altitude, Time.now().value() - _startEpoch]);
            _lastRouteTime = movingTime;
            if (_route.size() >= MAX_POINTS * 4) {
                _route = thin(_route);
                _routeEvery *= 2;
            }
        }
        checkPace();
    }

    private function updatePace() as Void {
        _window.addAll([movingTime, distance]);
        while (_window.size() > 4 && movingTime - _window[2] >= PACE_WINDOW) {
            _window = _window.slice(2, null);
        }
        var seconds = movingTime - _window[0];
        var meters = distance - _window[1];
        currentPace = (meters > 10 && seconds > 0) ? seconds / meters * 1000.0 : null;
    }

    //! Advances through every step whose time or distance has been reached.
    private function advanceSteps() as Void {
        var changed = false;
        while (stepIndex < steps.size()) {
            var step = steps[stepIndex] as Array;
            var target = step[Proto.S_DURATION].toFloat();
            var endTime = 0.0;
            var endDistance = 0.0;
            if (step[Proto.S_DURATION_TYPE] == 0) {
                if (movingTime - stepStartTime < target) {
                    break;
                }
                endTime = stepStartTime + target;
                endDistance = distance;
            } else {
                if (distance - stepStartDistance < target) {
                    break;
                }
                endTime = movingTime;
                endDistance = stepStartDistance + target;
            }
            stepTotals.add([endTime - stepStartTime, endDistance - stepStartDistance, 0]);
            stepStartTime = endTime;
            stepStartDistance = endDistance;
            stepIndex++;
            changed = true;
        }
        if (changed) {
            addLap();
            alert(true);
            _lastPaceAlert = movingTime;
        }
    }

    private function closeStep(skipped as Boolean) as Void {
        stepTotals.add([movingTime - stepStartTime, distance - stepStartDistance, skipped ? 1 : 0]);
        stepStartTime = movingTime;
        stepStartDistance = distance;
        stepIndex++;
    }

    private function recordSplits() as Void {
        while (distance - _splitStartDistance >= unitMeters) {
            splits.add([unitMeters, movingTime - _splitStartTime]);
            _splitStartTime = movingTime;
            _splitStartDistance += unitMeters;
        }
    }

    //! Buzzes at most once a minute when pace drifts outside the target (not during recoveries or walks).
    private function checkPace() as Void {
        var step = currentStep();
        if (step == null || movingTime - stepStartTime < 30 || movingTime - _lastPaceAlert < 60) {
            return;
        }
        var kind = step[Proto.S_KIND];
        if ("recover".equals(kind) || "walk".equals(kind)) {
            return;
        }
        var drift = compliance(10);
        if (drift == 0) {
            return;
        }
        _lastPaceAlert = movingTime;
        if (Attention has :vibrate) {
            // One long buzz: ease off. Two short: pick it up.
            var pattern = drift < 0
                ? [new Attention.VibeProfile(100, 700)]
                : [new Attention.VibeProfile(100, 200), new Attention.VibeProfile(0, 150), new Attention.VibeProfile(100, 200)];
            Attention.vibrate(pattern);
        }
    }

    private function alert(strong as Boolean) as Void {
        if (Attention has :vibrate) {
            Attention.vibrate([new Attention.VibeProfile(100, strong ? 600 : 250)]);
        }
        if (strong && (Attention has :playTone)) {
            Attention.playTone(Attention.TONE_INTERVAL_ALERT);
        }
    }

    //! Keeps every other point of a flat 4-value-per-point array.
    private function thin(flat as Array) as Array {
        var out = [];
        for (var i = 0; i + 4 <= flat.size(); i += 8) {
            out.addAll(flat.slice(i, i + 4));
        }
        return out;
    }

    // MARK: Phone

    //! Writes the run's messages to storage: the header as part 0, then route and sample chunks.
    private function storeForPhone() as Void {
        var seq = storeChunks(0, "route", _route);
        _route = [];
        seq = storeChunks(seq, "samples", _samples);
        _samples = [];
        Store.saveRunPart(runId, 0, {
            "t" => "run",
            "v" => Proto.VERSION,
            "id" => runId,
            "wid" => workoutId,
            "title" => title,
            "start" => _startEpoch,
            "end" => Time.now().value(),
            "dist" => distance,
            "time" => movingTime,
            "hr" => averageHeartRate != null ? averageHeartRate : 0,
            "steps" => stepTotals,
            "splits" => splits,
            "parts" => seq
        });
        Store.addToOutbox(runId, seq + 1);
    }

    //! Stores `flat` as chunk messages numbered from `seq`. Returns the next sequence number.
    private function storeChunks(seq as Number, kind as String, flat as Array) as Number {
        var size = Proto.CHUNK_POINTS * 4;
        for (var i = 0; i < flat.size(); i += size) {
            var last = i + size < flat.size() ? i + size : flat.size();
            Store.saveRunPart(runId, seq + 1, {
                "t" => "chunk",
                "id" => runId,
                "seq" => seq,
                "kind" => kind,
                "data" => flat.slice(i, last)
            });
            seq++;
        }
        return seq;
    }
}
