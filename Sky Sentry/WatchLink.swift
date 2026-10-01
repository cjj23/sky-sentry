//
//  WatchLink.swift
//  Eyes Out
//
//  Sends the traffic picture to the watch. The phone does all the work — it is
//  the one on the SkyEcho's Wi-Fi — and the watch only receives a summary of the
//  single aircraft worth acting on.
//
//  Messages are small and throttled. WatchConnectivity is not a firehose, and a
//  pilot does not need a list on their wrist: they need to know which way to
//  look, and how urgently.
//

import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchLink: NSObject {

    private(set) var isPaired = false
    private(set) var isWatchAppInstalled = false
    private(set) var isReachable = false

    private var lastSent: TrafficSummary?
    private var lastSendAt: Date?
    /// The display recomputes at 4 Hz; the wrist does not need that.
    private let minimumInterval: TimeInterval = 1.0

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
    }

    /// Builds the summary from the current picture and sends it if it has moved on.
    func update(solutions: [TrafficSolution], overallThreat: ThreatLevel, hasPicture: Bool) {
        var summary = TrafficSummary()
        summary.hasPicture = hasPicture

        // Same prioritisation as the display: converging first, otherwise nearest.
        let subject = solutions.first(where: \.isConverging)
            ?? solutions.min(by: { $0.rangeNM < $1.rangeNM })

        if hasPicture, let subject {
            summary.threatLevel = overallThreat.rawValue
            summary.rangeNM = subject.rangeNM
            summary.relativeAltitudeFeet = subject.relativeAltitudeFeet
            summary.isConverging = subject.isConverging
            summary.secondsToCPA = subject.secondsToCPA
            summary.side = Self.side(forRelativeBearing: subject.relativeBearing)
        }

        send(summary)
    }

    /// Splits the circle down the nose: anything on the right half is a right
    /// turn of the head, anything on the left half a left one. Dead ahead falls
    /// to the right by the tie-break, which is harmless — the aircraft is in
    /// front either way.
    static func side(forRelativeBearing bearing: Double?) -> TrafficSide {
        guard let bearing else { return .unknown }
        let normalised = bearing.normalizedDegrees
        return normalised < 180 ? .right : .left
    }

    // MARK: - Sending

    private func send(_ summary: TrafficSummary) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated else { return }

        // Always push a change in alert state straight through; otherwise respect
        // the throttle so a steadily closing target does not flood the link.
        let changedState = lastSent.map {
            $0.side != summary.side
                || $0.threatLevel != summary.threatLevel
                || $0.isConverging != summary.isConverging
                || $0.hasPicture != summary.hasPicture
        } ?? true

        if !changedState, let lastSendAt, Date().timeIntervalSince(lastSendAt) < minimumInterval {
            return
        }

        lastSent = summary
        lastSendAt = Date()
        let payload = summary.dictionary

        if session.isReachable {
            // Live and immediate while the watch app is up.
            session.sendMessage(payload, replyHandler: nil, errorHandler: nil)
        } else {
            // Latest-state-only fallback, so the watch is correct when it wakes.
            try? session.updateApplicationContext(payload)
        }
    }
}

// MARK: - WCSessionDelegate

extension WatchLink: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        let reachable = session.isReachable
        Task { @MainActor in
            self.isPaired = paired
            self.isWatchAppInstalled = installed
            self.isReachable = reachable
        }
    }

    nonisolated func sessionDidBecomeInactive(_ session: WCSession) { }

    nonisolated func sessionDidDeactivate(_ session: WCSession) {
        // Required on iOS: reactivate so a newly paired watch is picked up.
        session.activate()
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        let paired = session.isPaired
        let installed = session.isWatchAppInstalled
        Task { @MainActor in
            self.isPaired = paired
            self.isWatchAppInstalled = installed
        }
    }
}
