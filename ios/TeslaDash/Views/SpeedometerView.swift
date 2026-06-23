import SwiftUI

/// Tesla-style speed readout: a large number with a small unit, sitting on a
/// subtle arc gauge that fills with speed.
struct SpeedometerView: View {
    var speed: Double
    var unit: String
    var maxSpeed: Double = 90
    var size: CGFloat = 220

    private var fraction: Double { min(1, max(0, speed / maxSpeed)) }

    var body: some View {
        ZStack {
            // Track
            Circle()
                .trim(from: 0.13, to: 0.87)
                .stroke(Color.white.opacity(0.12), style: .init(lineWidth: 10, lineCap: .round))
                .rotationEffect(.degrees(90))

            // Progress
            Circle()
                .trim(from: 0.13, to: 0.13 + (0.74 * fraction))
                .stroke(
                    LinearGradient(
                        colors: [Color(red: 0.20, green: 0.62, blue: 1.0), Color(red: 0.40, green: 0.85, blue: 1.0)],
                        startPoint: .leading, endPoint: .trailing
                    ),
                    style: .init(lineWidth: 10, lineCap: .round)
                )
                .rotationEffect(.degrees(90))
                .animation(.easeOut(duration: 0.4), value: fraction)

            VStack(spacing: -4) {
                Text("\(Int(speed.rounded()))")
                    .font(.system(size: size * 0.436, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .contentTransition(.numericText(value: speed))
                    .animation(.snappy(duration: 0.3), value: Int(speed.rounded()))
                Text(unit)
                    .font(.system(size: size * 0.091, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .frame(width: size, height: size)
    }
}

#Preview {
    ZStack { Color.black; SpeedometerView(speed: 47, unit: "mph") }
}
