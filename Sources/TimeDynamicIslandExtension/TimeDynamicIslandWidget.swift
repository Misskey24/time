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
                    TimerClockText(
                        clockStartDate: context.state.clockStartDate,
                        font: .system(size: 28, weight: .semibold, design: .monospaced),
                        color: .white,
                        minWidth: 138
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
                TimerClockText(
                    clockStartDate: context.state.clockStartDate,
                    font: .system(size: 11, weight: .semibold, design: .monospaced),
                    color: .white,
                    minWidth: 52
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

                TimerClockText(
                    clockStartDate: state.clockStartDate,
                    font: .system(size: 34, weight: .semibold, design: .monospaced),
                    color: .white,
                    minWidth: 168
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

private struct TimerClockText: View {
    let clockStartDate: Date
    let font: Font
    let color: Color
    let minWidth: CGFloat

    var body: some View {
        Text(
            timerInterval: clockStartDate...clockStartDate.addingTimeInterval(24 * 60 * 60),
            countsDown: false,
            showsHours: true
        )
        .font(font)
        .foregroundStyle(color)
        .monospacedDigit()
        .frame(minWidth: minWidth, alignment: .leading)
        .lineLimit(1)
        .minimumScaleFactor(0.45)
    }
}
