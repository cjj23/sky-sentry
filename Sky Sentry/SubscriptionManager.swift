//
//  SubscriptionManager.swift
//  Eyes Out
//
//  StoreKit 2 subscription handling: one monthly auto-renewing product with a
//  one month introductory free trial.
//
//  SAFETY RULE: access is evaluated at launch and then held for the lifetime of
//  the launch. A subscription that lapses, or a StoreKit call that fails while
//  airborne with no signal, must never cause the traffic display to disappear
//  in flight. Billing problems get resolved on the ground, not at 2,000 feet.
//

import Foundation
import StoreKit

@MainActor
@Observable
final class SubscriptionManager {

    /// Must match the product identifier created in App Store Connect.
    static let monthlyProductID = "uk.co.chrisjones.eyesout.monthly"

    enum Access {
        case checking
        case entitled
        case notEntitled
    }

    private(set) var access: Access = .checking
    private(set) var product: Product?
    private(set) var lastError: String?
    private(set) var isPurchasing = false
    /// True when access was granted because entitlement could not be checked at
    /// all, rather than because a valid subscription was found.
    private(set) var isUnverified = false

    /// Set once access has been granted during this launch, and never cleared.
    private var grantedThisLaunch = false

    private var updatesTask: Task<Void, Never>?

    // MARK: - Lifecycle

    func start() {
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
    }

    func stop() {
        updatesTask?.cancel()
        updatesTask = nil
    }

    // MARK: - Entitlement

    func refresh() async {
        if product == nil {
            do {
                product = try await Product.products(for: [Self.monthlyProductID]).first
            } catch {
                lastError = error.localizedDescription
            }
        }

        var entitled = false
        for await result in Transaction.currentEntitlements {
            if case .verified(let transaction) = result,
               transaction.productID == Self.monthlyProductID,
               transaction.revocationDate == nil {
                entitled = true
            }
        }

        if entitled { grantedThisLaunch = true }

        if entitled || grantedThisLaunch {
            // Once granted, stay granted for this launch — see the safety rule above.
            access = .entitled
        } else if product == nil {
            // We could not even find out what is for sale: either the product is
            // not configured in App Store Connect yet, or the App Store is
            // unreachable — which is the normal state airborne. Fail open. A
            // billing system that cannot reach a server must never be the reason
            // a pilot loses their traffic display.
            isUnverified = true
            access = .entitled
        } else {
            access = .notEntitled
        }
    }

    // MARK: - Purchasing

    func purchase() async {
        guard let product, !isPurchasing else { return }
        isPurchasing = true
        lastError = nil
        defer { isPurchasing = false }

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

    /// "£4.99 / month", taken from StoreKit so it is correct in every storefront.
    var priceDescription: String? {
        guard let product else { return nil }
        return "\(product.displayPrice) / month"
    }

    /// Describes the introductory offer if the account is eligible for one.
    var trialDescription: String? {
        guard let offer = product?.subscription?.introductoryOffer,
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
        return "\(count) \(unit) free, then"
    }
}
