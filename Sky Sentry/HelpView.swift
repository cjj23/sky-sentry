//
//  HelpView.swift
//  Eyes Out
//
//  Help and safety information. The warning is shown first and is not
//  collapsible: the limitations are the most important thing in the app.
//

import SwiftUI
import UIKit

struct HelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                warningSection
                cannotSeeSection
                readingDisplaySection
                alongsideSection
                iPadWindowingSection
                setupSection
                aboutSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Help & Safety")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var warningSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("This is an aid to lookout", systemImage: "exclamationmark.triangle.fill")
                    .font(.headline)
                    .foregroundStyle(.orange)

                Text(AppInfo.primaryWarning)
                    .font(.callout)
            }
            .padding(.vertical, 4)
        }
    }

    private var cannotSeeSection: some View {
        Section {
            ForEach(AppInfo.whatItCannotSee, id: \.self) { item in
                Label {
                    Text(item).font(.callout)
                } icon: {
                    Image(systemName: "eye.slash")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("What this app cannot see")
        } footer: {
            Text("This list is not exhaustive. Assume at all times that there is "
                 + "traffic near you that this app has not detected.")
        }
    }

    private var readingDisplaySection: some View {
        Section {
            ForEach(AppInfo.howToUse, id: \.self) { item in
                Text(item).font(.callout)
            }
        } header: {
            Text("Reading the display")
        }
    }

    private var alongsideSection: some View {
        Section {
            Text(AppInfo.relationshipToOtherApps).font(.callout)
        } header: {
            Text("Using it alongside your navigation app")
        }
    }

    /// iPad only: how to get a window at all. Hidden on iPhone, where none of
    /// it applies.
    @ViewBuilder
    private var iPadWindowingSection: some View {
        if UIDevice.current.userInterfaceIdiom == .pad {
            Section {
                Text(AppInfo.iPadWindowingNote).font(.callout)

                VStack(alignment: .leading, spacing: 8) {
                    ForEach(Array(AppInfo.iPadWindowingSteps.enumerated()), id: \.offset) { index, step in
                        stepRow(index + 1, step)
                    }
                }
                .padding(.vertical, 2)
            } header: {
                Text("Showing it beside your navigation app")
            } footer: {
                Text(AppInfo.iPadWindowingFooter)
            }
        }
    }

    private var setupSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 8) {
                stepRow(1, "Power on your SkyEcho 2 and let it get a GPS fix.")
                stepRow(2, "On your device, join the SkyEcho's Wi-Fi network in Settings.")
                stepRow(3, "Open \(AppInfo.displayName) and select SkyEcho as the source.")
                stepRow(4, "Check the header shows traffic counts rather than NO DATA.")
            }
            .padding(.vertical, 2)
        } header: {
            Text("Connecting a SkyEcho 2")
        } footer: {
            Text("A grey screen means the app is receiving nothing and is not "
                 + "telling you anything about the airspace. It is not the same "
                 + "as a green screen.")
        }
    }

    private var aboutSection: some View {
        Section {
            LabeledContent("Version", value: AppInfo.versionString)
        } footer: {
            Text(AppInfo.oneLineDisclaimer)
        }
    }

    private func stepRow(_ number: Int, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Text("\(number)")
                .font(.caption.bold())
                .foregroundStyle(.white)
                .frame(width: 20, height: 20)
                .background(Circle().fill(.tint))
            Text(text).font(.callout)
        }
    }
}

// MARK: - First-run acknowledgement

/// Shown once, before the display is usable. The user has to scroll and accept,
/// so the limitations cannot be dismissed without at least being presented.
struct SafetyAcknowledgementView: View {
    @Binding var accepted: Bool

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 44))
                        .foregroundStyle(.orange)
                        .frame(maxWidth: .infinity)

                    Text("Before you use \(AppInfo.displayName)")
                        .font(.title2.bold())
                        .frame(maxWidth: .infinity, alignment: .center)

                    Text(AppInfo.primaryWarning)
                        .font(.callout)

                    Divider()

                    Text("It cannot see:").font(.headline)
                    ForEach(AppInfo.whatItCannotSee, id: \.self) { item in
                        Label {
                            Text(item).font(.callout)
                        } icon: {
                            Image(systemName: "eye.slash").foregroundStyle(.secondary)
                        }
                    }

                    Divider()

                    Text(AppInfo.relationshipToOtherApps).font(.callout)
                }
                .padding(20)
            }

            VStack(spacing: 10) {
                Button {
                    accepted = true
                } label: {
                    Text("I understand — this supplements my lookout")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)

                Text("You can read this again at any time from the Help button.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(20)
            .background(.bar)
        }
    }
}

#Preview {
    HelpView()
}
