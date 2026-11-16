//
//  GDL90Receiver.swift
//  Sky Sentry
//
//  Listens for GDL90 datagrams on UDP port 4000, which is what a SkyEcho 2
//  broadcasts once the phone has joined its WiFi network.
//
//  This uses BSD sockets rather than Network framework. That is deliberate and
//  against the usual advice: Apple's own guidance is that Network framework's
//  UDP broadcast support is "so limited as to be useless in practice", and that
//  BSD sockets are the only workable option for broadcast traffic. There are
//  also reports of NWConnection failing with EACCES on broadcast under iOS 26
//  even with the entitlement granted.
//  See https://developer.apple.com/forums/thread/772642
//
//  NOTE: since iOS 14, *receiving* broadcast UDP requires the
//  com.apple.developer.networking.multicast entitlement, which Apple grants on
//  request for exactly this use (EFB / traffic receivers). The rule splits on
//  unicast versus broadcast, not on send versus receive, so a receive-only app
//  still needs it. Without it the sockets bind happily but no packets arrive.
//  The built-in simulator needs no entitlement, so development can proceed
//  without it.
//

import Foundation
import Darwin
import OSLog

final class GDL90Receiver {

    private static let log = Logger(subsystem: "uk.co.chrisjones.skysentry",
                                    category: "GDL90Receiver")

    enum State: Equatable {
        case idle
        case listening
        case receiving
        case failed(String)
    }

    /// Called on the main queue for every successfully decoded message.
    var onMessage: ((GDL90.Message) -> Void)?
    /// Called on the main queue whenever the listener state changes.
    var onStateChange: ((State) -> Void)?
    /// Called on the receiver's own queue with every datagram before decoding,
    /// so a recording captures exactly what arrived, including frames we fail
    /// to decode. Those are often the interesting ones.
    var onRawData: ((Data) -> Void)?

    private let port: UInt16
    private let queue = DispatchQueue(label: "SkySentry.GDL90Receiver")
    /// One read source per bound socket; cancelling a source closes its socket.
    private var sources: [DispatchSourceRead] = []
    /// Reused across reads. Only touched on `queue`, which is serial.
    private var buffer = [UInt8](repeating: 0, count: 8192)

    init(port: UInt16 = 4000) {
        self.port = port
    }

    // MARK: - Lifecycle

    func start() {
        stop()
        queue.async { [weak self] in
            guard let self else { return }

            // Bind one socket per candidate interface. Apple's guidance is to be
            // explicitly interface-specific for broadcast rather than relying on
            // the default route, which is unpredictable when the phone has both
            // WiFi and cellular up.
            var opened: [DispatchSourceRead] = []
            var lastError: String?

            let interfaces = Self.broadcastInterfaces()
            Self.log.notice("candidate interfaces: \(interfaces.map(\.name).joined(separator: ", "), privacy: .public)")

            for interface in interfaces {
                do {
                    opened.append(try self.makeSource(interfaceIndex: interface.index))
                    Self.log.notice("bound port \(self.port) on \(interface.name, privacy: .public)")
                } catch {
                    lastError = "\(interface.name): \(error.localizedDescription)"
                    Self.log.error("bind failed on \(interface.name, privacy: .public): \(error.localizedDescription, privacy: .public)")
                }
            }

            // Fall back to an unbound socket if no interface looked suitable —
            // notably in the Simulator, where the WiFi interface is the host's.
            if opened.isEmpty {
                do {
                    opened.append(try self.makeSource(interfaceIndex: nil))
                    Self.log.notice("bound port \(self.port) unbound to any interface")
                } catch {
                    lastError = error.localizedDescription
                    Self.log.error("fallback bind failed: \(error.localizedDescription, privacy: .public)")
                }
            }

            guard !opened.isEmpty else {
                self.report(.failed(lastError ?? "Could not open a socket on port \(self.port)"))
                return
            }

            self.sources = opened
            opened.forEach { $0.resume() }
            self.report(.listening)
        }
    }

    func stop() {
        queue.async { [weak self] in
            guard let self else { return }
            self.sources.forEach { $0.cancel() }
            self.sources.removeAll()
        }
    }

    // MARK: - Socket setup

    private enum SocketError: LocalizedError {
        case create(Int32)
        case bind(Int32)
        case option(String, Int32)

