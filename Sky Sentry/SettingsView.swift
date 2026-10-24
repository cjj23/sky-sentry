//
//  SettingsView.swift
//  Eyes Out
//
//  The split here is TCAS's, and it is deliberate.
//
//  Display range and altitude band are the pilot's: a TCAS traffic display lets
//  the crew pick both, so they can open the picture out in the cruise and close
//  it down in the circuit where clutter is the problem.
//
//  Alert thresholds are not. TCAS chooses them automatically from own altitude,
//  because the trade-off between protection and nuisance alerts is the thing its
//  designers tuned, and a dial invites a pilot to turn protection off by
//  accident. This screen therefore shows what the thresholds currently ARE, and
//  lets the pilot pick a profile — but not type numbers into them.
//

import SwiftUI

struct SettingsView: View {
    @Bindable var model: TrafficModel
    @Bindable var subscriptions: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingPaywall = false
    @State private var showingDiagnostics = false

    private var isLocked: Bool { !subscriptions.isEntitled }

    var body: some View {
        NavigationStack {
            List {
                sourceSection
                if isLocked { unlockSection }

                // Locked controls are shown rather than hidden: a greyed-out
                // setting explains what a subscription buys far better than an
                // absence does, and the thresholds in force stay readable
                // either way.
                Group {
                    rangeSection
                    forwardBiasSection
                    altitudeSection
                    profileSection
                }
                .disabled(isLocked)
                .opacity(isLocked ? 0.45 : 1)

                activeThresholdsSection
                diagnosticsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .sheet(isPresented: $showingPaywall) {
                PaywallView(subscriptions: subscriptions)
            }
            .sheet(isPresented: $showingDiagnostics) {
                DiagnosticsView(model: model)
            }
        }
    }

    // MARK: - Source

    /// Not premium: choosing which receiver to listen to is basic operation,
    /// not customisation. The test feed lives here rather than on the main
    /// screen — simulated aircraft should not sit as an equally weighted choice
    /// underneath a live traffic display.
    private var sourceSection: some View {
        Section {
            Picker("Traffic source", selection: Binding(
                get: { model.source },
                set: { model.source = $0 }
            )) {
                Text("SkyEcho").tag(TrafficModel.Source.live)
                Text("Test feed").tag(TrafficModel.Source.simulator)
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Traffic source")
        } footer: {
            Text(model.source == .simulator
                 ? "The test feed is INVENTED traffic for trying the app out on "
                 + "the ground. It is not real and tells you nothing about the "
                 + "airspace around you."
                 : "Live traffic from the receiver on the SkyEcho's Wi-Fi network.")
        }
    }

    private var unlockSection: some View {
        Section {
            Button {
                showingPaywall = true
            } label: {
                Label("Unlock customisation", systemImage: "lock.open")
                    .font(.headline)
            }
        } footer: {
            Text("The traffic display, converging-traffic detection and the "
                 + "safety information are free. A subscription adds the "
                 + "settings below, and flight recording.")
        }
    }

    private var diagnosticsSection: some View {
        Section {
            Button {
                if isLocked { showingPaywall = true } else { showingDiagnostics = true }
            } label: {
                HStack {
                    Label("Flight recording & diagnostics", systemImage: "waveform.path.ecg")
                    Spacer()
                    if isLocked {
                        Image(systemName: "lock.fill").foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            Text("Records every aircraft heard and what the app did with it, for "
                 + "working out afterwards what your receiver can and cannot see.")
        }
    }

    // MARK: - Display

    private var rangeSection: some View {
        Section {
            Picker("Range", selection: Binding(
                get: { model.config.displayRangeNM },
                set: { model.config.displayRangeNM = $0 }
            )) {
                ForEach(AlertConfig.selectableRangesNM, id: \.self) { range in
                    Text("\(Int(range)) nm").tag(range)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Text("Display range")
        } footer: {
            Text("The outer ring. Rings sit at \(ringText). A shorter range in "
                 + "the circuit cuts clutter; a longer one in the cruise gives "
                 + "more warning.")
        }
    }

    private var ringText: String {
        String(format: "%.0f and %.0f nm",
               model.config.innerRingNM, model.config.middleRingNM)
    }

    private var forwardBiasSection: some View {
        Section {
            Picker("Ownship position", selection: Binding(
                get: { model.config.forwardBias },
                set: { model.config.forwardBias = $0 }
            )) {
                ForEach(ForwardBias.allCases) { bias in
                    Text(bias.title).tag(bias)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Showing", value: model.config.forwardBias.detail)
        } header: {
            Text("Forward bias")
        } footer: {
            Text("Moves you down the screen so more of it shows what is ahead, "
                 + "which is where the threats are for a faster aircraft. The "
                 + "scale stays the same in every direction — the picture is "
                 + "never stretched — so the trade is seeing less to the sides "
                 + "and behind. Traffic pushed off the edge still appears as an "
                 + "arrowhead at the edge, on the correct bearing.")
        }
    }

    private var altitudeSection: some View {
        Section {
            Picker("Altitude band", selection: Binding(
                get: { model.config.altitudeBand },
                set: { model.config.altitudeBand = $0 }
            )) {
                ForEach(AltitudeBand.allCases) { band in
                    Text(band.title).tag(band)
                }
            }
            .pickerStyle(.segmented)

            LabeledContent("Showing", value: model.config.altitudeBand.detail)
        } header: {
            Text("Altitude band")
        } footer: {
            Text("Which slice of altitude to draw, as on a TCAS traffic display. "
                 + "Above and Below are for climb and descent, when the traffic "
                 + "that matters is mostly on one side of you. This hides "
                 + "aircraft from the display — it does not make them safe.")
        }
    }

    // MARK: - Alerting

    private var profileSection: some View {
        Section {
            Picker("Profile", selection: Binding(
                get: { model.config.profileKind },
                set: { model.config.profileKind = $0 }
            )) {
                ForEach(AlertProfile.Kind.allCases) { kind in
                    Text(kind.title).tag(kind)
                }
            }
            .pickerStyle(.segmented)

            Text(model.config.profileKind.detail)
                .font(.caption)
                .foregroundStyle(.secondary)

            if let caveat = model.config.profileKind.caveat {
                Label {
                    Text(caveat).font(.caption)
                } icon: {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                }
                .padding(.vertical, 2)
            }
        } header: {
            Text("Alert profile")
        } footer: {
            Text("Alerting is based on time to closest approach, not distance — "
                 + "so an aircraft can turn the screen amber while still outside "
                 + "a ring if it is closing fast, and stay green inside one if it "
                 + "is not closing at all.")
        }
    }

    /// Shows what is actually in force right now, so the pilot can see the
    /// thresholds change with altitude rather than having to trust that they do.
    private var activeThresholdsSection: some View {
        let altitude = model.ownship?.pressureAltitudeFeet
        let level = model.config.profile.level(forOwnAltitudeFeet: altitude.map(Double.init))

        return Section {
            LabeledContent("Own altitude",
                           value: altitude.map { "\($0) ft" } ?? "unknown")
            thresholdRow("Caution", level.caution)
            thresholdRow("Warning", level.warning)
        } header: {
            Text("Thresholds in force")
        } footer: {
            Text("Chosen automatically from your altitude, as TCAS does. Tighter "
                 + "low down where circuit traffic would otherwise alert "
                 + "constantly, wider up high where closing speeds are greater. "
                 + (altitude == nil
                    ? "With no altitude known, the tightest band applies."
                    : ""))
        }
    }

    private func thresholdRow(_ title: String, _ thresholds: AlertThresholds) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(.subheadline.bold())
            Text(String(format: "%.0f s to closest approach · %.2f nm · %.0f ft",
                        thresholds.tauSeconds, thresholds.dmodNM, thresholds.zthrFeet))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
    }
}
