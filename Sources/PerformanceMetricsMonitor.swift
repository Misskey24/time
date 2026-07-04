import Foundation
import UIKit
import Darwin

struct PerformanceMetricsSnapshot {
    let latencyMs: Double?
    let downloadBytesPerSecond: Double
    let uploadBytesPerSecond: Double
    let refreshRate: Double

    var displayLine: String {
        "延迟 \(Self.formatLatency(latencyMs))  下行 \(Self.formatBytes(downloadBytesPerSecond))  上行 \(Self.formatBytes(uploadBytesPerSecond))  \(Self.formatRefreshRate(refreshRate))"
    }

    var compactLine: String {
        "延迟 \(Self.formatLatency(latencyMs))  ↓\(Self.formatBytes(downloadBytesPerSecond))  ↑\(Self.formatBytes(uploadBytesPerSecond))  \(Self.formatRefreshRate(refreshRate))"
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
    private var displayLink: CADisplayLink?
    private var lastCounters: NetworkCounters?
    private var lastCounterDate: Date?
    private var frameCount = 0
    private var lastFrameSampleTime: CFTimeInterval = 0

    private(set) var snapshot = PerformanceMetricsSnapshot(
        latencyMs: nil,
        downloadBytesPerSecond: 0,
        uploadBytesPerSecond: 0,
        refreshRate: Double(UIScreen.main.maximumFramesPerSecond)
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

        let link = CADisplayLink(target: self, selector: #selector(sampleRefreshRate(_:)))
        if #available(iOS 15.0, *) {
            let maxFPS = Float(Self.maximumSupportedFrameRate)
            link.preferredFrameRateRange = CAFrameRateRange(
                minimum: 10,
                maximum: maxFPS,
                preferred: maxFPS
            )
        }
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func updateLatency(ms: Double?) {
        snapshot = PerformanceMetricsSnapshot(
            latencyMs: ms,
            downloadBytesPerSecond: snapshot.downloadBytesPerSecond,
            uploadBytesPerSecond: snapshot.uploadBytesPerSecond,
            refreshRate: snapshot.refreshRate
        )
    }

    static var maximumSupportedFrameRate: Int {
        max(30, UIScreen.main.maximumFramesPerSecond)
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

        snapshot = PerformanceMetricsSnapshot(
            latencyMs: snapshot.latencyMs,
            downloadBytesPerSecond: Double(receivedDelta) / interval,
            uploadBytesPerSecond: Double(sentDelta) / interval,
            refreshRate: snapshot.refreshRate
        )
    }

    @objc private func sampleRefreshRate(_ link: CADisplayLink) {
        if lastFrameSampleTime == 0 {
            lastFrameSampleTime = link.timestamp
            return
        }

        frameCount += 1
        let elapsed = link.timestamp - lastFrameSampleTime
        guard elapsed >= 1 else { return }

        let measured = Double(frameCount) / elapsed
        frameCount = 0
        lastFrameSampleTime = link.timestamp

        snapshot = PerformanceMetricsSnapshot(
            latencyMs: snapshot.latencyMs,
            downloadBytesPerSecond: snapshot.downloadBytesPerSecond,
            uploadBytesPerSecond: snapshot.uploadBytesPerSecond,
            refreshRate: measured
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
}
