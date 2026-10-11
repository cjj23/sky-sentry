//
//  TrafficModel.swift
//  Sky Sentry
//
//  Holds the current traffic picture: takes decoded GDL90 messages in, and
//  publishes a sorted list of relative solutions plus one overall threat level
//  for the background colour.
//

import Foundation
import CoreLocation
import Observation

@MainActor
@Observable
final class TrafficModel {

    enum Source: String {
        case simulator = "TEST FEED"
        case live = "SKYECHO"
    }

    // MARK: - Published state

    private(set) var ownship: Ownship?
    private(set) var solutions: [TrafficSolution] = []
    private(set) var overallThreat: ThreatLevel = .clear
    private(set) var receiverState: GDL90Receiver.State = .idle
    private(set) var lastPacket: Date?
    /// Targets held but not drawn, e.g. filtered out on altitude.
    private(set) var filteredCount: Int = 0
    /// What happened to every target on the last pass, for the diagnostic log.
    private(set) var lastDispositions: [TargetDisposition] = []
    /// Republished each refresh so the diagnostics screen updates live.
    private(set) var recorderStats = FlightRecorder.Stats()

    let recorder = FlightRecorder()
    let watchLink = WatchLink()
    let location = LocationProvider()

    var config = AlertConfig.loaded() {
        didSet {
            config.save()
            recompute()
        }
    }

    /// Remembered across launches: having to reselect the receiver before every
    /// flight is exactly the sort of step that gets forgotten.
    var source: Source = Source(rawValue: UserDefaults.standard.string(forKey: "trafficSource") ?? "")
        ?? .simulator {
        didSet {
            guard oldValue != source else { return }
            UserDefaults.standard.set(source.rawValue, forKey: "trafficSource")
            restartSource()
        }
    }

    /// True when we have heard nothing at all recently.
    var isStale: Bool {
        guard let lastPacket else { return true }
        return Date().timeIntervalSince(lastPacket) > 5
    }

    /// The receiver is not telling us anything usable — no packets, or the
    /// socket never came up. The display must not show a reassuring green
    /// "clear" in this state: no data is not the same as no traffic.
    var isSignalLost: Bool {
        if case .failed = receiverState { return true }
        return isStale
    }

    /// Why the receiver failed, if it did.
    var receiverFault: String? {
        if case .failed(let reason) = receiverState { return reason }
        return nil
    }

    // MARK: - Internals

    private var targets: [UInt32: TrafficTarget] = [:]
    private var bearingTracks: [UInt32: BearingTrack] = [:]
    private let receiver = GDL90Receiver()
    private let simulator = TrafficSimulator()
    private var refreshTimer: Timer?

    init() {
        receiver.onMessage = { [weak self] message in
            self?.handle(message)
        }
        receiver.onStateChange = { [weak self] state in
            self?.receiverState = state
        }
        simulator.onPacket = { [weak self] data in
            // Straight into the same decode path the radio uses.
            self?.receiver.ingest(data)
        }
        receiver.onRawData = { [weak self] data in
            self?.recorder.recordRaw(data)
        }
    }

    /// Entry point for sources that measure distance but not direction — a Mode S
    /// interrogation, or a FLARM contact reported without a bearing. The display
    /// shows these as a pulsing ring rather than an arrow, since drawing an arrow
    /// would invent a direction we do not have.
    ///
    /// Nothing calls this yet: the SkyEcho's GDL90 cannot express a bearingless
    /// contact, and the test feed deliberately produces none. It is the hook for
    /// a PilotAware or PowerFLARM source.
    func ingestRangeOnly(address: UInt32, callsign: String,
                         rangeNM: Double, altitudeFeet: Int?) {
        lastPacket = Date()
        targets[address] = TrafficTarget(icaoAddress: address,
                                         callsign: callsign,
                                         latitude: nil,
                                         longitude: nil,
                                         rangeOnlyNM: rangeNM,
                                         altitudeFeet: altitudeFeet,
                                         trackDegrees: nil,
                                         groundSpeedKnots: nil,
                                         verticalSpeedFPM: nil,
                                         isAirborne: true,
                                         lastUpdate: Date())
    }

    // MARK: - Recording

    func startRecording() {
        recorder.start(source: source.rawValue, config: config)
        recorderStats = recorder.stats
    }

    func stopRecording() {
        recorder.stop()
        recorderStats = recorder.stats
    }

    func start() {
        // SwiftUI calls onAppear again whenever the view's identity is rebuilt —
        // returning from a sheet, or the subscription state resolving. Without
        // this guard each call added another repeating timer to the run loop
        // while leaking the previous one, so recompute ran an extra time per
        // tick, for ever, and the retained closures accumulated.
        guard refreshTimer == nil else { return }

        watchLink.start()
        location.start()
        restartSource()

        // Keeps stale targets pruned and the picture current even between packets.
        let timer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            guard let self else { return }
            Task { @MainActor in self.recompute() }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        location.stop()
        receiver.stop()
        simulator.stop()
    }

