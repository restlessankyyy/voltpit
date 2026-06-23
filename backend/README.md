# Voltpit: Backend

Node + TypeScript service that turns your car's data into a realtime WebSocket
stream the iPhone app consumes. It abstracts the data source so you can run with
a **simulator** today and switch to the real **Tesla Fleet API** later.

## Run

```bash
cp .env.example .env      # SOURCE=simulator by default
npm install
npm run dev               # ws://localhost:8080/stream
```

`GET /health` returns `{ ok, source, clients }`.

## Configuration

All config is via `.env` (see [`.env.example`](.env.example)). Key values:

| Var | Meaning |
| --- | --- |
| `SOURCE` | `simulator`, `tesla`, or `tesla_telemetry`. |
| `PORT` | HTTP + WebSocket port (default 8080). |
| `POLL_INTERVAL_MS` | How often to poll Tesla `vehicle_data` while driving. |
| `PRIMARY_UNIT` | `mph` or `kph`: which speed the app shows large. |
| `TESLA_*` | Fleet API credentials (only for `SOURCE=tesla`). |
| `TELEMETRY_INGEST_PATH` | Path the fleet-telemetry server POSTs to (default `/telemetry/ingest`). |
| `TELEMETRY_INGEST_TOKEN` | Shared secret guarding the ingest endpoint (empty = open, local dev). |
| `COSMOS_ENDPOINT` | Cosmos account endpoint. Empty disables persistence. |
| `COSMOS_DATABASE` / `COSMOS_CONTAINER` | Target database and container (defaults `tesladash` / `events`). |
| `COSMOS_TTL_SECONDS` | Per-event time-to-live (default 30 days). |

## The stream contract

Every update is one JSON message. The app decodes exactly this shape (kept in
sync with `VehicleState` in Swift):

```json
{
  "type": "vehicle_state",
  "ts": 1718600000000,
  "speedMph": 47.2, "speedKph": 75.9, "primaryUnit": "mph",
  "lat": 37.7749, "lng": -122.4194, "heading": 182.5,
  "shiftState": "D", "power": 23, "batteryLevel": 78,
  "source": "simulator", "online": true
}
```

Diagnostic messages use `{"type":"status","level":"info|warn|error","message":"…"}`.

## Architecture

```mermaid
flowchart LR
    Index["index.ts"] --> Build["buildSource()"]
    Build --> Sim["SimulatorSource (fake drive loop)"]
    Build --> Tesla["TeslaSource"]
    Build --> Tel["TeslaTelemetrySource (/telemetry/ingest)"]
    Tesla --> Fleet["FleetApi"]
    Fleet --> OAuth["TeslaOAuth"]
    OAuth --> Store["TokenStore"]
    Sim --> Hub["WsHub.broadcast() (every sample)"]
    Fleet --> Hub
    Tel --> Hub
    Tel --> Cosmos["CosmosEventStore"]
    Cosmos --> DB[("Cosmos DB")]
    Hub --> WS["ws://…/stream"]
    WS --> App["iPhone app"]
```

- [`src/sources/`](src/sources/): pluggable data sources behind a common interface.
- [`src/storage/`](src/storage/): best-effort Cosmos DB persistence (`CosmosEventStore`).
- [`src/tesla/`](src/tesla/): OAuth, the Fleet API client, and token persistence.
- [`src/routes/`](src/routes/): `/auth/*` (OAuth) and the `.well-known` public key.
- [`src/wsHub.ts`](src/wsHub.ts): fan-out to all connected apps; replays last state on connect.

## Switching to your real Tesla

1. Complete [`../docs/TESLA_FLEET_API_SETUP.md`](../docs/TESLA_FLEET_API_SETUP.md).
2. Generate the signing keys: `npm run keys` (writes `keys/`, gitignored).
3. Set `SOURCE=tesla` and the `TESLA_*` values in `.env`.
4. `npm run dev`, then open `http://localhost:8080/auth/login` once to authorize.
5. The app now shows live data whenever the car is awake.

### Realtime note

Tesla discourages aggressive polling of `vehicle_data`. This backend polls at a
configurable interval and backs off when the car is asleep. For true sub-second
updates, configure **Fleet Telemetry** (the car streams to your server) and run
with `SOURCE=tesla_telemetry`: `TeslaTelemetrySource` exposes an ingest endpoint
that the fleet-telemetry server POSTs decoded records to, feeding the same
`WsHub` and optionally persisting each event to Cosmos DB. See the setup guide's
"Upgrade to Fleet Telemetry" section.

## Testing persistence locally (Cosmos DB Emulator)

Persistence targets Cosmos DB, so to exercise it without a real Azure account
run the **Azure Cosmos DB Emulator** (not Azurite, which only emulates Blob /
Queue / Table storage):

```bash
docker compose -f docker-compose.cosmos.yml up -d   # starts the emulator
```

Then set these in `.env` and start the backend:

```bash
COSMOS_ENDPOINT=https://localhost:8081
COSMOS_KEY=C2y6yDjf5/R+ob0N8A7Cgv30VRDJIWEHLM+4QDU5DE2nQ9nDuVTqobD4b8mGGyPMbIZnqyMsEcaGQy67XIw/Jw==
```

When `COSMOS_KEY` is set the app treats it as local mode: it trusts the
emulator's self-signed cert and creates the `tesladash`/`events` database and
container on startup. In production no key is used; the app authenticates with
its managed identity against the Terraform-provisioned account. Stop the
emulator with `docker compose -f docker-compose.cosmos.yml down`.

To push a sample record at the running telemetry receiver (no real car needed):

```bash
# backend running with SOURCE=tesla_telemetry on PORT (8080 by default)
PORT=8080 TELEMETRY_INGEST_TOKEN=<token-if-set> npm run telemetry:sample
```

It POSTs one fleet-telemetry-shaped record to `/telemetry/ingest`; you should
see a `vehicle_state` on the stream and (if Cosmos is configured) a persisted
event.
