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
                        timeText: context.state.timeText,
                        font: .system(size: 24, weight: .semibold, design: .monospaced),
                        minWidth: 122,
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
                    timeText: context.state.timeText,
                    font: .system(size: 15, weight: .semibold, design: .monospaced),
                    minWidth: 92,
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
                    timeText: state.timeText,
                    font: .system(size: 34, weight: .semibold, design: .monospaced),
                    minWidth: 178,
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
    let timeText: String
    let font: Font
    let minWidth: CGFloat
    let alignment: Alignment

    var body: some View {
        coloredText
            .font(font)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: minWidth, alignment: alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var coloredText: Text {
        let value = displayParts
        let body = Text(value.body).foregroundColor(.white)
        guard let tenth = value.tenth else { return body }
        return body + Text(tenth).foregroundColor(Color(red: 1.0, green: 0.25, blue: 0.18))
    }

    private var displayParts: (body: String, tenth: String?) {
        let components = timeText.split(separator: ":", omittingEmptySubsequences: false).map(String.init)
        guard components.count >= 3 else { return (timeText, nil) }

        let hour = String(Int(components[0]) ?? 0)
        let minute = components[1]
        let second = components[2]
        guard components.count >= 4, let tenth = components[3].first else {
            return ("\(hour):\(minute):\(second)", nil)
        }
        return ("\(hour):\(minute):\(second).", String(tenth))
    }
}
