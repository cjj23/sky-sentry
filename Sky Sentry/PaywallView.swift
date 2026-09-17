//
//  PaywallView.swift
//  Eyes Out
//

import SwiftUI

struct PaywallView: View {
    @Bindable var subscriptions: SubscriptionManager
    @State private var showingHelp = false

    var body: some View {
        VStack(spacing: 0) {
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

            Button {
                Task { await subscriptions.purchase() }
            } label: {
                VStack(spacing: 2) {
                    if subscriptions.isPurchasing {
                        ProgressView().tint(.white)
                    } else {
                        Text(subscriptions.trialDescription ?? "Subscribe")
                            .font(.headline)
                        if let price = subscriptions.priceDescription {
                            Text(price).font(.subheadline)
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .disabled(subscriptions.product == nil || subscriptions.isPurchasing)

            Button("Restore purchases") {
                Task { await subscriptions.restore() }
            }
            .font(.footnote)

            Text("Renews monthly until cancelled. Cancel any time in Settings › "
                 + "Apple Account › Subscriptions.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(20)
        .background(.bar)
    }
}
