//
//  TrafficModels.swift
//  Sky Sentry
//
//  Core data types: ownship, traffic targets, threat evaluation and the
//  spherical geometry used to turn two lat/lon pairs into range and bearing.
//

import Foundation

// MARK: - Alert configuration

/// Tunable thresholds for the display. Ranges are in nautical miles.
///
/// Threat level is currently a pure function of slant range. To move to a
/// time-based scheme later, add closure-time thresholds here and extend
/// `ThreatLevel.evaluate` to take the worse of the range and time verdicts.
struct AlertConfig {
    /// Targets beyond this are not drawn at all; also the radius of the outer ring.
    var displayRangeNM: Double = 10.0
    /// Inside this the whole screen goes amber.
    var cautionRangeNM: Double = 5.0
    /// Inside this the screen goes red and the offending arrow flashes.
    var warningRangeNM: Double = 2.0
    /// Ignore traffic more than this far above or below us (feet). Keeps airliners
    /// in the flight levels from cluttering a low-level picture.
    var verticalFilterFeet: Int = 5000
    /// Cap on how many arrows we draw at once, nearest first.
    var maxDisplayedTargets: Int = 12
    /// Drop a target that has not been heard from for this long.
    var targetStaleAfter: TimeInterval = 12.0

    // MARK: Constant bearing, decreasing range
    //
    // Two aircraft whose line of sight holds a steady compass bearing while the
    // gap closes are, by definition, heading for the same point in space. That
    // is the classic collision geometry, and it is the case that looks least
    // alarming out of the window because the other aircraft does not appear to
    // move across the windscreen.

    /// How close the other aircraft is projected to pass, in nautical miles,
    /// before we call it a collision risk.
    ///
    /// Thresholding the bearing rate directly does not work: a target crossing
    /// squarely abeam at 5 nm drifts only about 0.3 deg/s, which is
    /// indistinguishable from a constant bearing by rate alone. Projecting the
    /// closest point of approach separates the two properly, because it accounts
    /// for range and closure speed as well as the drift.
    var cpaMissDistanceNM: Double = 1.0
    /// Only warn about a projected conflict this close in time, so distant
    /// traffic that happens to line up does not sit on the display for minutes.
    var cpaWarnSeconds: Double = 120
    /// Ignore geometry this slow-closing; it is mostly noise.
    var cbdrMinClosureKnots: Double = 15
    /// Minimum samples and time span before we will call it, so a couple of
    /// noisy GPS positions cannot trigger a warning on their own.
    var cbdrMinSamples: Int = 5
    var cbdrMinSpan: TimeInterval = 5
    /// How much bearing history to keep per target.
    var cbdrWindow: TimeInterval = 12

    static let `default` = AlertConfig()
}

// MARK: - Threat level

enum ThreatLevel: Int, Comparable, Sendable {
    /// Out of range entirely — not shown.
    case clear = 0
    /// In range, but no cause for concern. Background stays green.
    case advisory = 1
    /// Inside the caution ring. Background amber.
    case caution = 2
    /// Inside the warning ring. Background red, arrow flashes.
    case warning = 3

    static func < (lhs: ThreatLevel, rhs: ThreatLevel) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    static func evaluate(rangeNM: Double, config: AlertConfig) -> ThreatLevel {
        if rangeNM <= config.warningRangeNM { return .warning }
        if rangeNM <= config.cautionRangeNM { return .caution }
        if rangeNM <= config.displayRangeNM { return .advisory }
        return .clear
    }

    /// One step worse, for traffic that is on a collision bearing. This is what
    /// buys the early warning: a converging target raises the alarm well before
    /// range alone would have done.
    var escalated: ThreatLevel {
        ThreatLevel(rawValue: min(rawValue + 1, ThreatLevel.warning.rawValue)) ?? self
    }
}

// MARK: - Ownship

/// Our own position, as reported by the GDL90 source (SkyEcho) rather than the phone.
struct Ownship: Equatable, Sendable {
    var latitude: Double
    var longitude: Double
    /// Pressure altitude in feet — the figure that is directly comparable with
    /// the altitude in other aircraft's traffic reports.
    var pressureAltitudeFeet: Int?
    /// Geometric (GPS) altitude in feet, from the ownship geometric altitude message.
    var geometricAltitudeFeet: Int?
    var trackDegrees: Double
    var groundSpeedKnots: Double
    var lastUpdate: Date
}

// MARK: - Traffic target

struct TrafficTarget: Identifiable, Equatable, Sendable {
    let icaoAddress: UInt32
    var callsign: String
    /// Position, when the source gives us one. ADS-B always does; a Mode S
    /// interrogation or a FLARM contact without bearing does not.
    var latitude: Double?
    var longitude: Double?
    /// Distance in nautical miles, for sources that can measure range but not
    /// direction — PilotAware's Mode S detection, or FLARM's PFLAU when it
    /// reports a bearingless contact. Ignored when a position is present.
    var rangeOnlyNM: Double?
    /// Pressure altitude in feet, nil when the target is not reporting altitude.
    var altitudeFeet: Int?
    var trackDegrees: Double?
    var groundSpeedKnots: Double?
    var verticalSpeedFPM: Double?
    var isAirborne: Bool
    var lastUpdate: Date

