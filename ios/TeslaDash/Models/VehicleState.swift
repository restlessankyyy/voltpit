import Foundation

/// Mirrors the backend `VehicleState` JSON streamed over WebSocket.
struct VehicleState: Codable, Equatable {
    let type: String
    let ts: Double
    let speedMph: Double?
    let speedKph: Double?
    let primaryUnit: String
    let lat: Double?
    let lng: Double?
    let heading: Double?
    let shiftState: String?
    let power: Double?
    let batteryLevel: Int?
    let source: String
    let online: Bool

    /// True when the configured primary unit is metric (km/h).
    var usesMetric: Bool { primaryUnit == "kph" || primaryUnit == "kmh" }

    /// The speed to render large, in the configured primary unit.
    var primarySpeed: Double {
        let value = usesMetric ? speedKph : speedMph
        return max(0, value ?? 0)
    }

    var unitLabel: String { usesMetric ? "km/h" : "mph" }
}

/// Diagnostic/status messages from the backend (asleep, auth needed, etc.).
struct StatusMessage: Codable {
    let type: String
    let ts: Double
    let level: String
    let message: String
}

/// Connection state for the stream, surfaced in the UI.
enum StreamConnection: Equatable {
    case connecting
    case connected
    case disconnected(String)
}
