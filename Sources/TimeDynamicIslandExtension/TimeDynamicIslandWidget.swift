import ActivityKit
import SwiftUI
import WidgetKit

@main
struct TimeDynamicIslandExtensionBundle: WidgetBundle {
    var body: some Widget {
        TimeLiveActivityWidget()
    }
}

struct TimeLiveActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: TimeLiveActivityAttributes.self) { context in
            LockScreenTimeView(state: context.state)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    Label("时间", systemImage: "clock")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white)
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.sourceName)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.82))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.center) {
                    IslandClockText(
                        clockStartDate: context.state.clockStartDate,
                        timeText: context.state.timeText,
                        font: .system(size: 21, weight: .semibold, design: .monospaced),
                        width: 116,
                        alignment: .center
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text("来自 \(context.state.sourceName) 校时")
                        .font(.caption2)
                        .foregroundStyle(.white.opacity(0.7))
                }
            } compactLeading: {
                Image(systemName: "clock")
                    .foregroundStyle(.green)
            } compactTrailing: {
                IslandClockText(
                    clockStartDate: context.state.clockStartDate,
                    timeText: context.state.timeText,
                    font: .system(size: 12, weight: .semibold, design: .monospaced),
                    width: 76,
                    alignment: .trailing
                )
            } minimal: {
                Image(systemName: "clock")
                    .foregroundStyle(.green)
            }
            .keylineTint(.green)
        }
    }
}

private struct LockScreenTimeView: View {
    let state: TimeLiveActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "clock.fill")
                .font(.title2)
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("当前时间")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.68))

                IslandClockText(
                    clockStartDate: state.clockStartDate,
                    timeText: state.timeText,
                    font: .system(size: 32, weight: .semibold, design: .monospaced),
                    width: 178,
                    alignment: .leading
                )
            }

            Spacer(minLength: 8)

            Text(state.sourceName)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white)
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.white.opacity(0.16), in: Capsule())
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.green)
    }
}

private struct IslandClockText: View {
    let clockStartDate: Date
    let timeText: String
    let font: Font
    let width: CGFloat
    let alignment: Alignment

    var body: some View {
        TimelineView(.periodic(from: clockStartDate, by: 0.1)) { timeline in
            clockText(at: timeline.date)
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.68)
                .frame(width: width, alignment: alignment)
        }
    }

    private func clockText(at date: Date) -> Text {
        let value = displayParts(at: date)
        return Text(value.body).foregroundColor(.white)
        + Text(".").foregroundColor(.white)
        + Text(value.tenth).foregroundColor(Color(red: 1.0, green: 0.25, blue: 0.18))
    }

    private func displayParts(at date: Date) -> (body: String, tenth: String) {
        let elapsed = date.timeIntervalSince(clockStartDate)
        let totalTenths = Int((elapsed * 10).rounded(.down))
        let dayTenths = ((totalTenths % 864000) + 864000) % 864000
        let hour = dayTenths / 36000
        let minute = (dayTenths / 600) % 60
        let second = (dayTenths / 10) % 60
        let tenth = dayTenths % 10
        return (String(format: "%d:%02d:%02d", hour, minute, second), String(tenth))
    }
}
