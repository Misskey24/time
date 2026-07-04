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
                }

                DynamicIslandExpandedRegion(.trailing) {
                    Text(context.state.sourceName)
                        .font(.caption.weight(.semibold))
                        .lineLimit(1)
                }

                DynamicIslandExpandedRegion(.center) {
                    LiveClockText(
                        offsetSeconds: context.state.offsetSeconds,
                        showsSeconds: true,
                        font: .system(size: 28, weight: .semibold, design: .monospaced)
                    )
                }

                DynamicIslandExpandedRegion(.bottom) {
                    Text("来自 \(context.state.sourceName) 校时")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } compactLeading: {
                Image(systemName: "clock")
                    .foregroundStyle(.green)
            } compactTrailing: {
                LiveClockText(
                    offsetSeconds: context.state.offsetSeconds,
                    showsSeconds: false,
                    font: .system(size: 13, weight: .semibold, design: .monospaced)
                )
            } minimal: {
                Image(systemName: "clock")
                    .foregroundStyle(.green)
            }
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
                    .foregroundStyle(.secondary)

                LiveClockText(
                    offsetSeconds: state.offsetSeconds,
                    showsSeconds: true,
                    font: .system(size: 32, weight: .semibold, design: .monospaced)
                )
            }

            Spacer(minLength: 8)

            Text(state.sourceName)
                .font(.caption.weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(.thinMaterial, in: Capsule())
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .activityBackgroundTint(.black)
        .activitySystemActionForegroundColor(.green)
    }
}

private struct LiveClockText: View {
    let offsetSeconds: TimeInterval
    let showsSeconds: Bool
    let font: Font

    var body: some View {
        TimelineView(.periodic(from: Date(), by: 1)) { timeline in
            Text(Self.format(timeline.date.addingTimeInterval(offsetSeconds), showsSeconds: showsSeconds))
                .font(font)
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
    }

    private static func format(_ date: Date, showsSeconds: Bool) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        let components = calendar.dateComponents([.hour, .minute, .second], from: date)
        if showsSeconds {
            return String(format: "%02d:%02d:%02d", components.hour ?? 0, components.minute ?? 0, components.second ?? 0)
        }
        return String(format: "%02d:%02d", components.hour ?? 0, components.minute ?? 0)
    }
}