    private func restartSource() {
        receiver.stop()
        simulator.stop()
        targets.removeAll()
        bearingTracks.removeAll()
        ownship = nil
        lastPacket = nil
        receiverState = .idle

        switch source {
        case .simulator: simulator.start()
        case .live: receiver.start()
        }
        recompute()
    }

    // MARK: - Ingest

    private func handle(_ message: GDL90.Message) {
        lastPacket = Date()

        switch message {
        case .heartbeat:
            break

        case .ownship(let report):
            guard report.positionValid else { break }
            ownship = Ownship(latitude: report.latitude,
                              longitude: report.longitude,
                              pressureAltitudeFeet: report.altitudeFeet,
                              geometricAltitudeFeet: ownship?.geometricAltitudeFeet,
                              trackDegrees: report.trackDegrees ?? 0,
                              groundSpeedKnots: report.groundSpeedKnots ?? 0,
                              verticalSpeedFPM: report.verticalSpeedFPM,
                              lastUpdate: Date())

        case .ownshipGeometricAltitude(let feet):
            ownship?.geometricAltitudeFeet = feet

        case .traffic(let report):
            guard report.positionValid else { break }
            targets[report.address] = TrafficTarget(icaoAddress: report.address,
                                                    callsign: report.callsign,
                                                    latitude: report.latitude,
                                                    longitude: report.longitude,
                                                    rangeOnlyNM: nil,
                                                    altitudeFeet: report.altitudeFeet,
                                                    trackDegrees: report.trackDegrees,
                                                    groundSpeedKnots: report.groundSpeedKnots,
                                                    verticalSpeedFPM: report.verticalSpeedFPM,
                                                    isAirborne: report.isAirborne,
                                                    category: EmitterCategory(code: report.emitterCategory),
                                                    lastUpdate: Date())

        case .other:
            break
        }
    }

    // MARK: - Relative picture

    /// Ownship derived from the phone's GPS, used only while the receiver has
    /// not supplied one. Course is only meaningful when actually moving, so a
    /// stationary fix gives track 0 and the display is effectively north-up
    /// until the aircraft starts rolling.
    private func fallbackOwnship() -> Ownship? {
        guard location.hasUsableFix, let fix = location.latest else { return nil }
        return Ownship(latitude: fix.coordinate.latitude,
                       longitude: fix.coordinate.longitude,
                       // Geometric altitude, not pressure: relative-altitude
                       // comparisons against targets will be approximate until
                       // the receiver supplies its own pressure altitude.
                       pressureAltitudeFeet: fix.verticalAccuracy > 0
                           ? Int(fix.altitude * 3.280_84) : nil,
                       geometricAltitudeFeet: fix.verticalAccuracy > 0
                           ? Int(fix.altitude * 3.280_84) : nil,
                       trackDegrees: fix.course >= 0 ? fix.course : 0,
                       groundSpeedKnots: fix.speed >= 0 ? fix.speed * 1.943_84 : 0,
                       lastUpdate: fix.timestamp)
    }

