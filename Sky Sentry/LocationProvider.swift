//
//  LocationProvider.swift
//  Eyes Out
//
//  Two jobs, both real:
//
//  1. Ownship fallback. The SkyEcho normally supplies our position, but it can
//     take a while to get a fix after power-up, and without an ownship position
//     there is no relative picture at all — traffic is received and discarded.
//     Phone GPS fills that gap.
//
//  2. Keeping the app alive. iOS suspends a backgrounded app and stops
//     delivering UDP, so the traffic picture would die the moment the pilot
//     switched to their moving map. Continuous location updates keep the
//     process running, which is the same mechanism every EFB relies on.
//
//  The second is a consequence of the first, not a pretext for it: the position
//  is genuinely used, and the app behaves correctly if permission is refused.
//

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class LocationProvider: NSObject {

    private(set) var authorization: CLAuthorizationStatus = .notDetermined
    private(set) var latest: CLLocation?
    private(set) var isUpdating = false

    private let manager = CLLocationManager()

    /// True once we have a fix recent enough to stand in for the receiver's.
    var hasUsableFix: Bool {
        guard let latest else { return false }
        return Date().timeIntervalSince(latest.timestamp) < 10
            && latest.horizontalAccuracy > 0
            && latest.horizontalAccuracy < 200
    }

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Aircraft move fast; we want every update rather than distance-filtered ones.
        manager.distanceFilter = kCLDistanceFilterNone
        manager.activityType = .otherNavigation
        authorization = manager.authorizationStatus
    }

    func start() {
        guard !isUpdating else { return }

        switch authorization {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
            return
        case .denied, .restricted:
            // Nothing to do: the app still works from the receiver's own position.
            return
        default:
            break
        }

        // Only legal once authorised, and only with the location background mode.
        manager.allowsBackgroundLocationUpdates = true
        // Leave the system's blue indicator alone — the pilot should be able to
        // see that the app is using location in the background.
        manager.pausesLocationUpdatesAutomatically = false
        manager.startUpdatingLocation()
        isUpdating = true
    }

    func stop() {
        guard isUpdating else { return }
        manager.stopUpdatingLocation()
        manager.allowsBackgroundLocationUpdates = false
        isUpdating = false
    }
}

// MARK: - CLLocationManagerDelegate

extension LocationProvider: CLLocationManagerDelegate {

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            self.authorization = status
            if status == .authorizedWhenInUse || status == .authorizedAlways {
                self.start()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in self.latest = location }
    }

    nonisolated func locationManager(_ manager: CLLocationManager,
                                     didFailWithError error: Error) {
        // Transient failures are normal; the receiver's own position still works.
    }
}
