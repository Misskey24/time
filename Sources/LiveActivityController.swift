import ActivityKit
import Foundation

@MainActor
final class LiveActivityController {
    static let shared = LiveActivityController()

    var onStatus: ((String) -> Void)?

    private let enabledKey = "showDynamicIslandTime"
    private var refreshTimer: Timer?

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
            onStatus?("灵动岛时间需要 iOS 16.1 或更高版本。")
            isEnabled = false
            return
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            onStatus?("系统没有允许实时活动，请在设置里开启后再试。")
            isEnabled = false
            return
        }

        Task { @MainActor in
            await startOrRefreshActivity()
        }
        startRefreshTimer()
    }

    func end() {
        stopRefreshTimer()
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
        onStatus?("灵动岛时间已关闭。")
    }

    @available(iOS 16.1, *)
    private func startOrRefreshActivity() async {
        let state = makeContentState()

        if let activity = Activity<TimeLiveActivityAttributes>.activities.first {
            await activity.update(using: state)
            onStatus?("灵动岛时间已更新。")
            return
        }

        do {
            _ = try Activity<TimeLiveActivityAttributes>.request(
                attributes: TimeLiveActivityAttributes(title: "时间"),
                contentState: state,
                pushType: nil
            )
            onStatus?("灵动岛时间已开启，锁屏或进入后台后可查看。")
        } catch {
            onStatus?("灵动岛启动失败：\(error.localizedDescription)")
            isEnabled = false
        }
    }

    @available(iOS 16.1, *)
    private func makeContentState() -> TimeLiveActivityAttributes.ContentState {
        let offsetSeconds = StopwatchEngine.shared.currentOffsetSeconds()
        return TimeLiveActivityAttributes.ContentState(
            sourceName: StopwatchEngine.shared.source.rawValue,
            timeText: StopwatchEngine.shared.formattedClockTime(),
            offsetSeconds: offsetSeconds,
            clockStartDate: Self.clockStartDate(offsetSeconds: offsetSeconds),
            updatedAt: Date()
        )
    }

    private func startRefreshTimer() {
        guard refreshTimer == nil else { return }
        let timer = Timer(timeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isEnabled else { return }
                guard #available(iOS 16.1, *) else { return }
                await self.updateRunningActivity()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
    }

    private func stopRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    @available(iOS 16.1, *)
    private func updateRunningActivity() async {
        guard let activity = Activity<TimeLiveActivityAttributes>.activities.first else { return }
        await activity.update(using: makeContentState())
    }

    private static func clockStartDate(offsetSeconds: TimeInterval) -> Date {
        let adjustedNow = Date().addingTimeInterval(offsetSeconds)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let adjustedStartOfDay = calendar.startOfDay(for: adjustedNow)
        return adjustedStartOfDay.addingTimeInterval(-offsetSeconds)
    }
}
