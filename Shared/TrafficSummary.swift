//
//  TrafficSummary.swift
//  Shared between Eyes Out (iOS) and the watch app
//
//  The watch does not receive GDL90 itself — the phone is on the SkyEcho's
//  Wi-Fi and does all the decoding and threat work. This is the small summary
//  that crosses to the wrist: one aircraft, the one worth acting on.
//
//  Deliberately tiny and dictionary-based. WatchConnectivity payloads should be
//  small and frequent, and a plain [String: Any] avoids any Codable version
//  skew between a phone and a watch running different builds.
//

import Foundation

/// Which way to turn your head. The display is track-up, so this is relative to
/// where the nose is pointing, not to north.
enum TrafficSide: Int, Sendable {
    case left = -1
    case right = 1
    /// Range known but direction unknown — a Mode S or bearingless FLARM contact.
    case unknown = 0
}

struct TrafficSummary: Equatable, Sendable {

    /// Mirrors ThreatLevel.rawValue on the phone: 0 clear, 1 advisory,
    /// 2 caution, 3 warning.
    var threatLevel: Int = 0
    var side: TrafficSide = .unknown
    var rangeNM: Double?
    var relativeAltitudeFeet: Int?
    var isConverging: Bool = false
    var secondsToCPA: Double?
    /// False when the phone has no usable picture — no receiver, or stale data.
    /// The watch must stay silent rather than imply the sky is clear.
    var hasPicture: Bool = false

    static let noPicture = TrafficSummary()

    // MARK: - Wire format

    private enum Key {
        static let threat = "t"
        static let side = "s"
        static let range = "r"
        static let altitude = "a"
        static let converging = "c"
        static let cpa = "p"
        static let hasPicture = "h"
    }

    var dictionary: [String: Any] {
        var payload: [String: Any] = [
            Key.threat: threatLevel,
            Key.side: side.rawValue,
            Key.converging: isConverging,
            Key.hasPicture: hasPicture,
        ]
        if let rangeNM { payload[Key.range] = rangeNM }
        if let relativeAltitudeFeet { payload[Key.altitude] = relativeAltitudeFeet }
        if let secondsToCPA { payload[Key.cpa] = secondsToCPA }
        return payload
    }

    init() { }

    init(dictionary: [String: Any]) {
        threatLevel = dictionary[Key.threat] as? Int ?? 0
        side = TrafficSide(rawValue: dictionary[Key.side] as? Int ?? 0) ?? .unknown
        rangeNM = dictionary[Key.range] as? Double
        relativeAltitudeFeet = dictionary[Key.altitude] as? Int
        isConverging = dictionary[Key.converging] as? Bool ?? false
        secondsToCPA = dictionary[Key.cpa] as? Double
        hasPicture = dictionary[Key.hasPicture] as? Bool ?? false
    }

    // MARK: - Convenience

    /// True when there is something worth buzzing about at all.
    var isAlerting: Bool {
        hasPicture && threatLevel >= 1 && rangeNM != nil
    }

    var rangeLabel: String {
        guard let rangeNM else { return "—" }
        return rangeNM < 10 ? String(format: "%.1f", rangeNM) : String(format: "%.0f", rangeNM)
    }

    var altitudeLabel: String? {
        guard let relativeAltitudeFeet else { return nil }
        return String(format: "%@%d ft", relativeAltitudeFeet >= 0 ? "+" : "-",
                      abs(relativeAltitudeFeet))
    }
}
