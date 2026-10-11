//
//  TrafficModels.swift
//  Sky Sentry
//
//  Core data types: ownship, traffic targets, threat evaluation and the
//  spherical geometry used to turn two lat/lon pairs into range and bearing.
//

import Foundation

// MARK: - Alert configuration

/// What the pilot can choose, which TCAS keeps firmly separate from what alerts
/// them. On a TCAS traffic display the pilot picks the range and the altitude
/// band — longer and wider in the cruise, tighter in the circuit to cut clutter
/// — while the alerting thresholds are set automatically from own altitude.
/// Those live in `AlertProfile`.
struct AlertConfig {

    // MARK: Display — the pilot's to choose

    /// Targets beyond this are not drawn; also the radius of the outer ring.
    var displayRangeNM: Double = 10.0
    /// Which slice of altitude to draw, as a TCAS traffic display does.
    var altitudeBand: AltitudeBand = .normal
    /// Which set of alerting thresholds to apply.
    var profileKind: AlertProfile.Kind = .generalAviation
    /// Where ownship sits, trading rear and lateral coverage for what is ahead.
    var forwardBias: ForwardBias = .centred

    var profile: AlertProfile { profileKind.profile }

    /// Ring radii, as fractions of the selected range so the picture keeps its
    /// shape whichever range is chosen.
    var innerRingNM: Double { displayRangeNM * 0.2 }
    var middleRingNM: Double { displayRangeNM * 0.5 }

    /// The ranges offered in settings. TCAS equivalents are 3, 5, 10, 20 and 40 nm.
    static let selectableRangesNM: [Double] = [5, 10, 20]

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

    // MARK: Persistence
    //
    // Display choices survive a relaunch. Re-picking range, altitude band and
    // bias before every flight is exactly the sort of step that gets forgotten.

    private enum Key {
        static let range = "displayRangeNM"
        static let band = "altitudeBand"
        static let profile = "alertProfile"
        static let bias = "forwardBias"
    }

    static func loaded() -> AlertConfig {
        var config = AlertConfig()
        let defaults = UserDefaults.standard

        let range = defaults.double(forKey: Key.range)
        if selectableRangesNM.contains(range) { config.displayRangeNM = range }
        if let raw = defaults.string(forKey: Key.band),
           let band = AltitudeBand(rawValue: raw) { config.altitudeBand = band }
        if let raw = defaults.string(forKey: Key.profile),
           let kind = AlertProfile.Kind(rawValue: raw) { config.profileKind = kind }
        if let raw = defaults.string(forKey: Key.bias),
           let bias = ForwardBias(rawValue: raw) { config.forwardBias = bias }
        return config
    }

    func save() {
        let defaults = UserDefaults.standard
        defaults.set(displayRangeNM, forKey: Key.range)
        defaults.set(altitudeBand.rawValue, forKey: Key.band)
        defaults.set(profileKind.rawValue, forKey: Key.profile)
        defaults.set(forwardBias.rawValue, forKey: Key.bias)
    }
}

// MARK: - Forward bias

/// Where ownship sits on the display.
///
/// Moving it down devotes more of the screen to what is ahead, which is where
/// the threats are for a faster aircraft. The scale stays uniform in every
/// direction — the picture is never stretched — so what actually changes is
/// that the same range is drawn larger ahead, at the cost of seeing less to the
/// sides and behind. Traffic pushed off the edge is not dropped: it is shown as
/// an arrowhead at the edge on the correct relative bearing, as a TCAS display
/// does with its half symbols.
enum ForwardBias: String, CaseIterable, Identifiable, Sendable {
    case centred
    case slight
    case strong

    var id: String { rawValue }

    var title: String {
        switch self {
        case .centred: return "Centred"
        case .slight:  return "Slight"
        case .strong:  return "Strong"
        }
    }

    /// How much bigger the picture is drawn than the largest circle that fits
    /// whole. Everything follows from this: the bigger the picture, the lower
    /// ownship has to sit for the full range to still be visible ahead, and the
    /// more is lost to the sides and behind. Setting the offset directly and
    /// deriving the size from it — the obvious way round — zooms in violently
    /// and strands traffic off the edges.
    var zoom: Double {
        switch self {
        case .centred: return 1.0
        case .slight:  return 1.50
        case .strong:  return 1.8
        }
    }

    var detail: String {
        switch self {
        case .centred: return "Equal all round"
        case .slight:  return "More ahead, about 7 nm to the sides"
        case .strong:  return "Most ahead, about 5 nm to the sides"
        }
    }
}

// MARK: - Altitude band

/// Which slice of altitude to show, mirroring the ABV / N / BLW selector on a
/// TCAS traffic display. This is a DISPLAY filter and nothing to do with
/// alerting: an aircraft outside the band is simply not drawn.
///
/// The ±9,900 ft limit is TCAS's own: relative altitude is shown in hundreds of
/// feet with two digits, so it cannot express more.
enum AltitudeBand: String, CaseIterable, Identifiable, Sendable {
    case normal
    case above
    case below
    case unrestricted

    var id: String { rawValue }

    var title: String {
        switch self {
        case .normal:       return "Normal"
        case .above:        return "Above"
        case .below:        return "Below"
        case .unrestricted: return "All"
        }
    }

    /// How far above us to show traffic, in feet.
    var ceilingFeet: Double {
        switch self {
        case .normal:       return 2700
        case .above:        return 9900
        case .below:        return 2700
        case .unrestricted: return 9900
        }
    }

    /// How far below us to show traffic, in feet.
    var floorFeet: Double {
        switch self {
        case .normal:       return 2700
        case .above:        return 2700
        case .below:        return 9900
        case .unrestricted: return 9900
        }
    }

