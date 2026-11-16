//
//  GDL90.swift
//  Sky Sentry
//
//  Decoder (and matching encoder) for the Garmin GDL90 datalink interface, which
//  is what a SkyEcho 2 broadcasts over its WiFi on UDP port 4000.
//
//  Frames look like:  0x7E <message id> <payload...> <crc lo> <crc hi> 0x7E
//  with 0x7E and 0x7D escaped inside the frame as 0x7D followed by (byte XOR 0x20).
//
//  The encoder exists so the built-in test traffic is fed through the very same
//  decode path as real hardware, and so this can later drive an external device.
//

import Foundation

enum GDL90 {

    // MARK: - Message IDs

    enum MessageID: UInt8 {
        case heartbeat = 0x00
        case initialization = 0x02
        case uplinkData = 0x07
        case ownshipReport = 0x0A
        case ownshipGeometricAltitude = 0x0B
        case trafficReport = 0x14
        case basicReport = 0x1E
        case longReport = 0x1F
        case foreFlightID = 0x65
    }

    // MARK: - Decoded messages

    enum Message {
        case heartbeat(gpsPositionValid: Bool)
        case ownship(Report)
        case ownshipGeometricAltitude(feet: Int)
        case traffic(Report)
        case other(id: UInt8)
    }

    /// The payload shared by the traffic report (0x14) and ownship report (0x0A):
    /// they use an identical 27-byte layout.
    struct Report {
        var trafficAlert: Bool
        var addressType: UInt8
        var address: UInt32
        var latitude: Double
        var longitude: Double
        var positionValid: Bool
        /// Pressure altitude in feet, nil if the target reports none.
        var altitudeFeet: Int?
        var isAirborne: Bool
        var groundSpeedKnots: Double?
        var verticalSpeedFPM: Double?
        var trackDegrees: Double?
        var emitterCategory: UInt8
        var callsign: String
    }

    // MARK: - CRC

