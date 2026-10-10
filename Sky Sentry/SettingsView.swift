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
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                rangeSection
                altitudeSection
                profileSection
                activeThresholdsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Display & Alerts")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
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