    var detail: String {
        switch self {
        case .normal:       return "±2,700 ft"
        case .above:        return "+9,900 / −2,700 ft"
        case .below:        return "+2,700 / −9,900 ft"
        case .unrestricted: return "±9,900 ft"
        }
    }

    /// Relative altitude in feet, positive above.
    func includes(relativeAltitudeFeet: Int) -> Bool {
        let value = Double(relativeAltitudeFeet)
        return value <= ceilingFeet && value >= -floorFeet
    }
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

    /// Applies the TCAS-style test at this altitude band's thresholds.
    ///
    /// A target in range is at least an advisory; it becomes a caution or a
    /// warning only when the geometry says so — time to closest approach, with
    /// distance and altitude floors for the slow-closure cases that time alone
    /// misses. Range on its own no longer decides, which is why a target can be
    /// red while still outside the inner ring.
    static func evaluate(rangeNM: Double,
                         closureKnots: Double?,
                         relativeAltitudeFeet: Int?,
                         verticalClosureFPM: Double?,
                         level: SensitivityLevel,
                         config: AlertConfig) -> ThreatLevel {
        guard rangeNM <= config.displayRangeNM else { return .clear }

        let separation = relativeAltitudeFeet.map(Double.init)
        if AlertRule.isTriggered(rangeNM: rangeNM, closureKnots: closureKnots,
                                 verticalSeparationFeet: separation,
                                 verticalClosureFPM: verticalClosureFPM,
                                 thresholds: level.warning) {
            return .warning
        }
        if AlertRule.isTriggered(rangeNM: rangeNM, closureKnots: closureKnots,
                                 verticalSeparationFeet: separation,
                                 verticalClosureFPM: verticalClosureFPM,
                                 thresholds: level.caution) {
            return .caution
        }
        return .advisory
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
    /// Our own rate of climb or descent, needed to work out how fast the
    /// vertical gap to another aircraft is closing.
    var verticalSpeedFPM: Double?
    var lastUpdate: Date
}

// MARK: - Emitter category

/// What kind of thing is out there, straight from the GDL90 traffic report.
///
/// This arrives free in every report and needs no lookup, no database and no
/// internet — which matters, because a registration lookup would need all three.
/// It is also the part that actually changes a pilot's scan: a glider, a
/// helicopter and an airliner are looked for in different places, at different
/// speeds, with different closure.
enum EmitterCategory: UInt8, Sendable {
    case unknown = 0
    case light = 1
    case small = 2
    case large = 3
    case highVortexLarge = 4
    case heavy = 5
    case highlyManoeuvrable = 6
    case rotorcraft = 7
    case glider = 9
    case lighterThanAir = 10
    case parachutist = 11
    case ultralight = 12
    case uav = 14
    case spaceVehicle = 15
    case surfaceEmergencyVehicle = 17
    case surfaceServiceVehicle = 18
    case pointObstacle = 19
    case clusterObstacle = 20
    case lineObstacle = 21

    init(code: UInt8) {
        self = EmitterCategory(rawValue: code) ?? .unknown
    }

    /// Not aircraft: ground vehicles and obstacles are reported on the same
    /// datalink but are not traffic to avoid in the air, and showing a tethered
    /// balloon or an airfield service van as converging traffic would be absurd.
    var isAirborneTraffic: Bool {
        switch self {
        case .surfaceEmergencyVehicle, .surfaceServiceVehicle,
             .pointObstacle, .clusterObstacle, .lineObstacle:
            return false
        default:
            return true
        }
    }

    /// Short tag for the display, and nil when it would be noise.
    ///
    /// Most GA traffic is "light", which is the default assumption anyway, so
    /// labelling every arrow LIGHT would add clutter and tell the pilot nothing.
    /// Only categories that change what you are looking for get a tag.
    var shortLabel: String? {
        switch self {
        case .unknown, .light, .small:  return nil
        case .large, .highVortexLarge:  return "LARGE"
        case .heavy:                    return "HEAVY"
        case .highlyManoeuvrable:       return "FAST"
        case .rotorcraft:               return "HELI"
        case .glider:                   return "GLIDER"
        case .lighterThanAir:           return "BALLOON"
        case .parachutist:              return "CHUTE"
        case .ultralight:               return "MICRO"
        case .uav:                      return "DRONE"
        case .spaceVehicle:             return "SPACE"
        case .surfaceEmergencyVehicle,
             .surfaceServiceVehicle:    return "VEHICLE"
        case .pointObstacle,
             .clusterObstacle,
             .lineObstacle:             return "OBSTACLE"
        }
    }
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
    var category: EmitterCategory = .unknown
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

    /// "+12" / "-05" in hundreds of feet, the way a TCAS display reads. Nil
    /// when the aircraft is not reporting altitude — TCAS shows nothing at all
    /// in that case rather than implying a separation it does not know.
    var altitudeLabel: String? {
        guard let relativeAltitudeFeet else { return nil }
        let hundreds = Int((Double(relativeAltitudeFeet) / 100.0).rounded())
        if hundreds == 0 { return "00" }
        return String(format: "%@%02d", hundreds > 0 ? "+" : "-", abs(hundreds))
    }

    /// True when the aircraft is above us. Drives which side of the label the
    /// altitude is written on, so position says it as well as the sign does.
    var isAbove: Bool { (relativeAltitudeFeet ?? 0) >= 0 }

    /// Climb or descent arrow, shown only beyond 500 fpm — TCAS's threshold,
    /// below which the trend is not worth drawing attention to.
    var verticalTrend: String? {
        guard relativeAltitudeFeet != nil,
              let rate = target.verticalSpeedFPM, abs(rate) > 500 else { return nil }
        return rate > 0 ? "\u{2191}" : "\u{2193}"
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