    var id: UInt32 { icaoAddress }

    /// Something short enough to print next to an arrow on a phone screen.
    var shortLabel: String {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces)
        if trimmed.isEmpty {
            return String(format: "%06X", icaoAddress)
        }
        // UK registrations come through as e.g. "GABCD" — show the tail number part.
        return trimmed.count > 5 ? String(trimmed.suffix(5)) : trimmed
    }
}

// MARK: - Resolved relative picture

/// A target with the relative geometry worked out, ready to draw.
struct TrafficSolution: Identifiable, Equatable, Sendable {
    let target: TrafficTarget
    /// Horizontal distance in nautical miles.
    let rangeNM: Double
    /// True bearing from us to the target, nil when the source cannot give one.
    let bearingTrue: Double?
    /// Bearing relative to our track, so 0 is straight ahead (the display is
    /// track-up). Nil means the range is known but the direction is not, which
    /// the display shows as a ring rather than an arrow.
    let relativeBearing: Double?
    /// Target altitude minus our altitude, in feet. Positive means above us.
    let relativeAltitudeFeet: Int?
    /// Threat level after any escalation for converging traffic.
    let threat: ThreatLevel
    /// Threat from range alone, before the converging escalation.
    let rangeThreat: ThreatLevel
    /// Holding a steady bearing while closing: on a collision course.
    let isConverging: Bool
    /// Closure rate in knots. Positive means the gap is shrinking.
    let closureKnots: Double?
    /// Seconds until the closest point of approach, if it is still ahead of us.
    let secondsToCPA: Double?
    /// How far apart we are projected to be at that moment.
    let missDistanceNM: Double?

    var id: UInt32 { target.icaoAddress }

    /// Countdown to the closest point of approach, for the arrow label.
    var cpaLabel: String? {
        guard let secondsToCPA, secondsToCPA > 0 else { return nil }
        return "\(Int(secondsToCPA.rounded()))s"
    }

    /// "+12" / "-05" in hundreds of feet, the way a TCAS display reads.
    var altitudeLabel: String? {
        guard let relativeAltitudeFeet else { return nil }
        let hundreds = Int((Double(relativeAltitudeFeet) / 100.0).rounded())
        if hundreds == 0 { return "  0" }
        return String(format: "%@%02d", hundreds > 0 ? "+" : "-", abs(hundreds))
    }

    var rangeLabel: String {
        rangeNM < 10 ? String(format: "%.1f", rangeNM) : String(format: "%.0f", rangeNM)
    }
}

// MARK: - Geometry

enum Geo {
    static let earthRadiusNM = 3440.065

    /// Great-circle distance in nautical miles.
    static func distanceNM(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dPhi = (lat2 - lat1) * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let a = sin(dPhi / 2) * sin(dPhi / 2)
            + cos(phi1) * cos(phi2) * sin(dLambda / 2) * sin(dLambda / 2)
        let c = 2 * atan2(sqrt(a), sqrt(1 - a))
        return earthRadiusNM * c
    }

    /// Initial great-circle bearing from point 1 to point 2, in degrees true.
    static func bearingDegrees(lat1: Double, lon1: Double, lat2: Double, lon2: Double) -> Double {
        let phi1 = lat1 * .pi / 180
        let phi2 = lat2 * .pi / 180
        let dLambda = (lon2 - lon1) * .pi / 180

        let y = sin(dLambda) * cos(phi2)
        let x = cos(phi1) * sin(phi2) - sin(phi1) * cos(phi2) * cos(dLambda)
        return (atan2(y, x) * 180 / .pi).normalizedDegrees
    }

    /// Point a given distance and bearing away from a start point.
    static func destination(lat: Double, lon: Double, bearingDegrees: Double,
                            distanceNM: Double) -> (lat: Double, lon: Double) {
        let delta = distanceNM / earthRadiusNM
        let theta = bearingDegrees * .pi / 180
        let phi1 = lat * .pi / 180
        let lambda1 = lon * .pi / 180

        let sinPhi2 = sin(phi1) * cos(delta) + cos(phi1) * sin(delta) * cos(theta)
        let phi2 = asin(sinPhi2)
        let lambda2 = lambda1 + atan2(sin(theta) * sin(delta) * cos(phi1),
                                      cos(delta) - sin(phi1) * sinPhi2)

        return (phi2 * 180 / .pi, ((lambda2 * 180 / .pi) + 540).truncatingRemainder(dividingBy: 360) - 180)
    }
}

extension Double {
    /// Wraps any angle into 0..<360.
    var normalizedDegrees: Double {
        let r = truncatingRemainder(dividingBy: 360)
        return r < 0 ? r + 360 : r
    }
}
