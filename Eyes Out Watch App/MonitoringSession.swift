//
//  MonitoringSession.swift
//  Eyes Out Watch App
//
//  Keeps the watch app alive with the wrist down, so haptics keep playing when
//  you are not looking at it. That is the whole point: a traffic alerter that
//  only works while you stare at your wrist is useless.
//
//  watchOS has no way to WAKE a closed app on an event, so this is arm-before-
//  flight rather than something that springs to life. The pilot taps Start
//  Monitoring at the hold, the way they would set a transponder code.
//
//  Within an extended runtime session, lowering the wrist turns the screen off
//  but the process is NOT suspended and may still play haptics. Leaving the app
//  with the Digital Crown ends the session, and watchOS caps its length, so the
//  session warns before it expires and asks to be re-armed.
//

import Foundation
import Observation
import WatchKit

@MainActor
@Observable
final class MonitoringSession: NSObject {

    enum State: Equatable {
        case idle
        case running
        /// watchOS has signalled that the session is about to end.
        case expiring
    }

    private(set) var state: State = .idle
    private(set) var startedAt: Date?
    private(set) var lastEndReason: String?

    private var session: WKExtendedRuntimeSession?

    /// Fired when the session is about to expire, so the alerter can buzz a
    /// distinct pattern — the pilot needs telling without looking.
    var onExpiryWarning: (() -> Void)?

    var isArmed: Bool { state != .idle }

    /// How long it has been running, for the display.
    var elapsed: TimeInterval {
        guard let startedAt else { return 0 }
        return Date().timeIntervalSince(startedAt)
    }

    // MARK: - Arming

    func arm() {
        guard session == nil else { return }

        let session = WKExtendedRuntimeSession()
        session.delegate = self
        self.session = session
        lastEndReason = nil
        session.start()
    }

    func disarm() {
        session?.invalidate()
        session = nil
        state = .idle
        startedAt = nil
    }
}

// MARK: - WKExtendedRuntimeSessionDelegate

extension MonitoringSession: WKExtendedRuntimeSessionDelegate {

    nonisolated func extendedRuntimeSessionDidStart(_ session: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.state = .running
            self.startedAt = Date()
        }
    }

    nonisolated func extendedRuntimeSessionWillExpire(_ session: WKExtendedRuntimeSession) {
        Task { @MainActor in
            self.state = .expiring
            self.onExpiryWarning?()
        }
    }

    nonisolated func extendedRuntimeSession(_ session: WKExtendedRuntimeSession,
                                            didInvalidateWith reason: WKExtendedRuntimeSessionInvalidationReason,
                                            error: Error?) {
        let description = Self.describe(reason)
        Task { @MainActor in
            self.session = nil
            self.state = .idle
            self.startedAt = nil
            self.lastEndReason = description
        }
    }

    nonisolated private static func describe(_ reason: WKExtendedRuntimeSessionInvalidationReason) -> String {
        switch reason {
        case .none:                     return "Stopped"
        case .sessionInProgress:        return "A session was already running"
        case .expired:                  return "Session time ran out — re-arm to continue"
        case .resignedFrontmost:        return "You left the app — re-arm to continue"
        case .suppressedBySystem:       return "Paused by the watch"
        case .error:                    return "Session failed"
        @unknown default:               return "Session ended"
        }
    }
}
