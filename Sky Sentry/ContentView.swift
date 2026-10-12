//
//  ContentView.swift
//  Sky Sentry
//

import SwiftUI

struct ContentView: View {
    @State private var model = TrafficModel()
    @State private var subscriptions = SubscriptionManager()
    @State private var showingHelp = false
    @State private var showingSettings = false
    @AppStorage("hasAcceptedSafetyBriefing") private var hasAcceptedSafety = false
    @AppStorage("autoStartRecording") private var autoStartRecording = false

    var body: some View {
        Group {
            // The traffic display itself is never gated. A billing problem must
            // not be able to take a pilot's traffic picture away, and charging
            // for the thing most likely to prevent a collision is the wrong
            // trade in every sense. The subscription buys the customisation.
            if !hasAcceptedSafety {
                SafetyAcknowledgementView(accepted: $hasAcceptedSafety)
            } else {
                trafficDisplay
            }
        }
        .onAppear { subscriptions.start() }
        .onDisappear { subscriptions.stop() }
    }

    private var trafficDisplay: some View {
        let palette = model.isSignalLost ? Palette.unknown : Palette.of(model.overallThreat)

        return GeometryReader { geometry in
            // In a small iPadOS window there is only room for the glanceable
            // layer, which is the part that matters anyway: colour, rings and
            // arrows. Chrome is dropped rather than shrunk, so what remains
            // stays readable at arm's length.
            // Thresholds chosen so a small iPadOS window and a phone in
            // landscape go compact, but an iPhone SE or mini in portrait
            // (375pt wide) keeps the full layout.
            let compact = geometry.size.height < 500 || geometry.size.width < 330

            ZStack {
                palette.background
                    .ignoresSafeArea()

                VStack(spacing: 0) {
                    header(palette, compact: compact)
                    RadarView(solutions: model.solutions, config: model.config, palette: palette)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    if !compact { footer(palette) }
                }
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
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
        .sheet(isPresented: $showingSettings) {
            SettingsView(model: model, subscriptions: subscriptions)
        }
    }

    // MARK: - Window sizing

    /// iPadOS enforces its own minimum window size and there is no way to go
    /// below it. `UIWindowScene.sizeRestrictions.minimumSize` defaults to
    /// 0x0 — no app-imposed floor — so setting it can only ever make windows
    /// BIGGER. An earlier attempt set 180x180 here, which raised our own floor
    /// rather than lowering the system's; the scene accepted the value and
    /// reported it back, and nothing got smaller.
    ///
    /// Nothing to do, then, except make the app work at whatever size the
    /// system permits — which is what the compact layout is for. On a small
    /// iPad the system minimum is a larger share of the screen, so the window
    /// looks proportionally bigger there even though it is the same in points.

    // MARK: - Header

    @ViewBuilder
    private func header(_ palette: Palette, compact: Bool) -> some View {
        if compact {
            compactHeader(palette)
        } else {
            fullHeader(palette)
        }
    }

    /// One line: state on the left, the thing that matters on the right. The
    /// controls are deliberately absent — widen the window to reach them.
    private func compactHeader(_ palette: Palette) -> some View {
        HStack(spacing: 6) {
            if model.recorderStats.isRecording {
                Image(systemName: "record.circle")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.red)
            }

            Text(statusWord)
                .font(.annunciator(16))
                .tracking(Font.annunciatorTracking(16))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Spacer(minLength: 4)

            Text(compactDetail)
                .font(.annunciatorDetail(12))
                .foregroundStyle(palette.ink.opacity(0.9))
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        // iPadOS draws its window controls over the top-left of the window
        // content rather than insetting the safe area for them, so the header
        // has to leave room or the state word sits underneath them.
        .padding(.leading, UIDevice.current.userInterfaceIdiom == .pad ? 74 : 10)
        .padding(.trailing, 10)
        .padding(.top, 2)
    }

    /// Nearest or converging traffic in the least space that still says something.
    private var compactDetail: String {
        if model.receiverFault != nil || model.isStale { return "—" }
        let subject = model.solutions.first(where: \.isConverging) ?? model.solutions.first
        guard let subject else { return "CLEAR \(Int(model.config.displayRangeNM)) NM" }

        var text = "\(subject.rangeLabel) NM"
        if let feet = subject.relativeAltitudeFeet {
            text += String(format: " %@%d", feet >= 0 ? "+" : "-", abs(feet))
        }
        if subject.isConverging { text += " CBDR" }
        return text
    }

    @ViewBuilder
    private func fullHeader(_ palette: Palette) -> some View {
        VStack(spacing: 2) {
            HStack {
                Text(model.source.rawValue)
                    .font(.annunciatorDetail(11, weight: .heavy))
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
                    .font(.annunciatorDetail(11, weight: .semibold))
                    .foregroundStyle(palette.ink.opacity(0.85))

                Button { showingHelp = true } label: {
                    Image(systemName: "questionmark.circle")
                        .font(.system(size: 17, weight: .semibold))
                }
                .foregroundStyle(palette.ink.opacity(0.8))

                Button { showingSettings = true } label: {
                    Image(systemName: "slider.horizontal.3")
                        .font(.system(size: 22, weight: .semibold))
                        .frame(width: 34, height: 34)
                }
                .foregroundStyle(palette.ink)
            }

            Text(statusWord)
                .font(.annunciator(32))
                .tracking(Font.annunciatorTracking(32))
                .foregroundStyle(palette.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)

            Text(nearestDetail)
                .font(.annunciatorDetail(13))
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

        var text = subject.target.shortLabel
        if let category = subject.target.category.shortLabel {
            text += " (\(category))"
        }
        text += "  \(subject.rangeLabel) NM"
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
            Text(AppInfo.oneLineDisclaimer)
                .font(.annunciatorDetail(10, weight: .medium))
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
