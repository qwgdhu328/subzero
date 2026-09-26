import ActivityKit
import WidgetKit
import SwiftUI

/// UI della Live Activity sull'Isola Dinamica e in schermata di blocco.
@main
struct NewsActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: NewsActivityAttributes.self) { context in
            // MARK: Schermata di blocco
            LockScreenNewsView(state: context.state)
                .activityBackgroundTint(Color.black.opacity(0.35))
                .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                // MARK: Zona espansa (tocco lungo sull'isola)
                DynamicIslandExpandedRegion(.leading) {
                    Text(context.state.emoji)
                        .font(.system(size: 30))
                        .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CineFlash")
                            .font(.system(size: 11, weight: .heavy))
                            .kerning(1.4)
                            .foregroundColor(Color(hex: 0xC93B2F))
                        Text(context.state.headline)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundColor(.white)
                            .lineLimit(2)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if context.state.newCount > 1 {
                        Text("\(context.state.newCount)")
                            .font(.system(size: 20, weight: .heavy, design: .rounded))
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Circle().fill(Color(hex: 0xC93B2F)))
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    HStack {
                        Text(context.state.detail)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(.white.opacity(0.75))
                            .lineLimit(1)
                        Spacer()
                        Text(context.state.updatedAt, style: .relative)
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(.white.opacity(0.5))
                    }
                }
            } compactLeading: {
                // MARK: Isola compatta — sinistra
                Text(context.state.emoji)
                    .font(.system(size: 14))
            } compactTrailing: {
                // MARK: Isola compatta — destra (badge conteggio)
                if context.state.newCount > 1 {
                    Text("\(context.state.newCount)")
                        .font(.system(size: 12, weight: .heavy, design: .rounded))
                        .foregroundColor(.white)
                        .padding(4)
                        .background(Circle().fill(Color(hex: 0xC93B2F)))
                } else {
                    Circle()
                        .fill(Color(hex: 0xC93B2F))
                        .frame(width: 8, height: 8)
                }
            } minimal: {
                // MARK: Isola minimal (quando ci sono più activity)
                Circle()
                    .fill(Color(hex: 0xC93B2F))
                    .frame(width: 8, height: 8)
            }
            .widgetURL(URL(string: "cineflash://news"))
        }
    }
}

/// Vista in schermata di blocco: banda scura con accent rossa.
private struct LockScreenNewsView: View {
    let state: NewsActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: 0xC93B2F))
                Text(state.emoji)
                    .font(.system(size: 22))
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("CINEFLASH")
                    .font(.system(size: 10, weight: .heavy))
                    .kerning(1.6)
                    .foregroundColor(Color(hex: 0xF4F1EA).opacity(0.7))
                Text(state.headline)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundColor(.white)
                    .lineLimit(2)
                Text(state.detail)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(.white.opacity(0.7))
                    .lineLimit(1)
            }
            Spacer()
            if state.newCount > 1 {
                Text("\(state.newCount)")
                    .font(.system(size: 22, weight: .heavy, design: .rounded))
                    .foregroundColor(.white)
            }
        }
        .padding(14)
    }
}

// MARK: - Hex helper per il widget

extension Color {
    init(hexValue: UInt32, opacity: Double = 1) {
        self.init(.sRGB,
                  red: Double((hexValue >> 16) & 0xFF) / 255,
                  green: Double((hexValue >> 8) & 0xFF) / 255,
                  blue: Double(hexValue & 0xFF) / 255,
                  opacity: opacity)
    }
}

/// Trucco per riutilizzare la sintassi Color(hex:) con valore numerico.
private extension Color {
    init(hex: UInt32) {
        self.init(hexValue: hex)
    }
}
