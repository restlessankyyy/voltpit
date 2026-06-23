# Voltpit Architecture

Voltpit is a Tesla Model Y style driving dashboard: a large speedometer over a live
Apple Map that follows your heading, fed by your car's data through the Tesla Fleet API
with realtime updates over a WebSocket.

## System overview

```mermaid
flowchart LR
    subgraph Vehicle
        Car["Tesla Model Y"]
    end
    subgraph TeslaCloud["Tesla Cloud"]
        OAuth["OAuth 2.0"]
        Fleet["Fleet API"]
        Telemetry["fleet-telemetry server"]
    end
    subgraph Backend["Azure Container Apps backend (Node, TypeScript)"]
        OAuthMod["TeslaOAuth + TokenStore"]
        FleetClient["FleetApi"]
        Sources["VehicleSource"]
        TelemetrySrc["TeslaTelemetrySource"]
        Cosmos["CosmosEventStore"]
        Hub["WsHub"]
    end
    subgraph Azure["Azure"]
        CosmosDB[("Cosmos DB")]
    end
    subgraph iOS["iPhone TeslaDash (SwiftUI)"]
        Stream["VehicleStream"]
        UI["Dashboard: Speedometer + Apple Map"]
    end

    Car -->|telemetry| Fleet
    Car -->|telemetry| Telemetry
    OAuthMod -->|authorize / refresh| OAuth
    OAuthMod --> FleetClient
    FleetClient -->|bearer poll| Fleet
    FleetClient --> Sources --> Hub
    Telemetry -->|POST decoded records| TelemetrySrc
    TelemetrySrc --> Hub
    TelemetrySrc -->|onState| Cosmos
    Cosmos -->|managed identity write| CosmosDB
    Hub -->|wss VehicleState JSON| Stream
    Stream -->|bearer STREAM_TOKEN| Hub
    Stream --> UI
```

## Realtime data flow

```mermaid
sequenceDiagram
    participant U as User (browser)
    participant T as Tesla OAuth / Fleet API
    participant B as Backend (TeslaSource + WsHub)
    participant P as iPhone app

    Note over U,T: One-time authorization
    U->>B: GET /auth/login
    B->>T: redirect to authorize
    U->>T: sign in + consent
    T->>B: /auth/callback?code=...
    B->>T: exchange code for tokens
    B-->>B: TokenStore.save(.tokens.json)

    Note over B,P: Realtime streaming loop
    P->>B: WS connect /stream (Bearer STREAM_TOKEN)
    B-->>P: 101 Switching Protocols
    loop every POLL_INTERVAL_MS
        B->>T: GET vehicle_data (Bearer access token)
        alt 200 OK
            T-->>B: drive · charge · location
            B->>P: VehicleState JSON (speed, lat/lng, heading)
        else 408 asleep
            T-->>B: 408
            B->>P: offline VehicleState (back off)
        else 403 EXCEEDED_LIMIT
            T-->>B: account disabled
            B->>P: status warning
        end
    end
```

## Telemetry ingestion and persistence

```mermaid
sequenceDiagram
    participant FT as Tesla fleet-telemetry server
    participant S as TeslaTelemetrySource (/telemetry/ingest)
    participant H as WsHub
    participant C as CosmosEventStore
    participant DB as Cosmos DB
    participant P as iPhone app

    Note over FT,S: Push ingest (SOURCE=tesla_telemetry)
    FT->>S: POST decoded records (Bearer TELEMETRY_INGEST_TOKEN)
    S-->>S: map records to VehicleState (merge per VIN)
    S->>H: emit VehicleState
    H->>P: VehicleState JSON over wss
    S->>C: onState(state, vin)
    C->>DB: create item (managed identity, ttl 30d)
    Note right of C: best-effort, failures logged not thrown
    S-->>FT: 200 { ok, accepted }
```

## Components

| Layer | Component | Responsibility |
| --- | --- | --- |
| Vehicle | Tesla Model Y | Reports drive, charge, and location telemetry to Tesla. |
| Tesla Cloud | OAuth 2.0 | Authorizes the app and issues access / refresh tokens. |
| Tesla Cloud | Fleet API | Serves `vehicle_data` to authenticated clients. |
| Backend | TeslaOAuth + TokenStore | Runs the OAuth code exchange and caches tokens. |
| Backend | FleetApi | Polls `vehicle_data` with a bearer token. |
| Backend | VehicleSource | Abstracts the data source (Simulator, Tesla poll, or Tesla telemetry). |
| Backend | TeslaTelemetrySource | HTTP sink for Tesla's fleet-telemetry server; maps pushed records to `VehicleState`. |
| Backend | CosmosEventStore | Best-effort persistence of events to Cosmos DB with a 30-day TTL. |
| Backend | WsHub | Broadcasts `VehicleState` to connected clients. |
| Azure | Cosmos DB | Stores streamed events (`/vin` partition), least-privilege managed-identity writes. |
| iOS | VehicleStream | WebSocket client that receives `VehicleState`. |
| iOS | Dashboard | Renders the speedometer and heading-follow Apple Map. |

See the [backend reference](../backend/README.md) and
[Tesla Fleet API setup](TESLA_FLEET_API_SETUP.md) for details.
