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
                    StaticClockText(
                        timeText: context.state.timeText,
                        showsSeconds: true,
                        font: .system(size: 24, weight: .semibold, design: .monospaced),
                        minWidth: 118,
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
                StaticClockText(
                    timeText: context.state.timeText,
                    showsSeconds: false,
                    font: .system(size: 13, weight: .semibold, design: .monospaced),
                    minWidth: 46,
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

                StaticClockText(
                    timeText: state.timeText,
                    showsSeconds: true,
                    font: .system(size: 34, weight: .semibold, design: .monospaced),
                    minWidth: 158,
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

private struct StaticClockText: View {
    let timeText: String
    let showsSeconds: Bool
    let font: Font
    let minWidth: CGFloat
    let alignment: Alignment

    var body: some View {
        Text(displayText)
            .font(font)
            .foregroundStyle(.white)
            .monospacedDigit()
            .fixedSize(horizontal: true, vertical: false)
            .frame(minWidth: minWidth, alignment: alignment)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var displayText: String {
        let maxLength = showsSeconds ? 8 : 5
        return String(timeText.prefix(maxLength))
    }
}
