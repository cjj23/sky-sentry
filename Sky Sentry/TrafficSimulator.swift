//
//  TrafficSimulator.swift
//  Sky Sentry
//
//  Generates a scripted traffic scenario as real GDL90 packets so the display can
//  be developed and demonstrated without a SkyEcho powered up. Because it emits
//  genuine encoded frames, everything goes through the same decoder as live data.
//
//  There is nothing in the GDL90 protocol that marks a target as simulated, so
//  the app must never leave this running silently — the UI shows a TEST FEED
//  banner whenever it is active.
//

import Foundation

final class TrafficSimulator {

    /// Receives fully framed GDL90 datagrams, as if they had arrived over WiFi.
    ///
    /// Everything the test feed produces has a position, and therefore a
    /// bearing. Bearingless contacts — Mode S, or FLARM without a bearing —
    /// cannot be expressed in GDL90 anyway, and are delivered by real sources
    /// through `TrafficModel.ingestRangeOnly` instead.
    var onPacket: ((Data) -> Void)?

    private var timer: Timer?
    private var elapsed: TimeInterval = 0

    // Ownship starts near Oxford, tracking north-east at 120 kt, 3000 ft.
    private var ownLat = 51.8369
    private var ownLon = -1.3200
    private let ownTrack: Double = 45
    private let ownSpeed: Double = 120
    private let ownAltitude = 3000

    /// One scripted aircraft, described in terms relative to where we started.
    private struct Script {
        let address: UInt32
        let callsign: String
        /// Range and bearing from ownship at t = 0.
        let initialRangeNM: Double
        let initialBearing: Double
        let track: Double
        let speedKnots: Double
        let altitude: Int
        let verticalSpeed: Double
        /// GDL90 emitter category, so the display can show what kind of thing it is.
        var emitter: UInt8 = 1

        var latitude: Double = 0
        var longitude: Double = 0
    }

    private var scripts: [Script] = []

