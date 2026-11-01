import Toybox.Lang;
import Toybox.WatchUi;

//! The app's home screen: upcoming workouts from the phone, a free run, and sync actions.
class WorkoutMenu extends WatchUi.Menu2 {
    var isVisible as Boolean = false;

    function initialize() {
        Menu2.initialize({:title => "Kadence"});
        var today = Fmt.today();
        var index = Store.workoutIndex();
        var shown = 0;
        for (var i = 0; i < index.size(); i++) {
            var entry = index[i] as Array;
            var day = entry[1] instanceof Number ? entry[1] as Number : 0;
            if (day >= today) {
                addItem(new WatchUi.MenuItem(entry[0] as String, Fmt.dayLabel(day), i, null));
                shown++;
            }
        }
        addItem(new WatchUi.MenuItem("Free run", "No structure", :free, null));
        var waiting = Store.outbox().size();
        if (waiting > 0) {
            addItem(new WatchUi.MenuItem("Send runs to phone", waiting.toString() + " waiting", :sync, null));
        } else if (shown == 0) {
            addItem(new WatchUi.MenuItem("Get workouts", "Open Kadence on your phone", :sync, null));
        }
    }

    function onShow() as Void {
        isVisible = true;
        Menu2.onShow();
    }

    function onHide() as Void {
        isVisible = false;
        Menu2.onHide();
    }
}

class WorkoutMenuDelegate extends WatchUi.Menu2InputDelegate {
    function initialize() {
        Menu2InputDelegate.initialize();
    }

    function onSelect(item as WatchUi.MenuItem) as Void {
        var id = item.getId();
        if (id instanceof Number) {
            startRun(Store.workout(id));
        } else if (id == :free) {
            startRun(null);
        } else if (id == :sync) {
            getApp().link.sync();
        }
    }

    private function startRun(workout as Dictionary?) as Void {
        var run = new RunModel(workout);
        getApp().run = run;
        WatchUi.pushView(new RunView(run), new RunDelegate(run), WatchUi.SLIDE_UP);
    }
}
