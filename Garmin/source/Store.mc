import Toybox.Application;
import Toybox.Lang;

//! Message format shared with the phone. Keep in sync with StridePlan/Services/GarminProtocol.swift.
module Proto {
    const VERSION = 1;
    //! Route/sample points per chunk message (GarminProtocol.chunkPoints).
    const CHUNK_POINTS = 60;

    // Fields of each step array (GarminProtocol.StepField).
    const S_KIND = 0;
    const S_TITLE = 1;
    const S_ZONE_KEY = 2;
    const S_ZONE_NAME = 3;
    //! 0 = time in seconds, 1 = distance in meters.
    const S_DURATION_TYPE = 4;
    const S_DURATION = 5;
    //! Target pace in seconds per km; 0 when the step has no pace target.
    const S_FAST = 6;
    const S_SLOW = 7;
}

//! What the watch keeps between launches: upcoming workouts from the phone, and finished runs
//! (as ready-to-send messages) until the phone acknowledges them.
module Store {
    const MAX_WORKOUTS = 7;

    //! Replaces the stored workouts with the list from a phone `workouts` message.
    function saveWorkouts(message as Dictionary) as Void {
        var list = message["list"];
        if (!(list instanceof Array)) {
            return;
        }
        var count = list.size() < MAX_WORKOUTS ? list.size() : MAX_WORKOUTS;
        var index = [];
        for (var i = 0; i < count; i++) {
            var workout = list[i];
            if (workout instanceof Dictionary) {
                Storage.setValue("w" + index.size(), workout);
                index.add([workout["title"], workout["day"]]);
            }
        }
        for (var i = index.size(); i < MAX_WORKOUTS; i++) {
            Storage.deleteValue("w" + i);
        }
        Storage.setValue("windex", index);
        Storage.setValue("units", message["units"]);
        Storage.setValue("cues", message["cues"]);
    }

    //! `[[title, yyyymmdd], …]`, one per stored workout, for the workout list.
    function workoutIndex() as Array {
        var value = Storage.getValue("windex");
        return value instanceof Array ? value : [];
    }

    function workout(index as Number) as Dictionary? {
        var value = Storage.getValue("w" + index);
        return value instanceof Dictionary ? value : null;
    }

    //! "km" or "mi", as set on the phone.
    function units() as String {
        var value = Storage.getValue("units");
        return value instanceof String ? value : "km";
    }

    //! Effort description per zone key, shown when a step has no pace target.
    function cues() as Dictionary {
        var value = Storage.getValue("cues");
        return value instanceof Dictionary ? value : {};
    }

    // MARK: Outbox

    //! Ids of finished runs the phone hasn't acknowledged yet.
    function outbox() as Array {
        var value = Storage.getValue("outbox");
        return value instanceof Array ? value : [];
    }

    //! Part 0 is the run header, parts 1… are its chunks.
    function saveRunPart(id as String, index as Number, message as Dictionary) as Void {
        Storage.setValue("r" + id + ":" + index, message);
    }

    //! Marks a run's parts as complete and queues it for the phone.
    function addToOutbox(id as String, partCount as Number) as Void {
        Storage.setValue("r" + id + ":n", partCount);
        var ids = outbox();
        ids.add(id);
        Storage.setValue("outbox", ids);
    }

    function runPartCount(id as String) as Number {
        var value = Storage.getValue("r" + id + ":n");
        return value instanceof Number ? value : 0;
    }

    function runPart(id as String, index as Number) as Dictionary? {
        var value = Storage.getValue("r" + id + ":" + index);
        return value instanceof Dictionary ? value : null;
    }

    function isWaiting(id as String) as Boolean {
        var ids = outbox();
        for (var i = 0; i < ids.size(); i++) {
            if (id.equals(ids[i])) {
                return true;
            }
        }
        return false;
    }

    //! Deletes an acknowledged run.
    function removeRun(id as String) as Void {
        var count = runPartCount(id);
        for (var i = 0; i < count; i++) {
            Storage.deleteValue("r" + id + ":" + i);
        }
        Storage.deleteValue("r" + id + ":n");
        var remaining = [];
        var ids = outbox();
        for (var i = 0; i < ids.size(); i++) {
            if (!id.equals(ids[i])) {
                remaining.add(ids[i]);
            }
        }
        Storage.setValue("outbox", remaining);
    }
}
