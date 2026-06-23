import SwiftUI

/// Small rounded info chip (gear, battery, power, connection).
struct InfoPill: View {
    var systemImage: String
    var text: String
    var tint: Color = .white

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .font(.system(size: 13, weight: .semibold))
            Text(text)
                .font(.system(size: 15, weight: .semibold, design: .rounded))
                .monospacedDigit()
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }
}

/// The P R N D gear indicator, Tesla-style with the active gear highlighted.
struct GearIndicator: View {
    var shiftState: String?

    private let gears = ["P", "R", "N", "D"]

    var body: some View {
        HStack(spacing: 10) {
            ForEach(gears, id: \.self) { gear in
                Text(gear)
                    .font(.system(size: 17, weight: .bold, design: .rounded))
                    .foregroundStyle(isActive(gear) ? .white : .white.opacity(0.3))
                    .scaleEffect(isActive(gear) ? 1.15 : 1.0)
                    .animation(.snappy, value: shiftState)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial, in: Capsule())
    }

    private func isActive(_ gear: String) -> Bool {
        (shiftState ?? "P").uppercased() == gear
    }
}

/// A floating dark-glass circular gauge, like the new Tesla / Apple driver
/// display. A thin colored ring sweeps ~270° to show `fraction`, with arbitrary
/// content in the middle.
struct ClusterGauge<Center: View>: View {
    var fraction: Double
    var ringColors: [Color]
    var size: CGFloat = 200
    @ViewBuilder var center: () -> Center

    private var clamped: Double { min(1, max(0, fraction)) }

    var body: some View {
        ZStack {
            // Dark translucent glass puck.
            Circle().fill(.ultraThinMaterial)
            Circle().fill(Color.black.opacity(0.32))
            Circle().stroke(Color.white.opacity(0.10), lineWidth: 1)

            // Ring track.
            Circle()
                .trim(from: 0.13, to: 0.87)
                .stroke(Color.white.opacity(0.10),
                        style: .init(lineWidth: size * 0.045, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Ring progress.
            Circle()
                .trim(from: 0.13, to: 0.13 + (0.74 * clamped))
                .stroke(
                    LinearGradient(colors: ringColors, startPoint: .leading, endPoint: .trailing),
                    style: .init(lineWidth: size * 0.045, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.4), value: clamped)

            center()
        }
        .frame(width: size, height: size)
        .shadow(color: .black.opacity(0.35), radius: 18, y: 8)
    }
}
