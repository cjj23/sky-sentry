//
//  AlertProfile.swift
//  Eyes Out
//
//  Alerting thresholds, modelled on TCAS II v7.1.
//
//  TCAS draws a line this app had blurred: what you SEE and what ALERTS you are
//  different things, controlled differently.
//
//  * Display range and altitude band are chosen by the pilot — longer ranges and
//    wider altitude bands in the cruise, tighter in the circuit to cut clutter.
//    Those live in AlertConfig.
//
//  * Alert thresholds are NOT pilot-selectable in TCAS. The system picks a
//    sensitivity level from its own altitude, because the trade-off between
//    protection and nuisance alerts is the thing the designers tuned, and a
//    dial invites mis-setting. That is what this file does.
//
//  The alerting rule itself is TCAS's:
//
//      alert when (range tau <= T  OR  range <= DMOD)
//             AND (vertical tau <= T  OR  |vertical separation| <= ZTHR)
//
//  Tau is time-to-go to closest approach rather than distance. DMOD and ZTHR are
//  the floors that make it work at low closure rates: without them an aircraft
//  closing slowly can get very near without ever crossing a tau boundary, which
//  is precisely the slow-overtake case the booklet calls out.
//

import Foundation

// MARK: - Thresholds

/// One alerting band. TCAS uses a single tau value for both the range and the
/// vertical test, with separate distance and altitude floors.
struct AlertThresholds: Equatable, Sendable {
    /// Seconds to closest approach at which to alert.
    var tauSeconds: Double
    /// Range floor in nautical miles, for encounters closing too slowly for tau
    /// to fire. TCAS calls this DMOD.
    var dmodNM: Double
    /// Vertical floor in feet, for the same reason. TCAS calls this ZTHR.
    var zthrFeet: Double
}

/// The thresholds that apply in one band of own altitude.
struct SensitivityLevel: Equatable, Sendable, Identifiable {
    /// Lowest own pressure altitude at which this level applies, in feet.
    var floorFeet: Double
    var caution: AlertThresholds
    var warning: AlertThresholds

    var id: Double { floorFeet }
}

// MARK: - Profile

struct AlertProfile: Equatable, Sendable {

    enum Kind: String, CaseIterable, Identifiable, Sendable {
        case generalAviation
        case tcasII

        var id: String { rawValue }

        var title: String {
            switch self {
            case .generalAviation: return "General aviation"
            case .tcasII:          return "TCAS II"
            }
        }

        var detail: String {
            switch self {
            case .generalAviation:
                return "Alerts earlier than TCAS. Seeing an aircraft out of the "
                     + "window takes far longer than flying a resolution advisory, "
                     + "so the thresholds allow time to look, find it and decide."
            case .tcasII:
                return "The published TCAS II v7.1 thresholds. Tighter, and tuned "
                     + "for airliners with coordinated manoeuvres rather than for "
                     + "see and avoid. Included for comparison."
            }
        }

        var profile: AlertProfile {
            switch self {
            case .generalAviation: return .generalAviation
            case .tcasII:          return .tcasII
            }
        }
    }

    var kind: Kind
    /// Ordered by altitude, lowest first.
    var levels: [SensitivityLevel]

    /// The band that applies at this own altitude. Falls back to the lowest
    /// band when we have no altitude, which is the conservative choice: tighter
    /// thresholds mean fewer alerts, not more, and we should not claim
    /// protection we cannot justify.
    func level(forOwnAltitudeFeet altitude: Double?) -> SensitivityLevel {
        guard let altitude else { return levels[0] }
        return levels.last(where: { altitude >= $0.floorFeet }) ?? levels[0]
    }

    // MARK: Published TCAS II v7.1 values
    //
    // From Table 2, "Sensitivity Level Definition and Alarm Thresholds", in the
    // Introduction to TCAS II v7.1 booklet.
    //
    // We borrow TCAS's THRESHOLDS, not its output. This app never issues a
    // resolution advisory and never tells a pilot to climb or descend: red means
    // "look for this one now", not "manoeuvre". TCAS is also a far more robust
    // system — it interrogates transponders and coordinates with the other
    // aircraft, where this only hears whatever ADS-B happens to be broadcast.
    // The caution band is taken from TCAS's Traffic Advisory thresholds and the
    // warning band from its Resolution Advisory thresholds purely because those
    // are the two tested sets of numbers available.
    //
    // SL2 (below 1000 ft AGL) is omitted: it inhibits RAs entirely and is set
    // from a radio altimeter, which this app does not have.

