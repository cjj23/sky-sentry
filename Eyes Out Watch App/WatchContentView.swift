//
//  WatchContentView.swift
//  Eyes Out Watch App
//
//  Secondary to the haptics: this is what you see if you happen to glance down,
//  not something you are meant to watch. Same colour language as the phone, so
//  a glance means the same thing on either device.
//

import SwiftUI

struct WatchContentView: View {
    @Bindable var model: WatchTrafficModel

    var body: some View {
        let summary = model.displaySummary

        ScrollView {
            VStack(spacing: 8) {
                statusBlock(summary)
                armingBlock
                Toggle("Haptics", isOn: $model.hapticsEnabled)
                    .font(.annunciatorDetail(12, weight: .semibold))
            }
            .padding(.horizontal, 6)
        }
        .background(background(for: summary).ignoresSafeArea())
        .foregroundStyle(.white)
    }

    // MARK: - Traffic

    @ViewBuilder
    private func statusBlock(_ summary: TrafficSummary) -> some View {
        VStack(spacing: 4) {
            Text(headline(for: summary))
                .font(.annunciator(20))
                .tracking(Font.annunciatorTracking(20))
                .minimumScaleFactor(0.5)
                .lineLimit(1)

            if summary.isAlerting {
                Text(summary.side == .left ? "◀ LEFT"
                     : summary.side == .right ? "RIGHT ▶" : "DIRECTION UNKNOWN")
                    .font(.annunciatorDetail(15, weight: .heavy))

                Text(detail(for: summary))
                    .font(.annunciatorDetail(13, weight: .semibold))
                    .opacity(0.9)
            } else {
                Text(subtitle(for: summary))
                    .font(.annunciatorDetail(12, weight: .semibold))
                    .multilineTextAlignment(.center)
                    .opacity(0.85)
            }
        }
        .padding(.top, 2)
    }

    // MARK: - Arming

    @ViewBuilder
    private var armingBlock: some View {
        VStack(spacing: 4) {
            Button {
                model.toggleMonitoring()
            } label: {
                Label(model.monitoring.isArmed ? "Stop monitoring" : "Start monitoring",
                      systemImage: model.monitoring.isArmed ? "stop.circle.fill" : "bolt.horizontal.circle")
                    .font(.annunciatorDetail(14))
                    .frame(maxWidth: .infinity)
            }
            .tint(model.monitoring.isArmed ? .red : .accentColor)

            // The limitation stated plainly rather than hidden: without this the
            // watch stops alerting the moment the screen goes off.
            Text(armingFootnote)
                .font(.annunciatorDetail(10, weight: .medium))
                .multilineTextAlignment(.center)
                .opacity(0.8)
        }
    }

    private var armingFootnote: String {
        switch model.monitoring.state {
        case .idle:
            if let reason = model.monitoring.lastEndReason { return reason }
            return "Arm before flight — haptics stop when the screen sleeps otherwise."
        case .running:
            return "Monitoring — haptics continue with your wrist down."
        case .expiring:
            return "Session ending — tap to re-arm."
        }
    }

    // MARK: - Presentation

    private func background(for summary: TrafficSummary) -> Color {
        guard summary.hasPicture else {
            // Never green when we have nothing: no picture is not clear sky.
            return Color(red: 0.28, green: 0.30, blue: 0.33)
        }
        switch summary.threatLevel {
        case 3:  return Color(red: 0.82, green: 0.09, blue: 0.09)
        case 2:  return Color(red: 0.90, green: 0.52, blue: 0.02)
        default: return Color(red: 0.06, green: 0.42, blue: 0.18)
        }
    }

    private func headline(for summary: TrafficSummary) -> String {
        guard summary.hasPicture else { return "NO DATA" }
        if summary.isConverging { return "CONVERGING" }
        switch summary.threatLevel {
        case 3:  return "CLOSE"
        case 2:  return "CAUTION"
        case 1:  return "TRAFFIC"
        default: return "CLEAR"
        }
    }

    private func detail(for summary: TrafficSummary) -> String {
        var parts: [String] = []
        if let category = summary.categoryLabel { parts.append(category) }
        parts.append("\(summary.rangeLabel) NM")
        if let altitude = summary.altitudeLabel { parts.append(altitude) }
        if let seconds = summary.secondsToCPA, summary.isConverging, seconds > 0 {
            parts.append("\(Int(seconds.rounded()))s")
        }
        return parts.joined(separator: "  ")
    }

    private func subtitle(for summary: TrafficSummary) -> String {
        guard summary.hasPicture else {
            return model.isReachable ? "Waiting for the phone" : "Phone not reachable"
        }
        return "Nothing within range"
    }
}
