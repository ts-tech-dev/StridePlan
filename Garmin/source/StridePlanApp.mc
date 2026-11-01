import Toybox.Application;
import Toybox.Lang;
import Toybox.WatchUi;

//! StridePlan for Garmin: runs the workouts planned in the iPhone app and sends the results back.
class StridePlanApp extends Application.AppBase {
    var link as PhoneLink;
    //! The run on screen, if any.
    var run as RunModel? = null;
    private var _menu as WorkoutMenu? = null;

    function initialize() {
        AppBase.initialize();
        link = new PhoneLink();
    }

    function onStart(state as Dictionary?) as Void {
        link.start();
    }

    function onStop(state as Dictionary?) as Void {
        // Never lose a run in progress if the app is closed.
        var current = run;
        if (current != null && current.isActive()) {
            current.finish(true);
        }
    }

    function getInitialView() as [Views] or [Views, InputDelegates] {
        _menu = new WorkoutMenu();
        return [_menu, new WorkoutMenuDelegate()];
    }

    //! New workouts arrived from the phone: rebuild the list if it's what's on screen.
    function workoutsChanged() as Void {
        var menu = _menu;
        if (menu != null && menu.isVisible) {
            _menu = new WorkoutMenu();
            WatchUi.switchToView(_menu, new WorkoutMenuDelegate(), WatchUi.SLIDE_IMMEDIATE);
        }
    }
}

function getApp() as StridePlanApp {
    return Application.getApp() as StridePlanApp;
}