    private func recompute() {
        let now = Date()
        targets = targets.filter { now.timeIntervalSince($0.value.lastUpdate) < config.targetStaleAfter }
        bearingTracks = bearingTracks.filter { targets[$0.key] != nil }

        // Without an ownship position there is no relative picture at all, and
        // traffic is received only to be discarded. If the receiver has not got
        // a fix yet, stand in with the phone's own.
        guard let ownship = ownship ?? fallbackOwnship() else {
            solutions = []
            overallThreat = .clear
            filteredCount = 0
            return
        }

        var resolved: [TrafficSolution] = []
        var filtered = 0
        var dispositions: [TargetDisposition] = []

        for target in targets.values {
            // Ground vehicles and obstacles share the datalink but are not
            // traffic to avoid in the air. Still recorded, so the diagnostic log
            // shows they were heard rather than missed.
            guard target.category.isAirborneTraffic else {
                dispositions.append(TargetDisposition(target: target, rangeNM: nil,
                                                      outcome: .notAircraft))
                continue
            }

            // Work out where it is. A located target gives range and bearing; a
            // range-only contact (Mode S, bearingless FLARM) gives range alone.
            let range: Double
            var bearing: Double?

            if let latitude = target.latitude, let longitude = target.longitude {
                range = Geo.distanceNM(lat1: ownship.latitude, lon1: ownship.longitude,
                                       lat2: latitude, lon2: longitude)
                bearing = Geo.bearingDegrees(lat1: ownship.latitude, lon1: ownship.longitude,
                                             lat2: latitude, lon2: longitude)
            } else if let rangeOnly = target.rangeOnlyNM {
                range = rangeOnly
            } else {
                dispositions.append(TargetDisposition(target: target, rangeNM: nil, outcome: .noPosition))
                continue
            }

            guard range <= config.plotRangeNM else {
                dispositions.append(TargetDisposition(target: target, rangeNM: range, outcome: .beyondRange))
                continue
            }

            // Altitude band is a DISPLAY filter, exactly as the ABV/N/BLW
            // selector is on a TCAS traffic display: outside the band it is not
            // drawn. It says nothing about whether the aircraft is a threat.
            var relativeAltitude: Int?
            if let theirs = target.altitudeFeet, let ours = ownship.pressureAltitudeFeet {
                relativeAltitude = theirs - ours
                if !config.altitudeBand.includes(relativeAltitudeFeet: theirs - ours) {
                    filtered += 1
                    dispositions.append(TargetDisposition(target: target, rangeNM: range,
                                                          outcome: .verticalFilter(theirs - ours)))
                    continue
                }
            }

            // Collision projection needs a bearing to work on, so it only applies
            // to located targets. A range-only contact gets the range verdict alone.
            var trend = BearingTrack.Trend()
            if let bearing {
                // Bearing history is sampled per received position, not per redraw,
                // so the rate is measured against real reports.
                var track = bearingTracks[target.icaoAddress] ?? BearingTrack()
                track.add(bearing: bearing, range: range,
                          reportedAt: target.lastUpdate, window: config.cbdrWindow)
                bearingTracks[target.icaoAddress] = track
                trend = track.trend(currentRange: range, config: config)
            }

            // Rate at which the vertical gap is shrinking: positive means
            // converging, whichever of the two is higher.
            var verticalClosure: Double?
            if let separation = relativeAltitude, let theirs = target.verticalSpeedFPM {
                let rateOfChange = theirs - (ownship.verticalSpeedFPM ?? 0)
                verticalClosure = separation >= 0 ? -rateOfChange : rateOfChange
            }

            let level = config.profile.level(
                forOwnAltitudeFeet: ownship.pressureAltitudeFeet.map(Double.init))
            let rangeThreat = ThreatLevel.evaluate(rangeNM: range,
                                                   closureKnots: trend.closureKnots,
                                                   relativeAltitudeFeet: relativeAltitude,
                                                   verticalClosureFPM: verticalClosure,
                                                   level: level,
                                                   config: config)
            dispositions.append(TargetDisposition(target: target, rangeNM: range, outcome: .displayed))

            resolved.append(TrafficSolution(target: target,
                                            rangeNM: range,
                                            bearingTrue: bearing,
                                            relativeBearing: bearing.map {
                                                ($0 - ownship.trackDegrees).normalizedDegrees
                                            },
                                            relativeAltitudeFeet: relativeAltitude,
                                            threat: trend.isConverging ? rangeThreat.escalated : rangeThreat,
                                            rangeThreat: rangeThreat,
                                            isConverging: trend.isConverging,
                                            closureKnots: trend.closureKnots,
                                            secondsToCPA: trend.secondsToCPA,
                                            missDistanceNM: trend.missDistanceNM))
        }

        resolved.sort { $0.rangeNM < $1.rangeNM }

        // Anything past the display cap is still recorded as seen, so the
        // diagnostic log can show it was received rather than missed.
        if resolved.count > config.maxDisplayedTargets {
            let dropped = Set(resolved.dropFirst(config.maxDisplayedTargets).map(\.target.icaoAddress))
            for index in dispositions.indices where dropped.contains(dispositions[index].target.icaoAddress) {
                dispositions[index].outcome = .cappedByLimit
            }
        }

        solutions = Array(resolved.prefix(config.maxDisplayedTargets))
        overallThreat = solutions.map(\.threat).max() ?? .clear
        filteredCount = filtered
        lastDispositions = dispositions

        recorder.record(ownship: ownship, dispositions: dispositions, at: now)
        recorderStats = recorder.stats

        // The wrist gets the same verdict the screen does, including the grey
        // "no picture" state — silence on the watch must mean the same thing.
        watchLink.update(solutions: solutions,
                         overallThreat: overallThreat,
                         hasPicture: !isSignalLost)
    }
}

// MARK: - Diagnostics

/// What happened to one received target on this pass: shown, or dropped and why.
/// This is what makes the difference between "we never heard it" and "we heard
/// it and threw it away", which is the question a post-flight log has to answer.
struct TargetDisposition {
    enum Outcome: Equatable {
        case displayed
        case beyondRange
        case verticalFilter(Int)
        case noPosition
        case cappedByLimit
        case notAircraft

