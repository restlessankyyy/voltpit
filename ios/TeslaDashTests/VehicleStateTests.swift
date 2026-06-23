import XCTest
@testable import TeslaDash

/// Unit tests for the `VehicleState` model that backs the dashboard UI: the
/// JSON contract streamed by the backend and the derived values the views read
/// (primary speed, unit label, metric vs imperial).
final class VehicleStateTests: XCTestCase {

    private func decode(_ json: String) throws -> VehicleState {
        try JSONDecoder().decode(VehicleState.self, from: Data(json.utf8))
    }

    /// The exact shape the Node backend broadcasts over /stream.
    func testDecodesBackendStreamPayload() throws {
        let json = """
        {"type":"vehicle_state","ts":1782218839425,"speedMph":48,"speedKph":77.2,
         "primaryUnit":"kph","lat":59.336055,"lng":18.036579,"heading":14.1,
         "shiftState":"D","power":43.2,"batteryLevel":82,"source":"simulator",
         "online":true}
        """
        let state = try decode(json)

        XCTAssertEqual(state.type, "vehicle_state")
        XCTAssertEqual(state.speedMph, 48)
        XCTAssertEqual(state.speedKph, 77.2)
        XCTAssertEqual(state.primaryUnit, "kph")
        XCTAssertEqual(state.batteryLevel, 82)
        XCTAssertEqual(state.source, "simulator")
        XCTAssertTrue(state.online)
    }

    func testDecodesNullSpeedsWhenParked() throws {
        let json = """
        {"type":"vehicle_state","ts":1,"speedMph":null,"speedKph":null,
         "primaryUnit":"kph","lat":null,"lng":null,"heading":null,
         "shiftState":"P","power":null,"batteryLevel":null,"source":"tesla",
         "online":false}
        """
        let state = try decode(json)

        XCTAssertNil(state.speedMph)
        XCTAssertNil(state.speedKph)
        XCTAssertNil(state.batteryLevel)
        XCTAssertFalse(state.online)
    }

    func testUsesMetricForKphAndKmh() {
        XCTAssertTrue(make(primaryUnit: "kph").usesMetric)
        XCTAssertTrue(make(primaryUnit: "kmh").usesMetric)
        XCTAssertFalse(make(primaryUnit: "mph").usesMetric)
    }

    func testPrimarySpeedPicksTheConfiguredUnit() {
        let metric = make(primaryUnit: "kph", speedMph: 30, speedKph: 48)
        XCTAssertEqual(metric.primarySpeed, 48)

        let imperial = make(primaryUnit: "mph", speedMph: 30, speedKph: 48)
        XCTAssertEqual(imperial.primarySpeed, 30)
    }

    func testPrimarySpeedClampsAndDefaultsToZero() {
        XCTAssertEqual(make(primaryUnit: "kph", speedKph: nil).primarySpeed, 0)
        XCTAssertEqual(make(primaryUnit: "kph", speedKph: -5).primarySpeed, 0)
    }

    func testUnitLabel() {
        XCTAssertEqual(make(primaryUnit: "kph").unitLabel, "km/h")
        XCTAssertEqual(make(primaryUnit: "mph").unitLabel, "mph")
    }

    func testStatusMessageDecodes() throws {
        let json = """
        {"type":"status","ts":1,"level":"warn","message":"vehicle asleep"}
        """
        let status = try JSONDecoder().decode(StatusMessage.self, from: Data(json.utf8))
        XCTAssertEqual(status.level, "warn")
        XCTAssertEqual(status.message, "vehicle asleep")
    }

    // MARK: - Helpers

    private func make(
        primaryUnit: String,
        speedMph: Double? = 0,
        speedKph: Double? = 0
    ) -> VehicleState {
        VehicleState(
            type: "vehicle_state",
            ts: 0,
            speedMph: speedMph,
            speedKph: speedKph,
            primaryUnit: primaryUnit,
            lat: nil,
            lng: nil,
            heading: nil,
            shiftState: "D",
            power: nil,
            batteryLevel: nil,
            source: "simulator",
            online: true
        )
    }
}
