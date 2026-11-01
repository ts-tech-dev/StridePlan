import Toybox.Communications;
import Toybox.Lang;
import Toybox.WatchUi;

//! Messages to and from the StridePlan iPhone app. Outgoing messages are sent one at a time; if the phone can't be
//! reached the queue is dropped, and unacknowledged runs are sent again on the next launch or sync.
class PhoneLink {
    //! Each item is a message Dictionary, or `[runId, partIndex]` read from storage when its turn comes.
    private var _queue as Array = [];
    private var _sending as Boolean = false;
    //! Whether the last transmit reached the phone (null before the first attempt).
    var reachable as Boolean? = null;

    function initialize() {
    }

    function start() as Void {
        if (Communications has :registerForPhoneAppMessages) {
            Communications.registerForPhoneAppMessages(method(:onPhoneMessage));
        }
        sync();
    }

    //! Asks the phone for workouts and resends any runs it hasn't confirmed.
    function sync() as Void {
        enqueue({"t" => "hello", "v" => Proto.VERSION, "pending" => Store.outbox().size()});
        var ids = Store.outbox();
        for (var i = 0; i < ids.size(); i++) {
            sendRun(ids[i]);
        }
    }

    function sendRun(id as String) as Void {
        var count = Store.runPartCount(id);
        for (var i = 0; i < count; i++) {
            enqueue([id, i]);
        }
    }

    function onPhoneMessage(message as Communications.PhoneAppMessage) as Void {
        var data = message.data;
        if (!(data instanceof Dictionary)) {
            return;
        }
        var type = data["t"];
        if ("workouts".equals(type)) {
            Store.saveWorkouts(data);
            getApp().workoutsChanged();
        } else if ("ack".equals(type)) {
            var id = data["id"];
            if (id instanceof String) {
                Store.removeRun(id);
                WatchUi.requestUpdate();
            }
        }
    }

    private function enqueue(item) as Void {
        _queue.add(item);
        pump();
    }

    private function pump() as Void {
        while (!_sending && _queue.size() > 0) {
            var item = _queue[0];
            var message = item instanceof Array ? Store.runPart(item[0], item[1]) : item;
            if (message == null) {
                // The run was acknowledged while queued.
                _queue = _queue.slice(1, null);
                continue;
            }
            _sending = true;
            Communications.transmit(message, null, new TransmitListener(method(:onTransmitted)));
        }
    }

    function onTransmitted(ok as Boolean) as Void {
        _sending = false;
        reachable = ok;
        if (ok) {
            _queue = _queue.slice(1, null);
            pump();
        } else {
            _queue = [];
        }
        WatchUi.requestUpdate();
    }
}

class TransmitListener extends Communications.ConnectionListener {
    private var _done as Method;

    function initialize(done as Method) {
        ConnectionListener.initialize();
        _done = done;
    }

    function onComplete() as Void {
        _done.invoke(true);
    }

    function onError() as Void {
        _done.invoke(false);
    }
}
