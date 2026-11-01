import Toybox.Graphics;
import Toybox.Lang;
import Toybox.WatchUi;

//! The run screen: current step and target on a zone-colored band, what's left of the step, pace and distance.
//! After the run it shows a short summary and whether the phone has the run yet.
class RunView extends WatchUi.View {
    private var _run as RunModel;

    function initialize(run as RunModel) {
        View.initialize();
        _run = run;
    }

    function onUpdate(dc as Dc) as Void {
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_BLACK);
        dc.clear();
        if (_run.state == STATE_SAVED || _run.state == STATE_DISCARDED) {
            drawSummary(dc);
        } else {
            drawRun(dc);
        }
    }

    private function drawRun(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var step = _run.currentStep();
        var bandH = h * 32 / 100;

        // Band: step title and target. Text sits low in the band, where round screens are wider.
        var title;
        var target;
        var color;
        if (step != null) {
            title = step[Proto.S_TITLE];
            color = Zones.color(step[Proto.S_ZONE_KEY]);
            target = step[Proto.S_FAST] != 0
                ? Fmt.paceRange(step[Proto.S_FAST], step[Proto.S_SLOW], _run.unitMeters) + " /" + _run.units
                : (_run.cues[step[Proto.S_ZONE_KEY]] instanceof String ? _run.cues[step[Proto.S_ZONE_KEY]] : "");
        } else if (_run.isWorkoutComplete()) {
            title = "Workout complete";
            target = "Keep going or save";
            color = Graphics.COLOR_LT_GRAY;
        } else {
            title = _run.title;
            target = "";
            color = Zones.ACCENT;
        }
        if (_run.state == STATE_PAUSED) {
            title = "PAUSED";
            color = Graphics.COLOR_LT_GRAY;
        }
        dc.setColor(color, color);
        dc.fillRectangle(0, 0, w, bandH);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, bandH * 55 / 100, Graphics.FONT_XTINY, title, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx, bandH * 83 / 100, Graphics.FONT_XTINY, target, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        var small = Graphics.FONT_XTINY;
        var smallH = dc.getFontHeight(small);
        var big = numberFont(dc, h * 24 / 100);
        var bigH = dc.getFontHeight(big);
        var mid = h * 12 / 100 < dc.getFontHeight(Graphics.FONT_MEDIUM) ? Graphics.FONT_SMALL : Graphics.FONT_MEDIUM;
        var midH = dc.getFontHeight(mid);

        var y = bandH + bigH / 2;
        if (_run.state == STATE_READY) {
            dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, bandH + midH, mid, "Press START", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            dc.setColor(_run.gpsReady ? Graphics.COLOR_GREEN : Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, bandH + midH * 2, small, _run.gpsReady ? "GPS ready" : "Finding GPS...", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            var next = _run.isFreeRun() ? "Open run, no steps" : _run.steps.size().toString() + " steps";
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
            dc.drawText(cx, bandH + midH * 2 + smallH, small, next, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
            return;
        }

        // Main number: what's left of the step, or total distance on a free run / after the last step.
        var main;
        var mainLabel;
        if (step != null) {
            var left = _run.stepRemaining();
            main = step[Proto.S_DURATION_TYPE] == 0 ? Fmt.duration(left) : Fmt.stepDistance(left, _run.unitMeters, _run.units);
            var next = _run.nextStep();
            mainLabel = next != null ? "then " + next[Proto.S_TITLE] : "last step";
        } else {
            main = Fmt.distance(_run.distance, _run.unitMeters);
            mainLabel = _run.units;
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, big, main, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        y += bigH / 2 + smallH / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, small, mainLabel, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Pace (colored against the target) and distance or time.
        y += smallH / 2 + midH / 2;
        var drift = _run.compliance(5);
        dc.setColor(drift == 0 ? Graphics.COLOR_WHITE : (drift < 0 ? Graphics.COLOR_RED : Graphics.COLOR_BLUE), Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w / 5, y, mid, Fmt.pace(_run.currentPace, _run.unitMeters), Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        var right = step != null ? Fmt.distance(_run.distance, _run.unitMeters) : Fmt.duration(_run.movingTime);
        dc.drawText(cx + w / 5, y, mid, right, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        y += midH / 2 + smallH / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx - w / 5, y, small, "/" + _run.units, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
        dc.drawText(cx + w / 5, y, small, step != null ? _run.units : "time", Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);

        // Footer: total time and heart rate.
        var footer = step != null ? Fmt.duration(_run.movingTime) : "";
        if (_run.heartRate != null) {
            footer += (footer.length() > 0 ? "  " : "") + _run.heartRate + " bpm";
        }
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, h - smallH, small, footer, Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER);
    }

    private function drawSummary(dc as Dc) as Void {
        var w = dc.getWidth();
        var h = dc.getHeight();
        var cx = w / 2;
        var bandH = h * 30 / 100;
        var saved = _run.state == STATE_SAVED;
        var center = Graphics.TEXT_JUSTIFY_CENTER | Graphics.TEXT_JUSTIFY_VCENTER;

        dc.setColor(saved ? Zones.ACCENT : Graphics.COLOR_LT_GRAY, saved ? Zones.ACCENT : Graphics.COLOR_LT_GRAY);
        dc.fillRectangle(0, 0, w, bandH);
        dc.setColor(Graphics.COLOR_BLACK, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, bandH * 65 / 100, Graphics.FONT_SMALL, saved ? "Run saved" : "Run discarded", center);
        if (!saved) {
            return;
        }

        var small = Graphics.FONT_XTINY;
        var smallH = dc.getFontHeight(small);
        var big = numberFont(dc, h * 24 / 100);
        var bigH = dc.getFontHeight(big);
        var y = bandH + bigH / 2;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, big, Fmt.distance(_run.distance, _run.unitMeters), center);
        y += bigH / 2 + smallH / 2;
        dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, small, _run.units, center);
        y += smallH;
        dc.setColor(Graphics.COLOR_WHITE, Graphics.COLOR_TRANSPARENT);
        dc.drawText(cx, y, small, Fmt.duration(_run.movingTime) + "   " + Fmt.pace(_run.averagePace(), _run.unitMeters) + " /" + _run.units, center);

        var status;
        if (!Store.isWaiting(_run.runId)) {
            status = "Synced to phone";
            dc.setColor(Graphics.COLOR_GREEN, Graphics.COLOR_TRANSPARENT);
        } else if (getApp().link.reachable == false) {
            status = "Phone not reachable. Will retry.";
            dc.setColor(Graphics.COLOR_YELLOW, Graphics.COLOR_TRANSPARENT);
        } else {
            status = "Sending to phone...";
            dc.setColor(Graphics.COLOR_LT_GRAY, Graphics.COLOR_TRANSPARENT);
        }
        dc.drawText(cx, h - smallH * 3 / 2, small, status, center);
    }

    //! The largest number font no taller than `maxHeight`.
    private function numberFont(dc as Dc, maxHeight as Number) as Graphics.FontType {
        var fonts = [Graphics.FONT_NUMBER_HOT, Graphics.FONT_NUMBER_MEDIUM, Graphics.FONT_NUMBER_MILD];
        for (var i = 0; i < fonts.size(); i++) {
            if (dc.getFontHeight(fonts[i]) <= maxHeight) {
                return fonts[i];
            }
        }
        return Graphics.FONT_LARGE;
    }
}

//! START pauses and opens the run menu; BACK or LAP moves to the next step, like Garmin's own run app.
class RunDelegate extends WatchUi.BehaviorDelegate {
    private var _run as RunModel;

    function initialize(run as RunModel) {
        BehaviorDelegate.initialize();
        _run = run;
    }

    function onSelect() as Boolean {
        if (_run.state == STATE_READY) {
            _run.start();
        } else if (_run.isActive()) {
            _run.pause();
            showRunMenu(_run);
        } else {
            close();
        }
        return true;
    }

    function onBack() as Boolean {
        if (_run.state == STATE_RUNNING) {
            _run.lap();
        } else if (_run.state == STATE_PAUSED) {
            showRunMenu(_run);
        } else {
            if (_run.state == STATE_READY) {
                _run.finish(false);
            }
            close();
        }
        return true;
    }

    function onMenu() as Boolean {
        if (_run.isActive()) {
            _run.pause();
            showRunMenu(_run);
        }
        return true;
    }

    function onKey(event as WatchUi.KeyEvent) as Boolean {
        if (event.getKey() == WatchUi.KEY_LAP) {
            _run.lap();
            return true;
        }
        return false;
    }

    //! Ignore taps so a sweaty wrist can't pause the run.
    function onTap(event as WatchUi.ClickEvent) as Boolean {
        return true;
    }

    private function close() as Void {
        getApp().run = null;
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

function showRunMenu(run as RunModel) as Void {
    var menu = new WatchUi.Menu2({:title => "Paused"});
    menu.addItem(new WatchUi.MenuItem("Resume", null, :resume, null));
    menu.addItem(new WatchUi.MenuItem("Save", null, :save, null));
    menu.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
    WatchUi.pushView(menu, new RunMenuDelegate(run), WatchUi.SLIDE_UP);
}

class RunMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _run as RunModel;

    function initialize(run as RunModel) {
        Menu2InputDelegate.initialize();
        _run = run;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id == :resume) {
            _run.resume();
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :save) {
            _run.finish(true);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else if (id == :discard) {
            var confirm = new WatchUi.Menu2({:title => "Discard run?"});
            confirm.addItem(new WatchUi.MenuItem("Keep run", null, :keep, null));
            confirm.addItem(new WatchUi.MenuItem("Discard", null, :discard, null));
            WatchUi.pushView(confirm, new DiscardMenuDelegate(_run), WatchUi.SLIDE_LEFT);
        }
    }

    //! Backing out of the menu leaves the run paused.
    function onBack() as Void {
        WatchUi.popView(WatchUi.SLIDE_DOWN);
    }
}

class DiscardMenuDelegate extends WatchUi.Menu2InputDelegate {
    private var _run as RunModel;

    function initialize(run as RunModel) {
        Menu2InputDelegate.initialize();
        _run = run;
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        if (item.getId() == :discard) {
            _run.finish(false);
            // Close this menu and the run menu, back to the run screen showing "Run discarded".
            WatchUi.popView(WatchUi.SLIDE_IMMEDIATE);
            WatchUi.popView(WatchUi.SLIDE_DOWN);
        } else {
            WatchUi.popView(WatchUi.SLIDE_RIGHT);
        }
    }
}