        var errorDescription: String? {
            switch self {
            case .create(let code):
                return "socket() failed (\(String(cString: strerror(code))))"
            case .bind(let code):
                return "bind() failed (\(String(cString: strerror(code))))"
            case .option(let name, let code):
                return "\(name) failed (\(String(cString: strerror(code))))"
            }
        }
    }

    private func makeSource(interfaceIndex: UInt32?) throws -> DispatchSourceRead {
        let fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { throw SocketError.create(errno) }

        var success = false
        defer { if !success { close(fd) } }

        func setOption(_ level: Int32, _ option: Int32, _ name: String, _ value: UInt32) throws {
            var value = value
            let result = setsockopt(fd, level, option, &value,
                                    socklen_t(MemoryLayout<UInt32>.size))
            guard result == 0 else { throw SocketError.option(name, errno) }
        }

        // SO_REUSEPORT is the important one: it lets us share port 4000 with
        // other apps on the same phone, so Sky Sentry and SkyDemon can both
        // listen to the same SkyEcho at once.
        try setOption(SOL_SOCKET, SO_REUSEADDR, "SO_REUSEADDR", 1)
        try setOption(SOL_SOCKET, SO_REUSEPORT, "SO_REUSEPORT", 1)
        try setOption(SOL_SOCKET, SO_BROADCAST, "SO_BROADCAST", 1)

        // Bind to the interface by index rather than by address: the address can
        // change underneath us when the phone rejoins a network, the index does not.
        if let interfaceIndex {
            try setOption(IPPROTO_IP, IP_BOUND_IF, "IP_BOUND_IF", interfaceIndex)
        }

        // Non-blocking, so draining the socket cannot stall the queue.
        guard fcntl(fd, F_SETFL, O_NONBLOCK) != -1 else {
            throw SocketError.option("O_NONBLOCK", errno)
        }

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = INADDR_ANY

        let bound = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { generic in
                Darwin.bind(fd, generic, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else { throw SocketError.bind(errno) }

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in self?.drain(fd: fd) }
        source.setCancelHandler { close(fd) }

        success = true
        return source
    }

    /// Reads every datagram currently queued on the socket.
    private func drain(fd: Int32) {
        while true {
            let received = buffer.withUnsafeMutableBytes { raw -> Int in
                guard let base = raw.baseAddress else { return -1 }
                return recv(fd, base, raw.count, 0)
            }

            if received > 0 {
                Self.log.debug("received \(received) bytes")
                ingest(Data(buffer[0..<received]))
            } else {
                // EAGAIN / EWOULDBLOCK simply means we have drained it.
                break
            }
        }
    }

    // MARK: - Interfaces

    /// IPv4 interfaces that are up and capable of broadcast, excluding loopback.
    private static func broadcastInterfaces() -> [(name: String, index: UInt32)] {
        var addresses: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addresses) == 0, let first = addresses else { return [] }
        defer { freeifaddrs(addresses) }

        var found: [(name: String, index: UInt32)] = []

        for pointer in sequence(first: first, next: { $0.pointee.ifa_next }) {
            guard let address = pointer.pointee.ifa_addr,
                  address.pointee.sa_family == sa_family_t(AF_INET) else { continue }

            let flags = Int32(pointer.pointee.ifa_flags)
            guard flags & IFF_UP != 0,
                  flags & IFF_RUNNING != 0,
                  flags & IFF_LOOPBACK == 0,
                  flags & IFF_BROADCAST != 0 else { continue }

            let name = String(cString: pointer.pointee.ifa_name)
            // "en" covers WiFi, "bridge" covers personal hotspot. Cellular
            // (pdp_ip*) is excluded: a SkyEcho will never be on the far end of it.
            guard name.hasPrefix("en") || name.hasPrefix("bridge") else { continue }

            let index = if_nametoindex(name)
            guard index != 0, !found.contains(where: { $0.index == index }) else { continue }
            found.append((name, index))
        }
        return found
    }

    // MARK: - Decoding

    /// Decodes a datagram. Exposed so the simulator can push synthetic packets
    /// through exactly the same path as live hardware.
    func ingest(_ data: Data) {
        onRawData?(data)

        let frames = GDL90.extractFrames(from: data)
        guard !frames.isEmpty else { return }

        let messages = frames.compactMap { GDL90.decode(frameBody: $0) }
        guard !messages.isEmpty else { return }

        DispatchQueue.main.async {
            self.onStateChange?(.receiving)
            messages.forEach { self.onMessage?($0) }
        }
    }

    private func report(_ state: State) {
        DispatchQueue.main.async { self.onStateChange?(state) }
    }
}
