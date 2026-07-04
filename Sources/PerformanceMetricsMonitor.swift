import Foundation
import UIKit
import QuartzCore
import Network
import Darwin

struct PerformanceMetricsSnapshot {
    let latencyMs: Double?
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let refreshRate: Double

    enum LatencyLevel {
        case unknown
        case good
        case warning
        case bad
    }

    var displayLine: String {
        "延迟 \(Self.formatLatency(latencyMs))  下行 \(Self.formatBytes(downloadBytesPerSecond))  上行 \(Self.formatBytes(uploadBytesPerSecond))  \(Self.formatRefreshRate(refreshRate))"
    }

    var compactLine: String {
        "延迟 \(Self.formatLatency(latencyMs))  ↓\(Self.formatBytes(downloadBytesPerSecond))  ↑\(Self.formatBytes(uploadBytesPerSecond))  \(Self.formatRefreshRate(refreshRate))"
    }

    var latencyText: String {
        Self.formatLatency(latencyMs)
    }

    var uploadText: String {
        Self.formatBytes(uploadBytesPerSecond)
    }

    var downloadText: String {
        Self.formatBytes(downloadBytesPerSecond)
    }

    var refreshRateText: String {
        Self.formatRefreshRate(refreshRate)
    }

    var latencyLevel: LatencyLevel {
        guard let latencyMs else { return .unknown }
        if latencyMs >= 100 { return .bad }
        if latencyMs >= 50 { return .warning }
        return .good
    }

    private static func formatLatency(_ value: Double?) -> String {
        guard let value else { return "-- ms" }
        return String(format: "%.0f ms", max(0, value))
    }

    private static func formatBytes(_ value: Double) -> String {
        let bytes = max(0, value)
        if bytes >= 1024 * 1024 {
            return String(format: "%.1f MB/s", bytes / 1024 / 1024)
        }
        if bytes >= 1024 {
            return String(format: "%.0f KB/s", bytes / 1024)
        }
        return String(format: "%.0f B/s", bytes)
    }

    private static func formatRefreshRate(_ value: Double) -> String {
        guard value > 0 else { return "-- Hz" }

        if (57...63).contains(value) {
            return "60 Hz"
        }
        if (115...125).contains(value) {
            return "120 Hz"
        }

        return String(format: "%.0f Hz", value)
    }
}

final class PerformanceMetricsMonitor: NSObject {
    static let shared = PerformanceMetricsMonitor()

    private struct NetworkCounters {
        let received: UInt64
        let sent: UInt64
    }

    private var timer: Timer?
    private var latencyTimer: Timer?
    private var latencyRequestInFlight = false
    private var latencyConnection: NWConnection?
    private var latencyProbeWarmed = false
    private var latencySamples: [Double] = []
    private var latencySource: TimeSource?
    private var lastCounters: NetworkCounters?
    private var lastCounterDate: Date?
    private var lastFrameSampleTime: CFTimeInterval = 0
    private var frameIntervals: [CFTimeInterval] = []
    private let frameSampleWindow: CFTimeInterval = 0.25
    private let maxLatencySamples = 5
    private let maxBytesPerSecond: Double = 1024 * 1024 * 1024

    private(set) var snapshot = PerformanceMetricsSnapshot(
        latencyMs: nil,
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        refreshRate: Double(max(30, UIScreen.main.maximumFramesPerSecond))
    )

    private override init() {
        super.init()
    }

    func start() {
        guard timer == nil else { return }

        lastCounters = Self.readNetworkCounters()
        lastCounterDate = Date()
        let timer = Timer(
            timeInterval: 1,
            target: self,
            selector: #selector(sampleNetworkSpeed),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let latencyTimer = Timer(
            timeInterval: 2,
            target: self,
            selector: #selector(sampleLatency),
            userInfo: nil,
            repeats: true
        )
        RunLoop.main.add(latencyTimer, forMode: .common)
        self.latencyTimer = latencyTimer
        sampleLatency()
    }

    func updateLatency(ms: Double?) {
        snapshot = PerformanceMetricsSnapshot(
            latencyMs: ms,
            downloadBytesPerSecond: snapshot.downloadBytesPerSecond,
            uploadBytesPerSecond: snapshot.uploadBytesPerSecond,
            refreshRate: snapshot.refreshRate
        )
    }

    func resetLatencySamples(for source: TimeSource) {
        latencySource = source
        latencyProbeWarmed = source == .local
        latencySamples.removeAll()
        updateLatency(ms: source == .local ? 0 : nil)
    }

    static var maximumSupportedFrameRate: Int {
        max(30, UIScreen.main.maximumFramesPerSecond)
    }

    func recordRenderedFrame(at timestamp: CFTimeInterval) {
        if lastFrameSampleTime == 0 {
            lastFrameSampleTime = timestamp
            return
        }

        let interval = timestamp - lastFrameSampleTime
        lastFrameSampleTime = timestamp
        recordRefreshInterval(interval)
    }

