//
//  WatchTrafficModel.swift
//  Eyes Out Watch App
//
//  Receives the traffic summary from the phone and drives the haptics.
//

import Foundation
import Observation
import WatchConnectivity

@MainActor
@Observable
final class WatchTrafficModel: NSObject {

    private(set) var summary = TrafficSummary.noPicture
    private(set) var lastUpdate: Date?
    private(set) var isReachable = false

    /// Haptics can be silenced from the watch without touching the phone.
    var hapticsEnabled = true {
        didSet { if !hapticsEnabled { alerter.stop() } }
    }

    private let alerter = HapticAlerter()

    /// The phone sends about once a second; treat silence as loss of picture
    /// rather than as quiet skies.
    private var isStale: Bool {
        guard let lastUpdate else { return true }
        return Date().timeIntervalSince(lastUpdate) > 6
    }

    var displaySummary: TrafficSummary {
        isStale ? .noPicture : summary
    }

    func start() {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        alerter.start()
    }

    private func apply(_ incoming: TrafficSummary) {
        summary = incoming
        lastUpdate = Date()
        alerter.update(summary: hapticsEnabled ? incoming : .noPicture)
    }
}

// MARK: - WCSessionDelegate

extension WatchTrafficModel: WCSessionDelegate {

    nonisolated func session(_ session: WCSession,
                             activationDidCompleteWith state: WCSessionActivationState,
                             error: Error?) {
        let reachable = session.isReachable
        Task { @MainActor in self.isReachable = reachable }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        let reachable = session.isReachable
        Task { @MainActor in
            self.isReachable = reachable
            // Losing the phone is losing the picture. Stop buzzing immediately
            // rather than repeating the last thing we heard.
            if !reachable { self.alerter.stop() }
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        let incoming = TrafficSummary(dictionary: message)
        Task { @MainActor in self.apply(incoming) }
    }

    nonisolated func session(_ session: WCSession,
                             didReceiveApplicationContext context: [String: Any]) {
        let incoming = TrafficSummary(dictionary: context)
        Task { @MainActor in self.apply(incoming) }
    }
}
