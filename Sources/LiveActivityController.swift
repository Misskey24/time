import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    var onStatus: ((String) -> Void)?

    private let enabledKey = "showDynamicIslandTime"

    private init() {}

    var isEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: enabledKey) }
        set { UserDefaults.standard.set(newValue, forKey: enabledKey) }
    }

    var isSupported: Bool {
        guard #available(iOS 16.1, *) else { return false }
        return ActivityAuthorizationInfo().areActivitiesEnabled
    }

    func restoreIfNeeded() {
        guard isEnabled else { return }
        startOrRefresh()
    }

    func setEnabled(_ enabled: Bool) {
        isEnabled = enabled
        enabled ? startOrRefresh() : end()
    }

    func refreshIfEnabled() {
        guard isEnabled else { return }
        startOrRefresh()
    }

    func startOrRefresh() {
        guard #available(iOS 16.1, *) else {
            onStatus?("??????? iOS 16.1 ??????")
            isEnabled = false
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            onStatus?("??????????????????????")
            isEnabled = false
            return
        }

        Task { @MainActor in
            await startOrRefreshActivity()
        }
    }

    func end() {
        guard #available(iOS 16.1, *) else { return }

        Task { @MainActor in
            await endActivities()
        }
    }

    @available(iOS 16.1, *)
    private func endActivities() async {
        let state = makeContentState()
        for activity in Activity<TimeLiveActivityAttributes>.activities {
            await activity.end(using: state, dismissalPolicy: .immediate)
        }
        onStatus?("?????????")
    }

    @available(iOS 16.1, *)
    private func startOrRefreshActivity() async {
        let state = makeContentState()

        if let activity = Activity<TimeLiveActivityAttributes>.activities.first {
            await activity.update(using: state)
            onStatus?("?????????")
            return
        }

        do {
            _ = try Activity<TimeLiveActivityAttributes>.request(
                attributes: TimeLiveActivityAttributes(title: "??"),
                contentState: state,
                pushType: nil
            )
            onStatus?("?????????????????????")
        } catch {
            onStatus?("????????\(error.localizedDescription)")
            isEnabled = false
        }
    }

    @available(iOS 16.1, *)
    private func makeContentState() -> TimeLiveActivityAttributes.ContentState {
        TimeLiveActivityAttributes.ContentState(
            sourceName: StopwatchEngine.shared.source.rawValue,
            offsetSeconds: StopwatchEngine.shared.currentOffsetSeconds(),
            updatedAt: Date()
        )
    }
}