    func recordDisplayRefresh(timestamp: CFTimeInterval, targetTimestamp: CFTimeInterval) {
        recordRefreshInterval(targetTimestamp - timestamp)
    }

    private func recordRefreshInterval(_ interval: CFTimeInterval) {
        guard interval > 0, interval < 1 else { return }

        frameIntervals.append(interval)
        var total = frameIntervals.reduce(0, +)
        while total > frameSampleWindow, frameIntervals.count > 1 {
            total -= frameIntervals.removeFirst()
        }

        guard total > 0 else { return }
        let measured = Double(frameIntervals.count) / total

        snapshot = PerformanceMetricsSnapshot(
            latencyMs: snapshot.latencyMs,
            downloadBytesPerSecond: snapshot.downloadBytesPerSecond,
            uploadBytesPerSecond: snapshot.uploadBytesPerSecond,
            refreshRate: measured
        )
    }

    @objc private func sampleNetworkSpeed() {
        guard let counters = Self.readNetworkCounters() else { return }
        let now = Date()
        defer {
            lastCounters = counters
            lastCounterDate = now
        }

        guard let previous = lastCounters,
              let previousDate = lastCounterDate else {
            return
        }

        let interval = now.timeIntervalSince(previousDate)
        guard interval > 0 else { return }

        let receivedDelta = counters.received >= previous.received ? counters.received - previous.received : 0
        let sentDelta = counters.sent >= previous.sent ? counters.sent - previous.sent : 0
        let downloadBytesPerSecond = Double(receivedDelta) / interval
        let uploadBytesPerSecond = Double(sentDelta) / interval

        guard downloadBytesPerSecond <= maxBytesPerSecond,
              uploadBytesPerSecond <= maxBytesPerSecond else {
            return
        }

        snapshot = PerformanceMetricsSnapshot(
            latencyMs: snapshot.latencyMs,
            downloadBytesPerSecond: downloadBytesPerSecond,
            uploadBytesPerSecond: uploadBytesPerSecond,
            refreshRate: snapshot.refreshRate
        )
    }

    private static func readNetworkCounters() -> NetworkCounters? {
        var interfaces: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&interfaces) == 0, let first = interfaces else { return nil }
        defer { freeifaddrs(interfaces) }

        var received: UInt64 = 0
        var sent: UInt64 = 0
        var pointer: UnsafeMutablePointer<ifaddrs>? = first

        while let current = pointer {
            let interface = current.pointee
            let flags = Int32(interface.ifa_flags)
            let isUp = (flags & IFF_UP) == IFF_UP
            let isLoopback = (flags & IFF_LOOPBACK) == IFF_LOOPBACK

            if isUp,
               !isLoopback,
               let address = interface.ifa_addr,
               Int32(address.pointee.sa_family) == AF_LINK,
               let data = interface.ifa_data {
                let networkData = data.assumingMemoryBound(to: if_data.self).pointee
                received += UInt64(networkData.ifi_ibytes)
                sent += UInt64(networkData.ifi_obytes)
            }

            pointer = interface.ifa_next
        }

        return NetworkCounters(received: received, sent: sent)
    }

    @objc private func sampleLatency() {
        guard !latencyRequestInFlight else { return }
        let source = StopwatchEngine.shared.source
        if latencySource != source {
            resetLatencySamples(for: source)
        }

        guard let endpoint = Self.latencyProbeEndpoint(for: source) else {
            updateLatency(ms: 0)
            return
        }

        latencyRequestInFlight = true
        let startedAt = CACurrentMediaTime()

        let connection = NWConnection(
            host: NWEndpoint.Host(endpoint.host),
            port: NWEndpoint.Port(rawValue: endpoint.port) ?? 443,
            using: .tcp
        )
        latencyConnection = connection

        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .ready:
                let latencyMs = (CACurrentMediaTime() - startedAt) * 1000
                self?.latencyConnection?.cancel()
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.latencyRequestInFlight = false
                    self.latencyConnection = nil
                    guard self.latencySource == source else { return }
                    self.recordLatencySample(latencyMs)
                }
            case .failed, .cancelled:
                DispatchQueue.main.async {
                    guard let self else { return }
                    self.latencyRequestInFlight = false
                    self.latencyConnection = nil
                }
            default:
                break
            }
        }

        connection.start(queue: .global(qos: .utility))
    }

    private func recordLatencySample(_ latencyMs: Double) {
        if !latencyProbeWarmed {
            latencyProbeWarmed = true
            return
        }

        latencySamples.append(latencyMs)
        if latencySamples.count > maxLatencySamples {
            latencySamples.removeFirst(latencySamples.count - maxLatencySamples)
        }

        let average = latencySamples.reduce(0, +) / Double(latencySamples.count)
        updateLatency(ms: average)
    }

    private static func latencyProbeEndpoint(for source: TimeSource) -> (host: String, port: UInt16)? {
        switch source {
        case .local:
            return nil
        case .taobao:
            return ("www.taobao.com", 443)
        case .qqMusic:
            return ("c.y.qq.com", 443)
        }
    }
}
