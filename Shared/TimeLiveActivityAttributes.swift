import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct TimeLiveActivityAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var sourceName: String
        var offsetSeconds: TimeInterval
        var updatedAt: Date
    }

    var title: String
}
