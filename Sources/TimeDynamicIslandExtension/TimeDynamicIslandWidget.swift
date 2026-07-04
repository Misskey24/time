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
                    ColoredTimeText(
                        timeText: context.state.timeText,
                        font: .system(size: 25, weight: .semibold, design: .monospaced),
                        minWidth: 142,
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
                ColoredTimeText(
                    timeText: context.state.timeText,
                    font: .system(size: 10, weight: .semibold, design: .monospaced),
                    minWidth: 62,
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

                ColoredTimeText(
                    timeText: state.timeText,
                    font: .system(size: 32, weight: .semibold, design: .monospaced),
                    minWidth: 186,
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

private struct ColoredTimeText: View {
    let timeText: String
    let font: Font
    let minWidth: CGFloat
    let alignment: Alignment

    var body: some View {
        coloredText
            .font(font)
            .monospacedDigit()
            .frame(minWidth: minWidth, alignment: alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.35)
    }

    private var coloredText: Text {
        guard let last = timeText.last else { return Text("") }
        let body = String(timeText.dropLast())
        return Text(body).foregroundColor(.white) + Text(String(last)).foregroundColor(.red)
    }
}
