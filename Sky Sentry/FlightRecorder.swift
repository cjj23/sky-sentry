//
//  FlightRecorder.swift
//  Eyes Out
//
//  Records a flight for post-flight analysis. Two files per session:
//
//    raw.bin    every datagram exactly as it came off the wire, with a relative
//               timestamp, so a whole flight can be replayed through the decoder
//               afterwards and any decode change re-tested against real data.
//
//    log.jsonl  one JSON object per second describing ownship and every target
//               heard, each tagged with what the app did with it.
//
//  That second file is the point of the exercise. When traffic is visible on
//  another display but not on ours, the question is whether we never heard it or
//  heard it and filtered it out — and only a log that records the rejects can
//  tell the two apart.
//

import Foundation

final class FlightRecorder {

    struct Stats: Equatable {
        var isRecording = false
        var sessionName: String?
        var startedAt: Date?
        var rawBytes: Int = 0
        var datagrams: Int = 0
        var samples: Int = 0
        /// Every ICAO address heard this session, whether displayed or not.
        var uniqueTargets: Int = 0
        /// How many targets fell into each outcome, cumulatively.
        var outcomeCounts: [String: Int] = [:]

        var duration: TimeInterval {
            guard let startedAt else { return 0 }
            return Date().timeIntervalSince(startedAt)
        }
    }

    /// Where sessions are written. Exposed in Files.app via UIFileSharingEnabled.
    static var recordingsDirectory: URL {
        let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        return documents.appendingPathComponent("Recordings", isDirectory: true)
    }

    private let queue = DispatchQueue(label: "EyesOut.FlightRecorder")
    private let lock = NSLock()

    private var _stats = Stats()
    private var sessionURL: URL?
    private var rawHandle: FileHandle?
    private var logHandle: FileHandle?
    private var sessionStart: Date?
    private var seenAddresses: Set<UInt32> = []
    /// The JSON log is throttled to 1 Hz; the display recomputes far faster.
    private var lastSampleAt: Date?

    var stats: Stats {
        lock.lock(); defer { lock.unlock() }
        return _stats
    }

    var isRecording: Bool {
        lock.lock(); defer { lock.unlock() }
        return _stats.isRecording
    }

    // MARK: - Session lifecycle

    @discardableResult
    func start(source: String, config: AlertConfig) -> URL? {
        stop()

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HHmm'Z'"
        formatter.timeZone = TimeZone(identifier: "UTC")
        let name = formatter.string(from: Date())

        let folder = Self.recordingsDirectory.appendingPathComponent(name, isDirectory: true)
        let manager = FileManager.default

        do {
            try manager.createDirectory(at: folder, withIntermediateDirectories: true)

            let metadata: [String: Any] = [
                "app": AppInfo.displayName,
                "version": AppInfo.versionString,
                "startedUTC": ISO8601DateFormatter().string(from: Date()),
                "source": source,
                "displayRangeNM": config.displayRangeNM,
                "cautionRangeNM": config.cautionRangeNM,
                "warningRangeNM": config.warningRangeNM,
                "verticalFilterFeet": config.verticalFilterFeet,
                "maxDisplayedTargets": config.maxDisplayedTargets,
            ]
            let json = try JSONSerialization.data(withJSONObject: metadata, options: [.prettyPrinted, .sortedKeys])
            try json.write(to: folder.appendingPathComponent("session.json"))

            manager.createFile(atPath: folder.appendingPathComponent("raw.bin").path, contents: nil)
            manager.createFile(atPath: folder.appendingPathComponent("log.jsonl").path, contents: nil)

            let raw = try FileHandle(forWritingTo: folder.appendingPathComponent("raw.bin"))
            let log = try FileHandle(forWritingTo: folder.appendingPathComponent("log.jsonl"))

            lock.lock()
            sessionURL = folder
            rawHandle = raw
            logHandle = log
            sessionStart = Date()
            seenAddresses = []
            lastSampleAt = nil
            _stats = Stats(isRecording: true, sessionName: name, startedAt: Date())
            lock.unlock()

            return folder
        } catch {
            return nil
        }
    }

    func stop() {
        lock.lock()
        let raw = rawHandle
        let log = logHandle
        rawHandle = nil
        logHandle = nil
        sessionURL = nil
        sessionStart = nil
        _stats.isRecording = false
        lock.unlock()

        queue.async {
            try? raw?.close()
            try? log?.close()
        }
    }

    // MARK: - Raw capture

