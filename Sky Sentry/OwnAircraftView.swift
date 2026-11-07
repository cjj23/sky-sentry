//
//  OwnAircraftView.swift
//  Eyes Out
//
//  Managing the list of airframes whose ADS-B Out is our own.
//
//  Two ways in, because they suit different moments. Picking from the traffic
//  being heard is the one that works in the cockpit: the echo of your own
//  aircraft is the contact sitting at 0.0 nm, and one tap identifies it with no
//  hex to read or mistype. Typing the address is for setting it up on the
//  ground, before the aircraft is even powered.
//

import SwiftUI

struct OwnAircraftView: View {
    @Bindable var model: TrafficModel

    @State private var manualAddress = ""
    @State private var manualLabel = ""
    @State private var manualError: String?

    var body: some View {
        List {
            savedSection
            heardNowSection
            manualSection
            explanationSection
        }
        .listStyle(.insetGrouped)
        .navigationTitle("My aircraft")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Saved

    private var savedSection: some View {
        Section {
            if model.config.ownAircraft.isEmpty {
                Text("No aircraft listed.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(model.config.ownAircraft) { aircraft in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(aircraft.label.isEmpty ? aircraft.addressHex : aircraft.label)
                                .font(.body)
                            Text(aircraft.addressHex)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if model.isSuppressingOwnEcho, isCurrentlyHeard(aircraft) {
                            Text("HEARD NOW")
                                .font(.caption2.bold())
                                .foregroundStyle(.green)
                        }
                    }
                }
                .onDelete { offsets in
                    model.config.ownAircraft.remove(atOffsets: offsets)
                }
            }
        } header: {
            Text("Recognised as mine")
        } footer: {
            Text("Swipe to remove. An aircraft listed here is ignored only while "
                 + "it is within half a mile and 500 ft of you — the same "
                 + "airframe flown by somebody else, on another day, still "
                 + "shows as the traffic it is.")
        }
    }

    /// The listed airframe is in the current picture, which is the useful
    /// confirmation after adding one: it says the right contact was picked.
    private func isCurrentlyHeard(_ aircraft: OwnAircraft) -> Bool {
        model.lastDispositions.contains {
            $0.target.icaoAddress == aircraft.address && $0.outcome == .ownAircraft
        }
    }

    // MARK: - Pick from traffic

    private var heardNowSection: some View {
        Section {
            if candidates.isEmpty {
                Text("No traffic being heard.")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(candidates, id: \.target.icaoAddress) { disposition in
                    Button {
                        add(address: disposition.target.icaoAddress,
                            label: disposition.target.shortLabel)
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(disposition.target.shortLabel)
                                    .font(.body.monospaced())
                                Text(String(format: "%06X", disposition.target.icaoAddress))
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if let range = disposition.rangeNM {
                                Text(String(format: "%.1f nm", range))
                                    .font(.callout.monospacedDigit())
                                    .foregroundStyle(range <= model.config.ownEchoRangeNM
                                                     ? .primary : .secondary)
                            }
                        }
                    }
                }
            }
        } header: {
            Text("Add from traffic now")
        } footer: {
            Text("Your own aircraft is the one showing almost no distance, and "
                 + "it stays there through every turn. Already-listed aircraft "
                 + "are not shown here.")
        }
    }

    /// Nearest first, because the echo of ourselves is always the nearest thing
    /// there is. Anything already listed is left out so the list cannot be used
    /// to add the same airframe twice.
    private var candidates: [TargetDisposition] {
        model.lastDispositions
            .filter { !model.config.isOwnAircraft(address: $0.target.icaoAddress) }
            .sorted { ($0.rangeNM ?? .greatestFiniteMagnitude) < ($1.rangeNM ?? .greatestFiniteMagnitude) }
    }

    // MARK: - Manual entry

    private var manualSection: some View {
        Section {
            TextField("ICAO address, e.g. 40738A", text: $manualAddress)
                .font(.body.monospaced())
                .textInputAutocapitalization(.characters)
                .autocorrectionDisabled()
            TextField("Name, e.g. G-ETPC", text: $manualLabel)
                .autocorrectionDisabled()

            Button("Add aircraft") {
                guard let address = OwnAircraft.parse(address: manualAddress) else {
                    manualError = "That is not a six-digit hex address."
                    return
                }
                guard !model.config.isOwnAircraft(address: address) else {
                    manualError = "That aircraft is already listed."
                    return
                }
                add(address: address, label: manualLabel)
                manualAddress = ""
                manualLabel = ""
                manualError = nil
            }
            .disabled(manualAddress.isEmpty)

            if let manualError {
                Text(manualError)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("Add by address")
        } footer: {
            Text("The 24-bit ICAO address of the airframe, as six hex digits. "
                 + "It is on the transponder's configuration page, and in the "
                 + "CAA register entry for the aircraft. It is not the squawk.")
        }
    }

    private var explanationSection: some View {
        Section {
            Text("An aircraft with ADS-B Out transmits its position continuously, "
                 + "and a receiver in that same cockpit hears it exactly as it "
                 + "hears everybody else. Without being told otherwise, this app "
                 + "sees an aircraft a few yards away holding a constant bearing "
                 + "— which is the signature of a collision — and says so, for "
                 + "the whole flight.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func add(address: UInt32, label: String) {
        let trimmed = label.trimmingCharacters(in: .whitespaces)
        model.config.ownAircraft.append(
            OwnAircraft(address: address,
                        label: trimmed.isEmpty ? String(format: "%06X", address) : trimmed))
    }
}
