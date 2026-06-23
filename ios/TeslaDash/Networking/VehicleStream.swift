import Foundation
import Combine

/// Connects to the backend WebSocket, decodes `VehicleState` messages, and
/// publishes them to the UI. Automatically reconnects on drop with backoff.
@MainActor
final class VehicleStream: ObservableObject {
    @Published private(set) var state: VehicleState?
    @Published private(set) var connection: StreamConnection = .connecting
    @Published private(set) var lastStatus: String?

    private var task: URLSessionWebSocketTask?
    private var session: URLSession
    private var url: URL
    private var reconnectAttempt = 0
    private var isStopping = false

    init(url: URL = AppConfig.streamURL) {
        self.url = url
        self.session = URLSession(configuration: .default)
    }

    func start() {
        isStopping = false
        connect()
    }

    func stop() {
        isStopping = true
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    /// Point the stream at a new backend URL (e.g. after editing Settings).
    func updateURL(_ newURL: URL) {
        url = newURL
        reconnectAttempt = 0
        task?.cancel(with: .goingAway, reason: nil)
        connect()
    }

    private func connect() {
        guard !isStopping else { return }
        connection = .connecting
        let task = session.webSocketTask(with: makeRequest(for: url))
        self.task = task
        task.resume()
        receive()
        // The first successful receive flips us to .connected.
    }

    /// Builds the handshake request, attaching the bearer token when configured
    /// so the backend authorizes the WebSocket upgrade.
    private func makeRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        let token = AppConfig.streamToken
        if !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private func receive() {
        task?.receive { [weak self] result in
            guard let self else { return }
            Task { @MainActor in
                switch result {
                case .success(let message):
                    self.reconnectAttempt = 0
                    self.connection = .connected
                    self.handle(message)
                    self.receive() // keep listening
                case .failure(let error):
                    self.handleDisconnect(error.localizedDescription)
                }
            }
        }
    }

    private func handle(_ message: URLSessionWebSocketTask.Message) {
        let data: Data?
        switch message {
        case .string(let text): data = text.data(using: .utf8)
        case .data(let d): data = d
        @unknown default: data = nil
        }
        guard let data else { return }

        // Peek at the message type to route to the right decoder.
        if let vehicle = try? JSONDecoder().decode(VehicleState.self, from: data),
           vehicle.type == "vehicle_state" {
            state = vehicle
        } else if let status = try? JSONDecoder().decode(StatusMessage.self, from: data),
                  status.type == "status" {
            lastStatus = status.message
        }
    }

    private func handleDisconnect(_ reason: String) {
        guard !isStopping else { return }
        connection = .disconnected(reason)
        reconnectAttempt += 1
        let delay = min(10.0, pow(1.6, Double(reconnectAttempt)))
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            self.connect()
        }
    }
}
