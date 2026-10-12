//
//  SubscriptionManager.swift
//  Eyes Out
//
//  StoreKit 2 subscription handling: a monthly and an annual auto-renewing
//  product in the same subscription group, each with a one month free trial.
//
//  Annual matters more than it looks in this market. UK general aviation is
//  seasonal, so a monthly-only plan invites subscribing in April and cancelling
//  in October; the competition (SafeSky, SkyDemon, PilotAware) all sell yearly.
//
//  The traffic display does NOT depend on any of this — it is free, and nothing
//  here is consulted before drawing it. The subscription buys the customisation.
//  That is what makes it safe to deny access when entitlement cannot be proved:
//  the worst case is a pilot who cannot change the display range, not one who
//  loses their traffic picture over a billing problem.
//
//  Entitlement is still held for the lifetime of a launch once granted, so a
//  renewal failing mid-flight cannot pull settings out from under someone.
//
//  Note that being offline is NOT a reason to grant access: currentEntitlements
//  reads the local receipt and works perfectly well in the air. Only fetching
//  prices needs the network, and that matters solely for showing the paywall.
//

import Foundation
import StoreKit

@MainActor
@Observable
final class SubscriptionManager {

    /// Must match the product identifiers created in App Store Connect, both in
    /// the same subscription group so customers can move between them.
    enum Plan: String, CaseIterable {
        case monthly = "uk.co.chrisjones.eyesout.monthly"
        case yearly  = "uk.co.chrisjones.eyesout.yearly"
    }

    enum Access {
        case checking
        case entitled
        case notEntitled
    }

    private(set) var access: Access = .checking

    /// True once the customisation is unlocked. Note the traffic display never
    /// consults this: it is free, deliberately.
    var isEntitled: Bool { access == .entitled }
    private(set) var products: [Plan: Product] = [:]
    private(set) var lastError: String?
    private(set) var purchasingPlan: Plan?
    /// True when access was granted because entitlement could not be checked at
    /// all, rather than because a valid subscription was found.
    private(set) var isUnverified = false

    /// Set once access has been granted during this launch, and never cleared.
    private var grantedThisLaunch = false

    private var updatesTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
        // A repeated onAppear would otherwise replace this task without
        // cancelling it, leaving the old one iterating Transaction.updates for
        // the life of the process.
        guard updatesTask == nil else { return }

        // Listen for transactions that arrive outside a purchase we initiated,
        // such as a renewal or a purchase made on another device.
        updatesTask = Task { [weak self] in
            for await update in Transaction.updates {
                guard let self else { return }
                if case .verified(let transaction) = update {
                    await transaction.finish()
                    await self.refresh()
                }
            }
        }
        Task { await refresh() }

        // Watchdog. StoreKit can hang indefinitely when the App Store is
        // unreachable, and nothing should sit on "checking" for ever. Resolving
        // to not-entitled is safe now that only the customisation depends on it.
        Task { [weak self] in
            try? await Task.sleep(nanoseconds: 5_000_000_000)
            guard let self, self.access == .checking else { return }
            self.access = .notEntitled
        }
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: - Entitlement

    func refresh() async {
        if products.isEmpty {
            do {
                let loaded = try await Product.products(for: Plan.allCases.map(\.rawValue))
                products = Dictionary(uniqueKeysWithValues: loaded.compactMap { product in
                    Plan(rawValue: product.id).map { ($0, product) }
                })
            } catch {
                lastError = error.localizedDescription
            }
        }

        let identifiers = Set(Plan.allCases.map(\.rawValue))
        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               identifiers.contains(transaction.productID),
               transaction.revocationDate == nil {
                entitled = true
            }
        }

        if entitled { grantedThisLaunch = true }

        // Once granted, stay granted for this launch.
        access = (entitled || grantedThisLaunch) ? .entitled : .notEntitled
    }

    // MARK: - Purchasing

    func purchase(_ plan: Plan) async {
        guard let product = products[plan], purchasingPlan == nil else { return }
        purchasingPlan = plan
        lastError = nil
        defer { purchasingPlan = nil }

        do {
            switch try await product.purchase() {
            case .success(let verification):
                if case .verified(let transaction) = verification {
                    await transaction.finish()
                    grantedThisLaunch = true
                    access = .entitled
                } else {
                    lastError = "That purchase could not be verified."
                }
            case .userCancelled:
                break
            case .pending:
                lastError = "Your purchase is pending approval."
            @unknown default:
                break
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    func restore() async {
        do {
            try await AppStore.sync()
            await refresh()
            if access != .entitled {
                lastError = "No active subscription was found for this Apple Account."
            }
        } catch {
            lastError = error.localizedDescription
        }
    }

    // MARK: - Display helpers

    /// Localised price straight from StoreKit, so it is right in every storefront.
    func price(for plan: Plan) -> String? {
        products[plan]?.displayPrice
    }

    /// Describes the introductory offer, if this account is eligible for one.
    func trialDescription(for plan: Plan) -> String? {
        guard let offer = products[plan]?.subscription?.introductoryOffer,
              offer.paymentMode == .freeTrial else { return nil }

        let count = offer.period.value
        let unit: String
        switch offer.period.unit {
        case .day:   unit = count == 1 ? "day" : "days"
        case .week:  unit = count == 1 ? "week" : "weeks"
        case .month: unit = count == 1 ? "month" : "months"
        case .year:  unit = count == 1 ? "year" : "years"
        @unknown default: unit = "period"
        }
        return "\(count) \(unit) free"
    }

    /// How much the annual plan saves against twelve months of the monthly one,
    /// as a percentage, computed from live prices rather than hard-coded.
    var annualSavingPercent: Int? {
        guard let monthly = products[.monthly]?.price,
              let yearly = products[.yearly]?.price else { return nil }
        let twelveMonths = monthly * 12
        guard twelveMonths > 0, yearly < twelveMonths else { return nil }
        let saving = (twelveMonths - yearly) / twelveMonths * 100
        return Int(NSDecimalNumber(decimal: saving).doubleValue.rounded())
    }
}
