import SwiftUI
import CoreLocation

/// The main screen: full-bleed map with the speedometer and vehicle info
/// overlaid, mirroring the Tesla Model Y center display.
struct DashboardView: View {
    @StateObject private var stream = VehicleStream()
    @State private var showSettings = false

    var body: some View {
        GeometryReader { proxy in
            let landscape = proxy.size.width >= proxy.size.height
            let gaugeSize: CGFloat = landscape
                ? min(proxy.size.height * 0.52, 260)
                : min(proxy.size.width * 0.34, 148)

            ZStack {
                Color.black.ignoresSafeArea()

                // Full-bleed wide map spanning the whole background.
                mapPanel
                    .ignoresSafeArea()

                // Side scrims keep the floating panels legible over the map.
                LinearGradient(
                    colors: [.black.opacity(0.7), .black.opacity(0.0),
                             .black.opacity(0.0), .black.opacity(0.55)],
                    startPoint: .leading, endPoint: .trailing
                )
                .ignoresSafeArea()
                .allowsHitTesting(false)

                Group {
                    if landscape {
                        HStack(spacing: 10) {
                            leftPod(gaugeSize: gaugeSize)
                                .frame(width: max(proxy.size.width * 0.27, 240))
                            Spacer(minLength: 0)
                            rightColumn
                                .frame(width: max(proxy.size.width * 0.23, 200))
                        }
                    } else {
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            compactDock(gaugeSize: gaugeSize)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                }
                .padding(10)

                // Floating controls over the cluster.
                VStack {
                    HStack(alignment: .top) {
                        connectionPill
                        Spacer()
                        settingsButton
                    }
                    Spacer()
                }
                .padding(24)
            }
            .ignoresSafeArea(edges: .bottom)
        }
        .onAppear { stream.start() }
        .onDisappear { stream.stop() }
        .sheet(isPresented: $showSettings) {
            SettingsView { newURL in stream.updateURL(newURL) }
        }
    }

    // MARK: - Center map panel

    private var mapPanel: some View {
        MapView(
            coordinate: coordinate,
            heading: stream.state?.heading,
            moving: (stream.state?.primarySpeed ?? 0) > 1
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Compact portrait dock

    /// A single floating glass dock: compact speed gauge on the left, gear +
    /// battery + power stacked beside it, so the live map stays visible behind.
    private func compactDock(gaugeSize: CGFloat) -> some View {
        HStack(spacing: 18) {
            ClusterGauge(
                fraction: (stream.state?.primarySpeed ?? 0) / 160,
                ringColors: [Color(red: 0.20, green: 0.62, blue: 1.0),
                             Color(red: 0.45, green: 0.85, blue: 1.0)],
                size: gaugeSize
            ) {
                VStack(spacing: 0) {
                    Text(driveMode)
                        .font(.system(size: gaugeSize * 0.085, weight: .bold, design: .rounded))
                        .tracking(1.5)
                        .foregroundStyle(Color(red: 0.42, green: 0.76, blue: 1.0))

                    Text("\(Int((stream.state?.primarySpeed ?? 0).rounded()))")
                        .font(.system(size: gaugeSize * 0.40, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: stream.state?.primarySpeed ?? 0))
                        .animation(.snappy(duration: 0.3),
                                   value: Int((stream.state?.primarySpeed ?? 0).rounded()))

                    Text(stream.state?.unitLabel ?? "km/h")
                        .font(.system(size: gaugeSize * 0.085, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }

            VStack(alignment: .leading, spacing: 14) {
                prndRow(size: gaugeSize * 1.15)
                compactMetric(icon: batteryIcon(stream.state?.batteryLevel ?? 100),
                              value: batteryText, title: "Battery", tint: batteryTint)
                compactMetric(icon: powerIcon, value: powerText, title: powerTitle, tint: powerTint)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity)
        .glassCard()
    }

    private func compactMetric(icon: String, value: String, title: String, tint: Color) -> some View {
        HStack(spacing: 11) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)
            VStack(alignment: .leading, spacing: 0) {
                Text(value)
                    .font(.system(size: 21, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Text(title)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
        }
    }

    // MARK: - Left speed pod

    /// The driver pod: drive mode, big speed, the P R N D selector and a
    /// range-style battery readout, all inside one dark panel.
    private func leftPod(gaugeSize: CGFloat) -> some View {
        VStack(spacing: 18) {
            ClusterGauge(
                fraction: (stream.state?.primarySpeed ?? 0) / 160,
                ringColors: [Color(red: 0.20, green: 0.62, blue: 1.0),
                             Color(red: 0.45, green: 0.85, blue: 1.0)],
                size: gaugeSize
            ) {
                VStack(spacing: 2) {
                    Text(driveMode)
                        .font(.system(size: gaugeSize * 0.072, weight: .bold, design: .rounded))
                        .tracking(2)
                        .foregroundStyle(Color(red: 0.42, green: 0.76, blue: 1.0))

                    Text("\(Int((stream.state?.primarySpeed ?? 0).rounded()))")
                        .font(.system(size: gaugeSize * 0.30, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.white)
                        .contentTransition(.numericText(value: stream.state?.primarySpeed ?? 0))
                        .animation(.snappy(duration: 0.3),
                                   value: Int((stream.state?.primarySpeed ?? 0).rounded()))

                    Text(stream.state?.unitLabel ?? "km/h")
                        .font(.system(size: gaugeSize * 0.072, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.5))

                    prndRow(size: gaugeSize)
                        .padding(.top, 6)
                }
            }

            rangeReadout

            if let status = stream.lastStatus {
                Text(status)
                    .font(.system(size: 11, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.4))
                    .lineLimit(1)
                    .padding(.horizontal, 8)
            }
        }
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .glassCard()
    }

    private func prndRow(size: CGFloat) -> some View {
        HStack(spacing: size * 0.055) {
            ForEach(["P", "R", "N", "D"], id: \.self) { gear in
                Text(gear)
                    .font(.system(size: size * 0.085, weight: .bold, design: .rounded))
                    .foregroundStyle(isGear(gear) ? .white : .white.opacity(0.26))
                    .animation(.snappy, value: stream.state?.shiftState)
            }
        }
    }

    /// Range-style readout at the foot of the pod (battery %, the only
    /// energy figure the Fleet API gives us).
    private var rangeReadout: some View {
        HStack(spacing: 8) {
            Image(systemName: "car.fill")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(Color(red: 0.45, green: 0.85, blue: 1.0))
            Text(batteryText)
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
        }
    }

    // MARK: - Right metric cards

    private var rightColumn: some View {
        VStack(spacing: 10) {
            metricCard(
                value: batteryText,
                title: "Battery",
                icon: batteryIcon(stream.state?.batteryLevel ?? 100),
                tint: batteryTint
            )
            metricCard(
                value: powerText,
                title: powerTitle,
                icon: powerIcon,
                tint: powerTint
            )
        }
    }

    private func metricCard(value: String, title: String, icon: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(value)
                    .font(.system(size: 34, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.white)
                    .minimumScaleFactor(0.6)
                    .lineLimit(1)
                Spacer()
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
            }
            Text(title)
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.5))
        }
        .padding(22)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .glassCard()
    }

    // MARK: - Derived display values

    private var driveMode: String {
        switch (stream.state?.shiftState ?? "P").uppercased().first {
        case "D": return "DRIVE"
        case "R": return "REVERSE"
        case "N": return "NEUTRAL"
        default:  return "PARK"
        }
    }

    private func isGear(_ gear: String) -> Bool {
        (stream.state?.shiftState ?? "P").uppercased().hasPrefix(gear)
    }

    private var batteryText: String {
        stream.state?.batteryLevel.map { "\($0)%" } ?? "—"
    }

    private var batteryTint: Color {
        (stream.state?.batteryLevel ?? 100) <= 15 ? .red : Color(red: 0.45, green: 0.85, blue: 1.0)
    }

    private var powerTitle: String { (stream.state?.power ?? 0) < 0 ? "Regen" : "Power" }

    private var powerText: String {
        guard let power = stream.state?.power else { return "—" }
        return "\(Int(power.rounded())) kW"
    }

    private var powerIcon: String { (stream.state?.power ?? 0) < 0 ? "leaf.fill" : "bolt.fill" }

    private var powerTint: Color {
        (stream.state?.power ?? 0) < 0 ? .green : Color(red: 0.45, green: 0.85, blue: 1.0)
    }

    private var coordinate: CLLocationCoordinate2D? {
        guard let lat = stream.state?.lat, let lng = stream.state?.lng else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var settingsButton: some View {
        Button { showSettings = true } label: {
            Image(systemName: "gearshape.fill")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)
                .padding(10)
                .background(.ultraThinMaterial, in: Circle())
        }
    }

    private var connectionPill: some View {
        switch stream.connection {
        case .connecting:
            return AnyView(InfoPill(systemImage: "antenna.radiowaves.left.and.right", text: "Connecting", tint: .yellow))
        case .connected:
            let live = (stream.state?.online ?? true)
            return AnyView(InfoPill(systemImage: live ? "dot.radiowaves.up.forward" : "moon.zzz.fill",
                                    text: live ? "Live" : "Asleep",
                                    tint: live ? .green : .white.opacity(0.7)))
        case .disconnected:
            return AnyView(InfoPill(systemImage: "wifi.slash", text: "Offline", tint: .red))
        }
    }

    // MARK: - Bottom cluster

    private func batteryIcon(_ level: Int) -> String {
        switch level {
        case ..<13: return "battery.0percent"
        case ..<38: return "battery.25percent"
        case ..<63: return "battery.50percent"
        case ..<88: return "battery.75percent"
        default: return "battery.100percent"
        }
    }
}

#Preview {
    DashboardView()
}

private extension View {
    /// Dark rounded cluster-panel background, matching the EnhanceDash look.
    func dashPanel() -> some View {
        background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(Color(red: 0.04, green: 0.04, blue: 0.05))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
    }

    /// Floating frosted-glass card so the live map stays visible behind it.
    func glassCard() -> some View {
        background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(
                        LinearGradient(
                            colors: [.white.opacity(0.22), .white.opacity(0.05)],
                            startPoint: .topLeading, endPoint: .bottomTrailing
                        ),
                        lineWidth: 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
            .shadow(color: .black.opacity(0.45), radius: 22, y: 12)
    }
}
