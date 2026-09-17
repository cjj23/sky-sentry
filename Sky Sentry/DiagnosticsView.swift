//
//  DiagnosticsView.swift
//  Eyes Out
//
//  Recording controls and saved sessions. The live breakdown matters as much as
//  the recording itself: it shows, in flight, whether targets are being heard
//  and discarded rather than never heard at all.
//

import SwiftUI
import UIKit

struct DiagnosticsView: View {
    @Bindable var model: TrafficModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage("autoStartRecording") private var autoStartRecording = false
    @State private var sessions: [FlightRecorder.Session] = []
    @State private var shareItem: ShareItem?
    @State private var exportFailed = false

    private struct ShareItem: Identifiable {
        let url: URL
        var id: URL { url }
    }

    var body: some View {
        NavigationStack {
            List {
                recordingSection
                if model.recorderStats.isRecording { liveSection }
                heardNowSection
                sessionsSection
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Diagnostics")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { sessions = FlightRecorder.existingSessions() }
            .sheet(item: $shareItem) { item in
                ActivityView(activityItems: [item.url])
            }
            .alert("Could not prepare the export", isPresented: $exportFailed) {
                Button("OK", role: .cancel) { }
            } message: {
                Text("You can still retrieve the files with the Files app, under "
                     + "On My iPhone › \(AppInfo.displayName) › Recordings.")
            }
        }
    }

    // MARK: - Recording

    private var recordingSection: some View {
        Section {
            Button {
                if model.recorderStats.isRecording {
                    model.stopRecording()
                    sessions = FlightRecorder.existingSessions()
                } else {
                    model.startRecording()
                }
            } label: {
                HStack {
                    Image(systemName: model.recorderStats.isRecording
                          ? "stop.circle.fill" : "record.circle")
                        .font(.title2)
                    Text(model.recorderStats.isRecording ? "Stop recording" : "Start recording")
                        .font(.headline)
                    Spacer()
                }
                .foregroundStyle(model.recorderStats.isRecording ? .red : .accentColor)
            }

            Toggle("Record automatically on launch", isOn: $autoStartRecording)
        } header: {
            Text("Flight recording")
        } footer: {
            Text("Records every datagram received plus a once-per-second log of "
                 + "each target and what the app did with it. Keep the app in the "
                 + "foreground: iOS suspends background apps and reception stops.")
        }
    }

    private var liveSection: some View {
        Section("This session") {
            LabeledContent("Running", value: durationText(model.recorderStats.duration))
            LabeledContent("Datagrams", value: "\(model.recorderStats.datagrams)")
            LabeledContent("Captured", value: byteText(model.recorderStats.rawBytes))
            LabeledContent("Log samples", value: "\(model.recorderStats.samples)")
            LabeledContent("Distinct aircraft", value: "\(model.recorderStats.uniqueTargets)")

            ForEach(model.recorderStats.outcomeCounts.sorted(by: { $0.key < $1.key }), id: \.key) { entry in
                LabeledContent(entry.key, value: "\(entry.value)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// The live answer to "is it being filtered or never received?".
    private var heardNowSection: some View {
        Section {
            if model.lastDispositions.isEmpty {
                Text("No targets being heard.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.lastDispositions.sorted(by: { ($0.rangeNM ?? 999) < ($1.rangeNM ?? 999) }),
                        id: \.target.icaoAddress) { disposition in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(disposition.target.shortLabel)
                                .font(.callout.monospaced())
                            Text(disposition.outcome.label)
                                .font(.caption2)
                                .foregroundStyle(disposition.outcome == .displayed ? .green : .orange)
                        }
                        Spacer()
                        if let range = disposition.rangeNM {
                            Text(String(format: "%.1f nm", range))
                                .font(.callout.monospacedDigit())
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
        } header: {
            Text("Heard right now")
        } footer: {
            Text("Every aircraft the receiver is reporting, including those the "
                 + "app is not drawing, with the reason. If traffic is visible "
                 + "elsewhere but listed here as filtered, the thresholds are "
                 + "hiding it rather than the receiver missing it.")
        }
    }

    // MARK: - Saved sessions

    private var sessionsSection: some View {
        Section("Saved recordings") {
            if sessions.isEmpty {
                Text("No recordings yet.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(sessions) { session in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.name).font(.callout.monospaced())
                            Text(byteText(session.sizeBytes))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button {
                            if let archive = FlightRecorder.exportArchive(for: session) {
                                shareItem = ShareItem(url: archive)
                            } else {
                                exportFailed = true
                            }
                        } label: {
                            Image(systemName: "square.and.arrow.up")
                        }
                        .buttonStyle(.borderless)
                    }
                }
                .onDelete { indexSet in
                    for index in indexSet { FlightRecorder.delete(sessions[index]) }
                    sessions = FlightRecorder.existingSessions()
                }
            }
        }
    }

    // MARK: - Formatting

    private func durationText(_ seconds: TimeInterval) -> String {
        let total = Int(seconds)
        return String(format: "%02d:%02d:%02d", total / 3600, (total % 3600) / 60, total % 60)
    }

    private func byteText(_ bytes: Int) -> String {
        ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file)
    }
}

/// UIActivityViewController wrapper, since SwiftUI's ShareLink cannot share a
/// file that is created on demand at the moment of tapping.
struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) { }
}