    /// Called from the receiver's queue for every datagram, live or simulated.
    /// Record format: 8-byte big-endian milliseconds since session start,
    /// 2-byte big-endian length, then the bytes.
    func recordRaw(_ data: Data) {
        lock.lock()
        guard _stats.isRecording, let handle = rawHandle, let start = sessionStart else {
            lock.unlock(); return
        }
        _stats.rawBytes += data.count
        _stats.datagrams += 1
        lock.unlock()

        let elapsed = UInt64(max(0, Date().timeIntervalSince(start)) * 1000)
        let length = UInt16(min(data.count, Int(UInt16.max)))

        var record = Data(capacity: 10 + data.count)
        withUnsafeBytes(of: elapsed.bigEndian) { record.append(contentsOf: $0) }
        withUnsafeBytes(of: length.bigEndian) { record.append(contentsOf: $0) }
        record.append(data.prefix(Int(length)))

        queue.async { try? handle.write(contentsOf: record) }
    }

    // MARK: - Decoded snapshot

    func record(ownship: Ownship?, dispositions: [TargetDisposition], at now: Date) {
        lock.lock()
        guard _stats.isRecording, let handle = logHandle, let start = sessionStart else {
            lock.unlock(); return
        }
        if let last = lastSampleAt, now.timeIntervalSince(last) < 1.0 {
            lock.unlock(); return
        }
        lastSampleAt = now

        for disposition in dispositions {
            seenAddresses.insert(disposition.target.icaoAddress)
            _stats.outcomeCounts[disposition.outcome.category, default: 0] += 1
        }
        _stats.uniqueTargets = seenAddresses.count
        _stats.samples += 1
        let elapsed = now.timeIntervalSince(start)
        lock.unlock()

        var payload: [String: Any] = [
            "t": (elapsed * 10).rounded() / 10,
            "utc": ISO8601DateFormatter().string(from: now),
        ]

        if let ownship {
            payload["own"] = [
                "lat": ownship.latitude,
                "lon": ownship.longitude,
                "pressureAlt": ownship.pressureAltitudeFeet as Any,
                "geoAlt": ownship.geometricAltitudeFeet as Any,
                "track": ownship.trackDegrees,
                "gs": ownship.groundSpeedKnots,
            ]
        }

        payload["targets"] = dispositions.map { disposition -> [String: Any] in
            let target = disposition.target
            var entry: [String: Any] = [
                "icao": String(format: "%06X", target.icaoAddress),
                "callsign": target.callsign,
                "outcome": disposition.outcome.label,
            ]
            if let range = disposition.rangeNM { entry["rangeNM"] = (range * 100).rounded() / 100 }
            if let latitude = target.latitude { entry["lat"] = latitude }
            if let longitude = target.longitude { entry["lon"] = longitude }
            if let rangeOnly = target.rangeOnlyNM { entry["rangeOnlyNM"] = rangeOnly }
            if let altitude = target.altitudeFeet { entry["altFt"] = altitude }
            if let track = target.trackDegrees { entry["track"] = track }
            if let speed = target.groundSpeedKnots { entry["gs"] = speed }
            entry["airborne"] = target.isAirborne
            return entry
        }

        guard var line = try? JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys]) else { return }
        line.append(0x0A)
        queue.async { try? handle.write(contentsOf: line) }
    }

    // MARK: - Sessions on disk

    struct Session: Identifiable, Hashable {
        let url: URL
        let name: String
        let sizeBytes: Int
        let modified: Date
        var id: URL { url }
    }

    static func existingSessions() -> [Session] {
        let manager = FileManager.default
        guard let entries = try? manager.contentsOfDirectory(
            at: recordingsDirectory,
            includingPropertiesForKeys: [.contentModificationDateKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }

        return entries.compactMap { url -> Session? in
            guard (try? url.resourceValues(forKeys: [.isDirectoryKey]))?.isDirectory == true else { return nil }
            let files = (try? manager.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let size = files.reduce(0) { total, file in
                total + ((try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0)
            }
            let modified = (try? url.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate ?? .distantPast
            return Session(url: url, name: url.lastPathComponent, sizeBytes: size, modified: modified)
        }
        .sorted { $0.modified > $1.modified }
    }

    /// Zips a session folder for sharing. NSFileCoordinator's `.forUploading`
    /// option is the only zip facility in Foundation, and it hands back a
    /// temporary file that must be copied before the closure returns.
    static func exportArchive(for session: Session) -> URL? {
        var coordinatorError: NSError?
        var result: URL?

        NSFileCoordinator().coordinate(readingItemAt: session.url,
                                       options: [.forUploading],
                                       error: &coordinatorError) { temporary in
            let destination = FileManager.default.temporaryDirectory
                .appendingPathComponent("\(session.name).zip")
            try? FileManager.default.removeItem(at: destination)
            do {
                try FileManager.default.copyItem(at: temporary, to: destination)
                result = destination
            } catch {
                result = nil
            }
        }
        return coordinatorError == nil ? result : nil
    }

    static func delete(_ session: Session) {
        try? FileManager.default.removeItem(at: session.url)
    }
}
