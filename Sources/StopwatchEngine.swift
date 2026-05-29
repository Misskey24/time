import Foundation

enum TimeSource: String, CaseIterable {
    case local   = "本地"
    case taobao  = "淘宝"
    case qqMusic = "QQ音乐"
}

final class StopwatchEngine {
    static let shared = StopwatchEngine()

    private(set) var source: TimeSource {
        didSet { UserDefaults.standard.set(source.rawValue, forKey: "timeSource") }
    }
    private var offsetMs: Double = 0
    private(set) var lastSyncedAt: Date?

    private init() {
        if let raw = UserDefaults.standard.string(forKey: "timeSource"),
           let s = TimeSource(rawValue: raw) {
            source = s
        } else {
            source = .local
        }
    }

    func setSource(_ s: TimeSource, completion: ((Bool) -> Void)? = nil) {
        source = s
        if s == .local {
            offsetMs = 0
            lastSyncedAt = Date()
            completion?(true)
            return
        }
        TimeSourceManager.fetchServerTimeMs(source: s) { [weak self] serverMs in
            guard let self = self else { return }
            if let serverMs = serverMs {
                let localMs = Date().timeIntervalSince1970 * 1000
                self.offsetMs = serverMs - localMs
                self.lastSyncedAt = Date()
                completion?(true)
            } else {
                completion?(false)
            }
        }
    }

    func resync(completion: ((Bool) -> Void)? = nil) {
        setSource(source, completion: completion)
    }

    func currentTimeMs() -> Double {
        return Date().timeIntervalSince1970 * 1000 + offsetMs
    }

    func formattedTime() -> String {
        let ms = currentTimeMs()
        let date = Date(timeIntervalSince1970: ms / 1000.0)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let comps = calendar.dateComponents([.hour, .minute, .second], from: date)
        let tenths = Int(ms.truncatingRemainder(dividingBy: 1000)) / 100
        return String(format: "%02d:%02d:%02d:%d",
                      comps.hour ?? 0,
                      comps.minute ?? 0,
                      comps.second ?? 0,
                      tenths)
    }
}
