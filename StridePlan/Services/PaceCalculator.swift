import Foundation

/// VDOT-style pace math (after Daniels & Gilbert) plus a Riegel race-time predictor.
enum PaceCalculator {

    // MARK: VDOT

    /// Oxygen cost (ml/kg/min) of running at `velocity` meters per minute.
    static func oxygenCost(velocity v: Double) -> Double {
        -4.60 + 0.182258 * v + 0.000104 * v * v
    }

    /// Fraction of VO₂max that can be sustained for a race lasting `minutes`.
    static func sustainableFraction(minutes t: Double) -> Double {
        0.8 + 0.1894393 * exp(-0.012778 * t) + 0.2989558 * exp(-0.1932605 * t)
    }

    /// VDOT for a performance. Returns nil for nonsensical inputs.
    static func vdot(distanceMeters: Double, timeSeconds: Double) -> Double? {
        guard distanceMeters >= 800, timeSeconds > 60 else { return nil }
        let value = rawVDOT(distanceMeters: distanceMeters, timeSeconds: timeSeconds)
        guard value.isFinite, (15...90).contains(value) else { return nil }
        return value
    }

    private static func rawVDOT(distanceMeters: Double, timeSeconds: Double) -> Double {
        let minutes = timeSeconds / 60
        return oxygenCost(velocity: distanceMeters / minutes) / sustainableFraction(minutes: minutes)
    }

    /// Velocity (m/min) whose oxygen cost equals `vo2`. Inverse of `oxygenCost`.
    static func velocity(forOxygenCost vo2: Double) -> Double {
        let a = 0.000104, b = 0.182258, c = -4.60 - vo2
        return (-b + sqrt(b * b - 4 * a * c)) / (2 * a)
    }

    /// Pace (sec/km) when running at `fraction` of VDOT.
    static func pace(vdot: Double, fraction: Double) -> Double {
        60_000 / velocity(forOxygenCost: vdot * fraction)
    }

    /// Predicted race time (seconds) for `distanceMeters` at a given VDOT, solved by bisection.
    static func predictedTime(vdot target: Double, distanceMeters: Double) -> Double {
        var low = distanceMeters / 1000 * 120    // 2:00/km
        var high = distanceMeters / 1000 * 1200  // 20:00/km
        for _ in 0..<80 {
            let mid = (low + high) / 2
            let value = rawVDOT(distanceMeters: distanceMeters, timeSeconds: mid)
            // Higher VDOT means faster (shorter) time.
            if value > target { low = mid } else { high = mid }
        }
        return (low + high) / 2
    }

    // MARK: Riegel

    /// Riegel endurance model: t2 = t1 × (d2 / d1)^1.06
    static func riegel(timeSeconds: Double, fromMeters d1: Double, toMeters d2: Double, exponent: Double = 1.06) -> Double {
        timeSeconds * pow(d2 / d1, exponent)
    }

    // MARK: Zones

    /// Builds pace zones from the best available input.
    /// - Training zones come from the recent result when present, else from the goal time.
    /// - Race pace comes from the goal time when present, else the prediction for `raceDistance`.
    /// - Without either input, returns effort-only zones.
    static func zones(
        reference: RaceResult?,
        goalTimeSeconds: Double? = nil,
        raceDistanceMeters: Double? = nil,
        level: ExperienceLevel
    ) -> PaceZones {
        let referenceVDOT = reference.flatMap { vdot(distanceMeters: $0.distanceMeters, timeSeconds: $0.timeSeconds) }
        let goalVDOT: Double? = {
            guard let goalTimeSeconds, let raceDistanceMeters else { return nil }
            return vdot(distanceMeters: raceDistanceMeters, timeSeconds: goalTimeSeconds)
        }()

        guard let trainingVDOT = referenceVDOT ?? goalVDOT else {
            return .effortOnly(level: level)
        }

        var ranges: [PaceZoneKind: PaceRange] = [:]
        for zone in PaceZoneKind.allCases {
            guard let fractions = zone.vdotFractionRange else { continue }
            ranges[zone] = PaceRange(
                fast: pace(vdot: trainingVDOT, fraction: fractions.upperBound),
                slow: pace(vdot: trainingVDOT, fraction: fractions.lowerBound)
            )
        }
        if let easy = ranges[.easy] {
            ranges[.walk] = PaceRange(fast: max(easy.slow + 120, 540), slow: max(easy.slow + 300, 720))
        }

        if let raceDistanceMeters {
            let racePace: Double
            if let goalTimeSeconds, goalVDOT != nil {
                racePace = goalTimeSeconds / (raceDistanceMeters / 1000)
            } else {
                racePace = predictedTime(vdot: trainingVDOT, distanceMeters: raceDistanceMeters) / (raceDistanceMeters / 1000)
            }
            ranges[.race] = PaceRange(fast: racePace - 3, slow: racePace + 3)
        }

        return PaceZones(vdot: trainingVDOT, ranges: ranges, level: level)
    }
}