        /// Detailed, per-target, for the log line.
        var label: String {
            switch self {
            case .displayed:              return "displayed"
            case .beyondRange:            return "beyond-range"
            case .verticalFilter(let ft): return "vertical-filter(\(ft)ft)"
            case .noPosition:             return "no-position"
            case .cappedByLimit:          return "capped-by-limit"
            case .notAircraft:            return "not-aircraft"
            }
        }

        /// Stable key for tallying. `label` embeds the altitude difference, so
        /// counting by it would mint a new bucket for every distinct value and
        /// grow without bound over a flight.
        var category: String {
            switch self {
            case .displayed:      return "displayed"
            case .beyondRange:    return "beyond-range"
            case .verticalFilter: return "vertical-filter"
            case .noPosition:     return "no-position"
            case .cappedByLimit:  return "capped-by-limit"
            case .notAircraft:    return "not-aircraft"
            }
        }
    }

    let target: TrafficTarget
    let rangeNM: Double?
    var outcome: Outcome
}

// MARK: - Bearing history

/// Rolling history of one target's line-of-sight bearing and range, used to spot
/// the constant-bearing-decreasing-range geometry that means a collision course.
private struct BearingTrack {
    private struct Sample {
        let time: TimeInterval
        /// Bearing unwrapped past 360 degrees, so a target drifting through north
        /// gives a smooth line rather than a 360-degree jump.
        let bearing: Double
        let range: Double
    }

    private var samples: [Sample] = []
    private var lastReportAt: Date?
    private var lastRawBearing: Double?
    private var unwrapped: Double = 0

    mutating func add(bearing: Double, range: Double, reportedAt: Date, window: TimeInterval) {
        // One sample per received report; the display refreshes faster than that.
        guard lastReportAt != reportedAt else { return }
        lastReportAt = reportedAt

        if let previous = lastRawBearing {
            var delta = bearing - previous
            if delta > 180 { delta -= 360 }
            if delta < -180 { delta += 360 }
            unwrapped += delta
        } else {
            unwrapped = bearing
        }
        lastRawBearing = bearing

        let time = reportedAt.timeIntervalSinceReferenceDate
        samples.append(Sample(time: time, bearing: unwrapped, range: range))
        samples.removeAll { time - $0.time > window }
    }

    struct Trend {
        var isConverging = false
        var closureKnots: Double?
        var secondsToCPA: Double?
        var missDistanceNM: Double?
    }

    /// Projects the closest point of approach from how the line of sight is
    /// moving. Treating the bearing rate as a transverse velocity and the range
    /// rate as a radial one gives the full relative velocity, and from that both
    /// how long until we are nearest and how far apart we will be.
    func trend(currentRange: Double, config: AlertConfig) -> Trend {
        guard samples.count >= config.cbdrMinSamples,
              let first = samples.first, let last = samples.last,
              last.time - first.time >= config.cbdrMinSpan
        else { return Trend() }

        let times = samples.map(\.time)
        guard let bearingRateDeg = Self.slope(x: times, y: samples.map(\.bearing)),
              let rangeRate = Self.slope(x: times, y: samples.map(\.range))
        else { return Trend() }

        // Range rate is nm per second; negative means closing.
        let closureKnots = -rangeRate * 3600
        var trend = Trend(closureKnots: closureKnots)

        let omega = bearingRateDeg * .pi / 180          // rad/s
        let transverse = currentRange * omega           // nm/s across the line of sight
        let relativeSpeed = (rangeRate * rangeRate + transverse * transverse).squareRoot()
        guard relativeSpeed > 1e-6 else { return trend }

        let secondsToCPA = -currentRange * rangeRate / (relativeSpeed * relativeSpeed)
        let missDistance = currentRange * abs(transverse) / relativeSpeed

        trend.secondsToCPA = secondsToCPA
        trend.missDistanceNM = missDistance
        trend.isConverging = closureKnots >= config.cbdrMinClosureKnots
            && secondsToCPA > 0
            && secondsToCPA <= config.cpaWarnSeconds
            && missDistance <= config.cpaMissDistanceNM
        return trend
    }

    /// Least-squares gradient, which smooths out GPS jitter far better than
    /// differencing the first and last samples would.
    private static func slope(x: [Double], y: [Double]) -> Double? {
        guard x.count == y.count, x.count > 1 else { return nil }
        let n = Double(x.count)
        let meanX = x.reduce(0, +) / n
        let meanY = y.reduce(0, +) / n

        var numerator = 0.0
        var denominator = 0.0
        for i in x.indices {
            let dx = x[i] - meanX
            numerator += dx * (y[i] - meanY)
            denominator += dx * dx
        }
        guard denominator > 0 else { return nil }
        return numerator / denominator
    }
}
