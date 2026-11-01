import Toybox.Lang;
import Toybox.Time;
import Toybox.Time.Gregorian;

module Fmt {
    //! "4:05" or "1:02:09".
    function duration(seconds as Numeric) as String {
        var s = seconds.toNumber();
        if (s < 0) {
            s = 0;
        }
        var h = s / 3600;
        var m = (s % 3600) / 60;
        var sec = s % 60;
        if (h > 0) {
            return h.format("%d") + ":" + m.format("%02d") + ":" + sec.format("%02d");
        }
        return m.format("%d") + ":" + sec.format("%02d");
    }

    //! Pace in the runner's unit from seconds per km, e.g. "4:35". Implausible paces show as "--:--".
    function pace(secondsPerKm as Numeric?, unitMeters as Float) as String {
        if (secondsPerKm == null || secondsPerKm <= 0 || secondsPerKm > 1800) {
            return "--:--";
        }
        var total = (secondsPerKm * unitMeters / 1000.0 + 0.5).toNumber();
        return (total / 60).format("%d") + ":" + (total % 60).format("%02d");
    }

    //! "4:30-4:45".
    function paceRange(fast as Numeric, slow as Numeric, unitMeters as Float) as String {
        return pace(fast, unitMeters) + "-" + pace(slow, unitMeters);
    }

    //! Total distance in the runner's unit, e.g. "5.24".
    function distance(meters as Numeric, unitMeters as Float) as String {
        return (meters / unitMeters).format("%.2f");
    }

    //! Distance left in a step: meters under 1 km for metric runners, otherwise the unit with 2 decimals.
    function stepDistance(meters as Numeric, unitMeters as Float, units as String) as String {
        if (units.equals("km") && meters < 1000) {
            return ((meters / 10.0).toNumber() * 10).format("%d") + " m";
        }
        return (meters / unitMeters).format("%.2f") + " " + units;
    }

    //! yyyymmdd for a moment in local time.
    function dayNumber(moment as Time.Moment) as Number {
        var info = Gregorian.info(moment, Time.FORMAT_SHORT);
        return (info.year as Number) * 10000 + (info.month as Number) * 100 + info.day;
    }

    function today() as Number {
        return dayNumber(Time.now());
    }

    //! "Today", "Tomorrow" or e.g. "Wed 5".
    function dayLabel(day as Number) as String {
        var now = Time.now();
        if (day == dayNumber(now)) {
            return "Today";
        }
        if (day == dayNumber(now.add(new Time.Duration(86400)))) {
            return "Tomorrow";
        }
        var moment = Gregorian.moment({:year => day / 10000, :month => (day / 100) % 100, :day => day % 100, :hour => 12});
        var info = Gregorian.info(moment, Time.FORMAT_MEDIUM);
        return info.day_of_week + " " + info.day;
    }
}

//! Pace zone colors, matching ZonePalette in the iPhone app.
module Zones {
    const ACCENT = 0xFF5C29;

    function color(key) as Number {
        if ("walk".equals(key)) { return 0x8F99A8; }
        if ("recovery".equals(key)) { return 0x6BA8DB; }
        if ("easy".equals(key)) { return 0x33BD7A; }
        if ("steady".equals(key)) { return 0x1AADB3; }
        if ("tempo".equals(key)) { return 0xFABD1A; }
        if ("threshold".equals(key)) { return 0xFF851F; }
        if ("interval".equals(key)) { return 0xF0424D; }
        if ("repetition".equals(key)) { return 0xA35CF0; }
        if ("race".equals(key)) { return 0xEB338F; }
        return ACCENT;
    }
}
