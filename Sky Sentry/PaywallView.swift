//
//  PaywallView.swift
//  Eyes Out
//

import SwiftUI

struct PaywallView: View {
    @Bindable var subscriptions: SubscriptionManager
    @Environment(\.dismiss) private var dismiss
    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Spacer()
                Button("Not now") { dismiss() }
                    .font(.subheadline)
                    .padding(.horizontal, 20)
                    .padding(.top, 14)
            }

            ScrollView {
                VStack(spacing: 22) {
                    Image(systemName: "dot.radiowaves.up.forward")
                        .font(.system(size: 52))
                        .foregroundStyle(.tint)
                        .padding(.top, 30)

                    VStack(spacing: 6) {
                        Text(AppInfo.displayName).font(.largeTitle.bold())
                        Text("Traffic at a glance")
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 14) {
                        feature("eye", "See nearby aircraft without reading a map",
                                "Direction, distance and height on one glanceable screen.")
                        feature("arrow.triangle.merge", "Converging traffic called out",
                                "Aircraft on a constant bearing are the ones that collide. "
                                + "They are flagged with a countdown to closest approach.")
                        feature("antenna.radiowaves.left.and.right", "Works with your SkyEcho 2",
                                "Runs alongside SkyDemon or ForeFlight on the same receiver.")
                    }
                    .padding(.horizontal, 4)

                    warningCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }

            purchaseBar
        }
        .sheet(isPresented: $showingHelp) { HelpView() }
        // Close as soon as it is bought, so the screen they were heading for is
        // one tap away rather than behind a paywall they have already paid.
        .onChange(of: subscriptions.isEntitled) { _, entitled in
            if entitled { dismiss() }
        }
    }

    private func feature(_ symbol: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(.tint)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(.subheadline.bold())
                Text(detail).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    @ViewBuilder
    private func planButton(_ plan: SubscriptionManager.Plan, prominent: Bool) -> some View {
        let isBusy = subscriptions.purchasingPlan == plan
        let price = subscriptions.price(for: plan)
        let trial = subscriptions.trialDescription(for: plan)

        let action: () -> Void = { Task { await subscriptions.purchase(plan) } }
        let label = VStack(spacing: 2) {
            if isBusy {
                ProgressView().tint(prominent ? .white : .accentColor)
            } else {
                HStack(spacing: 6) {
                    Text(plan == .yearly ? "Yearly" : "Monthly").font(.headline)
                    if let price {
                        Text("· \(price)").font(.headline)
                    }
                }
                if let subtitle = planSubtitle(plan, trial: trial) {
                    Text(subtitle).font(.caption)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)

        // The two button styles are different types, so the branch has to wrap
        // the whole button rather than just the style modifier.
        if prominent {
            Button(action: action) { label }
                .buttonStyle(.borderedProminent)
                .disabled(price == nil || subscriptions.purchasingPlan != nil)
        } else {
            Button(action: action) { label }
                .buttonStyle(.bordered)
                .disabled(price == nil || subscriptions.purchasingPlan != nil)
        }
    }

    private func planSubtitle(_ plan: SubscriptionManager.Plan, trial: String?) -> String? {
        var parts: [String] = []
        if let trial { parts.append("\(trial) first") }
        if plan == .yearly, let saving = subscriptions.annualSavingPercent {
            parts.append("save \(saving)%")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private var warningCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Before you subscribe", systemImage: "exclamationmark.triangle.fill")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

            Text("This app is an aid to lookout, not a collision avoidance system. "
                 + "It shows only aircraft your receiver reports. Many aircraft — "
                 + "including most of the UK fleet without ADS-B Out — cannot be "
                 + "seen by it at all.")
                .font(.caption)

            Button("Read the full safety information") { showingHelp = true }
                .font(.caption.bold())
        }
        .padding(14)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }

    private var purchaseBar: some View {
        VStack(spacing: 10) {
            if let error = subscriptions.lastError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }

            // Annual first and prominent: it is the better deal for the customer
            // and it survives the winter, when UK flying largely stops.
            planButton(.yearly, prominent: true)
            planButton(.monthly, prominent: false)

            Button("Restore purchases") {
                Task { await subscriptions.restore() }
            }
            .font(.footnote)

            Text("Each plan renews automatically at the price shown until "
                 + "cancelled. Cancel any time in Settings › Apple Account › "
                 + "Subscriptions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            // Required in the binary by guideline 3.1.2, not just in the App
            // Store listing.
            HStack(spacing: 18) {
                Link("Terms of Use", destination: AppInfo.termsOfUseURL)
                Link("Privacy Policy", destination: AppInfo.privacyPolicyURL)
            }
            .font(.caption2)
        }
        .padding(20)
        .background(.bar)
    }
}
