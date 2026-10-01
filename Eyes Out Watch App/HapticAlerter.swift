//
//  HapticAlerter.swift
//  Eyes Out Watch App
//
//  The point of the watch app: tell the pilot which way to look without them
//  looking at anything.
//
//      one tap    traffic to the LEFT
//      two taps   traffic to the RIGHT
//
//  The gap between pulses shortens as the aircraft closes, so urgency is felt
//  rather than read. Only the single most important contact is played —
//  converging first, otherwise nearest — because overlapping patterns on the
//  wrist are unreadable and a pilot does not need a list.
//

import Foundation
import WatchKit

@MainActor
final class HapticAlerter {

    /// Gap between pulses at the edge of the display range, in seconds.
    private let slowestInterval: TimeInterval = 6.0
    /// Gap between pulses at or inside the warning ring.
    private let fastestInterval: TimeInterval = 1.1
    /// Converging traffic is played more insistently than range alone implies.
    private let convergingFactor: Double = 0.65
    /// Gap between the two pulses of a "right" double tap.
    private let doubleTapGap: TimeInterval = 0.22

    /// Matches the phone's rings, so the mapping is the same on both devices.
    private let displayRangeNM = 10.0
    private let warningRangeNM = 2.0

    private var timer: Timer?
    private var current = TrafficSummary.noPicture

    func start() {
        // The schedule is rebuilt whenever a summary arrives; nothing to do yet.
    }

    func stop() {
        timer?.invalidate()
        timer = nil
        current = .noPicture
    }

    func update(summary: TrafficSummary) {
        // Only reschedule when the cadence would actually change, otherwise a
        // 1 Hz stream of updates would reset the timer before it ever fires.
        let wasAlerting = current.isAlerting
        let previousInterval = interval(for: current)
        current = summary

        guard summary.isAlerting else {
            stop()
            return
        }

        let newInterval = interval(for: summary)
        let changedMeaningfully = !wasAlerting
            || abs(newInterval - previousInterval) > 0.15
            || summary.side != current.side

        if timer == nil || changedMeaningfully {
            schedule(interval: newInterval)
        }
    }

    // MARK: - Scheduling

    private func schedule(interval: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: interval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.fire() }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        // Play immediately so the first alert is not delayed by a whole interval.
        fire()
    }

    private func fire() {
        guard current.isAlerting else {
            stop()
            return
        }
        play(side: current.side, urgent: current.threatLevel >= 3)
    }

    private func play(side: TrafficSide, urgent: Bool) {
        let device = WKInterfaceDevice.current()
        // .notification is a heavier thump than .click, used once it is close.
        let haptic: WKHapticType = urgent ? .notification : .click

        switch side {
        case .left:
            device.play(haptic)
        case .right:
            device.play(haptic)
            Task { @MainActor in
                try? await Task.sleep(nanoseconds: UInt64(doubleTapGap * 1_000_000_000))
                device.play(haptic)
            }
        case .unknown:
            // Direction unknown: a distinct long-short pair, so it is never
            // mistaken for a confident left or right.
            device.play(.directionUp)
        }
    }

    // MARK: - Cadence

    /// Maps range to a pulse interval, geometrically so the rate climbs sharply
    /// as the aircraft gets close rather than creeping up linearly.
    private func interval(for summary: TrafficSummary) -> TimeInterval {
        guard let range = summary.rangeNM else { return slowestInterval }

        let span = displayRangeNM - warningRangeNM
        let fraction = max(0, min(1, (range - warningRangeNM) / span))
        var interval = fastestInterval * pow(slowestInterval / fastestInterval, fraction)

        if summary.isConverging { interval *= convergingFactor }
        return max(0.8, interval)
    }
}