    static let tcasII = AlertProfile(kind: .tcasII, levels: [
        // SL3: 1000–2350 ft
        SensitivityLevel(floorFeet: 0,
                         caution: AlertThresholds(tauSeconds: 25, dmodNM: 0.33, zthrFeet: 850),
                         warning: AlertThresholds(tauSeconds: 15, dmodNM: 0.20, zthrFeet: 600)),
        // SL4: 2350–5000 ft
        SensitivityLevel(floorFeet: 2350,
                         caution: AlertThresholds(tauSeconds: 30, dmodNM: 0.48, zthrFeet: 850),
                         warning: AlertThresholds(tauSeconds: 20, dmodNM: 0.35, zthrFeet: 600)),
        // SL5: 5000–10000 ft
        SensitivityLevel(floorFeet: 5000,
                         caution: AlertThresholds(tauSeconds: 40, dmodNM: 0.75, zthrFeet: 850),
                         warning: AlertThresholds(tauSeconds: 25, dmodNM: 0.55, zthrFeet: 600)),
        // SL6: 10000–20000 ft
        SensitivityLevel(floorFeet: 10000,
                         caution: AlertThresholds(tauSeconds: 45, dmodNM: 1.00, zthrFeet: 850),
                         warning: AlertThresholds(tauSeconds: 30, dmodNM: 0.80, zthrFeet: 600)),
        // SL7: above 20000 ft
        SensitivityLevel(floorFeet: 20000,
                         caution: AlertThresholds(tauSeconds: 48, dmodNM: 1.30, zthrFeet: 850),
                         warning: AlertThresholds(tauSeconds: 35, dmodNM: 1.10, zthrFeet: 700)),
    ])

    // MARK: General aviation values
    //
    // The TCAS structure with longer times and larger floors. These are a
    // judgement, not a standard: TCAS alerts a crew who will fly a coordinated
    // manoeuvre, whereas this app alerts a pilot who must first FIND the
    // aircraft out of the window. The usual figure for acquiring and reacting to
    // a small aircraft visually is of the order of 12 seconds before any
    // manoeuvre begins, so a 30-second TCAS traffic advisory leaves very little
    // margin for see and avoid.
    //
    // Bands are tighter low down, where circuit traffic would otherwise alert
    // constantly, and wider in the cruise where closing speeds are higher.

    static let generalAviation = AlertProfile(kind: .generalAviation, levels: [
        // Circuit and low level.
        SensitivityLevel(floorFeet: 0,
                         caution: AlertThresholds(tauSeconds: 45, dmodNM: 1.5, zthrFeet: 1200),
                         warning: AlertThresholds(tauSeconds: 25, dmodNM: 0.6, zthrFeet: 600)),
        // Transit.
        SensitivityLevel(floorFeet: 3000,
                         caution: AlertThresholds(tauSeconds: 60, dmodNM: 2.0, zthrFeet: 1500),
                         warning: AlertThresholds(tauSeconds: 30, dmodNM: 1.0, zthrFeet: 800)),
        // Higher, faster.
        SensitivityLevel(floorFeet: 10000,
                         caution: AlertThresholds(tauSeconds: 75, dmodNM: 3.0, zthrFeet: 1500),
                         warning: AlertThresholds(tauSeconds: 40, dmodNM: 1.5, zthrFeet: 800)),
    ])
}

// MARK: - Evaluation

enum AlertRule {

    /// TCAS's modified-tau test, applied to one threshold band.
    ///
    /// Both the horizontal and the vertical criterion must be met, which is what
    /// stops traffic a long way above from alerting merely because it is close
    /// in plan, and traffic far away laterally from alerting merely because it
    /// is co-altitude.
    static func isTriggered(rangeNM: Double,
                            closureKnots: Double?,
                            verticalSeparationFeet: Double?,
                            verticalClosureFPM: Double?,
                            thresholds: AlertThresholds) -> Bool {
        horizontalTriggered(rangeNM: rangeNM, closureKnots: closureKnots, thresholds: thresholds)
            && verticalTriggered(separationFeet: verticalSeparationFeet,
                                 closureFPM: verticalClosureFPM,
                                 thresholds: thresholds)
    }

    static func horizontalTriggered(rangeNM: Double,
                                    closureKnots: Double?,
                                    thresholds: AlertThresholds) -> Bool {
        // The DMOD floor alone covers the slow-closure case.
        if rangeNM <= thresholds.dmodNM { return true }
        guard let closureKnots, closureKnots > 0 else { return false }
        return rangeTau(rangeNM: rangeNM, closureKnots: closureKnots) <= thresholds.tauSeconds
    }

    static func verticalTriggered(separationFeet: Double?,
                                  closureFPM: Double?,
                                  thresholds: AlertThresholds) -> Bool {
        // No altitude from the target: we cannot rule it out, so we do not.
        guard let separationFeet else { return true }
        if abs(separationFeet) <= thresholds.zthrFeet { return true }
        guard let closureFPM, closureFPM > 0 else { return false }
        return verticalTau(separationFeet: separationFeet, closureFPM: closureFPM)
            <= thresholds.tauSeconds
    }

    /// Slant range (nm) divided by closing speed (kt), times 3600.
    static func rangeTau(rangeNM: Double, closureKnots: Double) -> Double {
        guard closureKnots > 0 else { return .infinity }
        return rangeNM / closureKnots * 3600
    }

    /// Altitude separation (feet) divided by vertical closing speed (ft/min), times 60.
    static func verticalTau(separationFeet: Double, closureFPM: Double) -> Double {
        guard closureFPM > 0 else { return .infinity }
        return abs(separationFeet) / closureFPM * 60
    }
}