    func start() {
        stop()
        elapsed = 0
        buildScenario()

        // 1 Hz, matching the rate a real SkyEcho reports at.
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.tick(interval: 1.0)
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        tick(interval: 0)
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    private func buildScenario() {
        var defs = [
            // Crossing left to right, co-altitude, stays in the caution band.
            Script(address: 0x40C3D4, callsign: "GXYZW", initialRangeNM: 4.2,
                   initialBearing: 300, track: 110, speedKnots: 95,
                   altitude: 2900, verticalSpeed: 0, emitter: 9),      // glider

            // Slow helicopter off to the left, descending.
            Script(address: 0x40E5F6, callsign: "GHELI", initialRangeNM: 3.0,
                   initialBearing: 285, track: 20, speedKnots: 70,
                   altitude: 2500, verticalSpeed: -700, emitter: 7),   // rotorcraft

            // Overtaking us from behind, slightly above.
            Script(address: 0x401122, callsign: "GTAIL", initialRangeNM: 7.5,
                   initialBearing: 225, track: 45, speedKnots: 165,
                   altitude: 3400, verticalSpeed: 800),

            // Well ahead and beyond the 10 nm ring — only visible when a
            // forward bias opens up the space in front.
            Script(address: 0x409911, callsign: "GFAR1", initialRangeNM: 15.0,
                   initialBearing: 50, track: 230, speedKnots: 130,
                   altitude: 3200, verticalSpeed: 0),

            // Airliner in the flight levels — well within 10 nm laterally, but it
            // should be filtered out by the vertical limit rather than cluttering.
            Script(address: 0x4004F2, callsign: "BAW23G", initialRangeNM: 6.0,
                   initialBearing: 150, track: 270, speedKnots: 420,
                   altitude: 24000, verticalSpeed: 1500, emitter: 5),  // heavy
        ]

        for i in defs.indices {
            let start = Geo.destination(lat: ownLat, lon: ownLon,
                                        bearingDegrees: defs[i].initialBearing,
                                        distanceNM: defs[i].initialRangeNM)
            defs[i].latitude = start.lat
            defs[i].longitude = start.lon
        }

        // A genuine collision course, so the CBDR detection has something real to
        // find: both aircraft are aimed at the same point at the same moment, which
        // holds the line of sight on a constant bearing all the way in.
        defs.append(collisionCourse(address: 0x40A1B2, callsign: "GABCD",
                                    secondsToImpact: 150, speedKnots: 140,
                                    approachFromBearing: 100, altitude: 3100))

        scripts = defs
    }

    /// Builds an aircraft that will arrive at the same point as ownship at the
    /// same time. `approachFromBearing` is the bearing from that meeting point
    /// back to where the aircraft starts, so it controls which side it comes from.
    private func collisionCourse(address: UInt32, callsign: String,
                                 secondsToImpact: Double, speedKnots: Double,
                                 approachFromBearing: Double, altitude: Int) -> Script {
        let hours = secondsToImpact / 3600
        let meeting = Geo.destination(lat: ownLat, lon: ownLon,
                                      bearingDegrees: ownTrack,
                                      distanceNM: ownSpeed * hours)
        let start = Geo.destination(lat: meeting.lat, lon: meeting.lon,
                                    bearingDegrees: approachFromBearing,
                                    distanceNM: speedKnots * hours)
        let track = Geo.bearingDegrees(lat1: start.lat, lon1: start.lon,
                                       lat2: meeting.lat, lon2: meeting.lon)

        var script = Script(address: address, callsign: callsign,
                            initialRangeNM: 0, initialBearing: 0,
                            track: track, speedKnots: speedKnots,
                            altitude: altitude, verticalSpeed: 0)
        script.latitude = start.lat
        script.longitude = start.lon
        return script
    }

    private func tick(interval: TimeInterval) {
        elapsed += interval
        advance(interval: interval)

        onPacket?(GDL90.encodeHeartbeat())

        let own = GDL90.Report(trafficAlert: false, addressType: 0, address: 0x400001,
                               latitude: ownLat, longitude: ownLon, positionValid: true,
                               altitudeFeet: ownAltitude, isAirborne: true,
                               groundSpeedKnots: ownSpeed, verticalSpeedFPM: 0,
                               trackDegrees: ownTrack, emitterCategory: 1,
                               callsign: "OWNSHIP")
        onPacket?(GDL90.encodeReport(id: .ownshipReport, report: own))
        onPacket?(GDL90.frame(body: [GDL90.MessageID.ownshipGeometricAltitude.rawValue,
                                     UInt8((ownAltitude / 5) >> 8),
                                     UInt8((ownAltitude / 5) & 0xFF), 0x00, 0x0A]))

        for script in scripts {
            let report = GDL90.Report(trafficAlert: false, addressType: 0,
                                      address: script.address,
                                      latitude: script.latitude, longitude: script.longitude,
                                      positionValid: true, altitudeFeet: script.altitude,
                                      isAirborne: true, groundSpeedKnots: script.speedKnots,
                                      verticalSpeedFPM: script.verticalSpeed,
                                      trackDegrees: script.track,
                                      emitterCategory: script.emitter,
                                      callsign: script.callsign)
            onPacket?(GDL90.encodeReport(id: .trafficReport, report: report))
        }
    }

    private func advance(interval: TimeInterval) {
        guard interval > 0 else { return }
        let hours = interval / 3600.0

        let moved = Geo.destination(lat: ownLat, lon: ownLon,
                                    bearingDegrees: ownTrack,
                                    distanceNM: ownSpeed * hours)
        ownLat = moved.lat
        ownLon = moved.lon

        for i in scripts.indices {
            let next = Geo.destination(lat: scripts[i].latitude, lon: scripts[i].longitude,
                                       bearingDegrees: scripts[i].track,
                                       distanceNM: scripts[i].speedKnots * hours)
            scripts[i].latitude = next.lat
            scripts[i].longitude = next.lon
        }
    }
}
