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

        ZStack {
            background(for: summary).ignoresSafeArea()

            VStack(spacing: 6) {
                Text(headline(for: summary))
                    .font(.system(size: 20, weight: .black, design: .rounded))
                    .minimumScaleFactor(0.5)
                    .lineLimit(1)

                if summary.isAlerting {
                    Text(summary.side == .left ? "◀ LEFT"
                         : summary.side == .right ? "RIGHT ▶" : "DIRECTION UNKNOWN")
                        .font(.system(size: 15, weight: .heavy, design: .rounded))

                    Text(detail(for: summary))
                        .font(.system(size: 13, weight: .semibold, design: .rounded))
                        .opacity(0.9)
                } else {
                    Text(subtitle(for: summary))
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .multilineTextAlignment(.center)
                        .opacity(0.85)
                }

                Toggle("Haptics", isOn: $model.hapticsEnabled)
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .padding(.top, 2)
            }
            .foregroundStyle(.white)
            .padding(.horizontal, 8)
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
        var parts = ["\(summary.rangeLabel) NM"]
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