    /// CRC-16-CCITT table, generated exactly as the GDL90 specification describes.
    private static let crcTable: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt16(i) << 8
            for _ in 0..<8 {
                let high = (crc & 0x8000) != 0
                crc <<= 1
                if high { crc ^= 0x1021 }
            }
            table[i] = crc
        }
        return table
    }()

    static func crc(for bytes: [UInt8]) -> UInt16 {
        var crc: UInt16 = 0
        for byte in bytes {
            crc = crcTable[Int(crc >> 8)] ^ (crc << 8) ^ UInt16(byte)
        }
        return crc
    }

    // MARK: - Framing

    /// Splits a datagram into unescaped frame bodies, discarding any frame whose
    /// CRC does not check out. A single UDP packet often carries several frames.
    static func extractFrames(from data: Data) -> [[UInt8]] {
        var frames: [[UInt8]] = []
        var current: [UInt8] = []
        var inFrame = false
        var escaping = false

        for byte in data {
            if byte == 0x7E {
                if inFrame, !current.isEmpty {
                    if let body = validatedBody(current) { frames.append(body) }
                }
                // A closing flag doubles as the opening flag of the next frame.
                current.removeAll(keepingCapacity: true)
                inFrame = true
                escaping = false
                continue
            }
            guard inFrame else { continue }

            if escaping {
                current.append(byte ^ 0x20)
                escaping = false
            } else if byte == 0x7D {
                escaping = true
            } else {
                current.append(byte)
            }
        }
        return frames
    }

    /// Strips and checks the trailing little-endian CRC.
    private static func validatedBody(_ frame: [UInt8]) -> [UInt8]? {
        guard frame.count >= 3 else { return nil }
        let body = Array(frame[0..<(frame.count - 2)])
        let received = UInt16(frame[frame.count - 2]) | (UInt16(frame[frame.count - 1]) << 8)
        return crc(for: body) == received ? body : nil
    }

    // MARK: - Decoding

    static func decode(frameBody body: [UInt8]) -> Message? {
        guard let id = body.first else { return nil }
        let payload = Array(body.dropFirst())

        switch MessageID(rawValue: id) {
        case .heartbeat:
            guard payload.count >= 1 else { return nil }
            // Status byte 1, bit 7 is the GPS position validity flag.
            return .heartbeat(gpsPositionValid: (payload[0] & 0x80) != 0)

        case .ownshipReport:
            guard let report = decodeReport(payload) else { return nil }
            return .ownship(report)

        case .trafficReport:
            guard let report = decodeReport(payload) else { return nil }
            return .traffic(report)

        case .ownshipGeometricAltitude:
            guard payload.count >= 2 else { return nil }
            var raw = Int(UInt16(payload[0]) << 8 | UInt16(payload[1]))
            if raw > 0x7FFF { raw -= 0x10000 }
            return .ownshipGeometricAltitude(feet: raw * 5)

        default:
            return .other(id: id)
        }
    }

    /// Decodes the 27-byte body shared by message 0x0A and 0x14.
    private static func decodeReport(_ p: [UInt8]) -> Report? {
        guard p.count >= 27 else { return nil }

        let trafficAlert = (p[0] >> 4) != 0
        let addressType = p[0] & 0x0F
        let address = UInt32(p[1]) << 16 | UInt32(p[2]) << 8 | UInt32(p[3])

        let latitude = semicirclesToDegrees(p[4], p[5], p[6])
        let longitude = semicirclesToDegrees(p[7], p[8], p[9])

        // 12-bit altitude: 25 ft per count, offset 1000 ft. 0xFFF means "unavailable".
        let altRaw = (UInt16(p[10]) << 4) | (UInt16(p[11]) >> 4)
        let altitudeFeet: Int? = altRaw == 0xFFF ? nil : Int(altRaw) * 25 - 1000

        let misc = p[11] & 0x0F
        let isAirborne = (misc & 0x08) != 0

        let nic = p[12] >> 4
        let nacp = p[12] & 0x0F
        // Both integrity figures zero means the position is not usable.
        let positionValid = !(nic == 0 && nacp == 0)

        // 12-bit horizontal velocity in knots. 0xFFF means "unavailable".
        let hvRaw = (UInt16(p[13]) << 4) | (UInt16(p[14]) >> 4)
        let groundSpeedKnots: Double? = hvRaw == 0xFFF ? nil : Double(hvRaw)

        // 12-bit signed vertical velocity, 64 fpm per count. 0x800 means "unavailable".
        let vvRaw = (UInt16(p[14] & 0x0F) << 8) | UInt16(p[15])
        var verticalSpeedFPM: Double?
        if vvRaw != 0x800 {
            var signed = Int(vvRaw)
            if signed > 0x7FF { signed -= 0x1000 }
            verticalSpeedFPM = Double(signed) * 64
        }

        // Track/heading is a single byte covering the full circle.
        let trackDegrees = Double(p[16]) * (360.0 / 256.0)

        let emitterCategory = p[17]
        let callsign = String(bytes: p[18..<26], encoding: .ascii)?
            .trimmingCharacters(in: CharacterSet(charactersIn: " \0")) ?? ""

        return Report(trafficAlert: trafficAlert,
                      addressType: addressType,
                      address: address,
                      latitude: latitude,
                      longitude: longitude,
                      positionValid: positionValid,
                      altitudeFeet: altitudeFeet,
                      isAirborne: isAirborne,
                      groundSpeedKnots: groundSpeedKnots,
                      verticalSpeedFPM: verticalSpeedFPM,
                      trackDegrees: trackDegrees,
                      emitterCategory: emitterCategory,
                      callsign: callsign)
    }

    /// 24-bit two's complement semicircles, 180 / 2^23 degrees per count.
    private static func semicirclesToDegrees(_ b0: UInt8, _ b1: UInt8, _ b2: UInt8) -> Double {
        var value = Int(UInt32(b0) << 16 | UInt32(b1) << 8 | UInt32(b2))
        if value > 0x7FFFFF { value -= 0x1000000 }
        return Double(value) * (180.0 / 8388608.0)
    }

    // MARK: - Encoding

    /// Wraps a message body (id + payload) in flags, CRC and byte stuffing.
    static func frame(body: [UInt8]) -> Data {
        let checksum = crc(for: body)
        var withCRC = body
        withCRC.append(UInt8(checksum & 0xFF))
        withCRC.append(UInt8(checksum >> 8))

        var out: [UInt8] = [0x7E]
        for byte in withCRC {
            if byte == 0x7E || byte == 0x7D {
                out.append(0x7D)
                out.append(byte ^ 0x20)
            } else {
                out.append(byte)
            }
        }
        out.append(0x7E)
        return Data(out)
    }

    static func encodeHeartbeat(gpsPositionValid: Bool = true) -> Data {
        // Status byte 1: bit 0 initialised, bit 7 GPS position valid.
        let status1: UInt8 = 0x01 | (gpsPositionValid ? 0x80 : 0x00)
        return frame(body: [MessageID.heartbeat.rawValue, status1, 0x00, 0x00, 0x00])
    }

    static func encodeReport(id: MessageID, report: Report) -> Data {
        var p = [UInt8](repeating: 0, count: 27)

        p[0] = ((report.trafficAlert ? 1 : 0) << 4) | (report.addressType & 0x0F)
        p[1] = UInt8((report.address >> 16) & 0xFF)
        p[2] = UInt8((report.address >> 8) & 0xFF)
        p[3] = UInt8(report.address & 0xFF)

        let lat = degreesToSemicircles(report.latitude)
        p[4] = UInt8((lat >> 16) & 0xFF); p[5] = UInt8((lat >> 8) & 0xFF); p[6] = UInt8(lat & 0xFF)
        let lon = degreesToSemicircles(report.longitude)
        p[7] = UInt8((lon >> 16) & 0xFF); p[8] = UInt8((lon >> 8) & 0xFF); p[9] = UInt8(lon & 0xFF)

        let altRaw: UInt16
        if let feet = report.altitudeFeet {
            altRaw = UInt16(max(0, min(0xFFE, (feet + 1000) / 25)))
        } else {
            altRaw = 0xFFF
        }
        p[10] = UInt8(altRaw >> 4)
        let misc: UInt8 = (report.isAirborne ? 0x08 : 0x00) | 0x01  // 0x01: track is true track
        p[11] = UInt8((altRaw & 0x0F) << 4) | misc

        p[12] = (10 << 4) | 10  // NIC / NACp, both healthy

        let hvRaw = UInt16(max(0, min(0xFFE, Int(report.groundSpeedKnots ?? 0))))
        p[13] = UInt8(hvRaw >> 4)

        let vvRaw: UInt16
        if let fpm = report.verticalSpeedFPM {
            var counts = Int((fpm / 64).rounded())
            counts = max(-2047, min(2047, counts))
            vvRaw = UInt16(bitPattern: Int16(counts)) & 0x0FFF
        } else {
            vvRaw = 0x800
        }
        p[14] = UInt8((hvRaw & 0x0F) << 4) | UInt8(vvRaw >> 8)
        p[15] = UInt8(vvRaw & 0xFF)

        p[16] = UInt8(Int((report.trackDegrees ?? 0).normalizedDegrees / (360.0 / 256.0)) & 0xFF)
        p[17] = report.emitterCategory

        let name = report.callsign.padding(toLength: 8, withPad: " ", startingAt: 0)
        for (i, scalar) in name.unicodeScalars.prefix(8).enumerated() {
            p[18 + i] = UInt8(scalar.value & 0x7F)
        }
        p[26] = 0

        return frame(body: [id.rawValue] + p)
    }

    private static func degreesToSemicircles(_ degrees: Double) -> Int32 {
        let raw = Int32((degrees / (180.0 / 8388608.0)).rounded())
        return raw & 0xFFFFFF
    }
}
