//
//  ContentView.swift
//  Sky Sentry
//

import SwiftUI

struct ContentView: View {
    @State private var model = TrafficModel()
    @State private var subscriptions = SubscriptionManager()
    @State private var showingHelp = false
    @State private var showingDiagnostics = false
    @AppStorage("hasAcceptedSafetyBriefing") private var hasAcceptedSafety = false
    @AppStorage("autoStartRecording") private var autoStartRecording = false

    var body: some View {
        Group {
            if !hasAcceptedSafety {
                SafetyAcknowledgementView(accepted: $hasAcceptedSafety)
            } else {
                switch subscriptions.access {
                case .checking:
                    ProgressView("Checking subscription…")
                case .notEntitled:
                    PaywallView(subscriptions: subscriptions)
                case .entitled:
                    trafficDisplay
                }
            }
        }
        .onAppear { subscriptions.start() }
        .onDisappear { subscriptions.stop() }
    }

    private var trafficDisplay: some View {
        let palette = model.isSignalLost ? Palette.unknown : Palette.of(model.overallThreat)

        return ZStack {
            palette.background
                .ignoresSafeArea()

            VStack(spacing: 0) {
                header(palette)
                RadarView(solutions: model.solutions, config: model.config, palette: palette)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                footer(palette)
            }
        }
        .animation(.easeInOut(duration: 0.2), value: model.overallThreat)
        .onAppear {
            model.start()
            // Starting the recorder by hand is easy to forget during a busy
            // pre-flight, so it can be armed once and left armed.
            if autoStartRecording && !model.recorderStats.isRecording {
                model.startRecording()
            }
            // A traffic display is no use if the phone dims itself on the glareshield.
            UIApplication.shared.isIdleTimerDisabled = true
        }
        .onDisappear {
            model.stop()
            UIApplication.shared.isIdleTimerDisabled = false
        }
        .sheet(isPresented: $showingHelp) { HelpView() }
        .sheet(isPresented: $showingDiagnostics) { DiagnosticsView(model: model) }
    }

    // MARK: - Header

    @ViewBuilder
    private func header(_ palette: Palette) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(model.source.rawValue)
                    .font(.system(size: 11, weight: .heavy, design: .rounded))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(
                        Capsule().fill(model.source == .simulator
                                       ? Color.black.opacity(0.35)
                                       : Color.black.opacity(0.2))
                    )
                    .foregroundStyle(palette.ink)

                // A red dot while recording, so it is obvious it is running.
                if model.recorderStats.isRecording {
                    Image(systemName: "record.circle")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.red)
                }

                Spacer()

                Text(statusDetail)
                    .font(.system(size: 11, weight: .semibold, design: .rounded))
                    .foregroundStyle(palette.ink.opacity(0.85))

                Button { showingDiagnostics = true } label: {
                    Image(systemName: "waveform.path.ecg")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(palette.ink.opacity(0.85))

                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 14, weight: .semibold))
                }
                .foregroundStyle(palette.ink.opacity(0.85))
            }

            Text(statusWord)
                .font(.system(size: 32, weight: .black, design: .rounded))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(nearestDetail)
                .font(.system(size: 13, weight: .bold, design: .rounded))
                .foregroundStyle(palette.ink.opacity(0.9))
        }
        .padding(.horizontal, 14)
        .padding(.top, 4)
    }

    private var statusWord: String {
        if model.receiverFault != nil { return "RECEIVER FAULT" }
        if model.isStale { return "NO DATA" }
        guard model.ownship != nil else { return "NO POSITION" }
        // Converging traffic is the thing worth naming, whatever the range.
        if model.solutions.contains(where: \.isConverging) { return "CONVERGING" }
        switch model.overallThreat {
        case .clear:    return "CLEAR"
        case .advisory: return "TRAFFIC"
        case .caution:  return "CAUTION"
        case .warning:  return "CLOSE TRAFFIC"
        }
    }

    private var statusDetail: String {
        if model.isStale { return "NO DATA" }
        var parts = ["\(model.solutions.count) IN RANGE"]
        if model.filteredCount > 0 { parts.append("\(model.filteredCount) FILTERED") }
        return parts.joined(separator: " · ")
    }

    private var nearestDetail: String {
        if let fault = model.receiverFault { return fault.uppercased() }
        if model.isStale {
            return model.source == .live
                ? "CHECK SKYECHO WIFI — NOT A CLEAR PICTURE"
                : "WAITING FOR DATA"
        }
        // Lead with converging traffic if there is any, otherwise the closest.
        let subject = model.solutions.first(where: \.isConverging) ?? model.solutions.first
        guard let subject else {
            return "NOTHING WITHIN \(Int(model.config.displayRangeNM)) NM"
        }

        var text = "\(subject.target.shortLabel)  \(subject.rangeLabel) NM"
        if let feet = subject.relativeAltitudeFeet {
            text += String(format: "  %@%d FT", feet >= 0 ? "+" : "-", abs(feet))
        }
        if subject.isConverging {
            text += "  · CONSTANT BEARING"
        }
        return text
    }

    // MARK: - Footer

    @ViewBuilder
    private func footer(_ palette: Palette) -> some View {
        VStack(spacing: 8) {
            Picker("Source", selection: Binding(
                get: { model.source },
                set: { model.source = $0 }
            )) {
                Text("Test feed").tag(TrafficModel.Source.simulator)
                Text("SkyEcho").tag(TrafficModel.Source.live)
            }
            .pickerStyle(.segmented)

            Text(AppInfo.oneLineDisclaimer)
                .font(.system(size: 10, weight: .medium, design: .rounded))
                .foregroundStyle(palette.ink.opacity(0.7))
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 6)
    }
}

#Preview {
    ContentView()
}
