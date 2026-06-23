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
    end
    subgraph Backend["Azure Container Apps backend (Node, TypeScript)"]
        OAuthMod["TeslaOAuth + TokenStore"]
        FleetClient["FleetApi"]
        Sources["VehicleSource"]
        Hub["WsHub"]
    end
    subgraph iOS["iPhone TeslaDash (SwiftUI)"]
        Stream["VehicleStream"]
        UI["Dashboard: Speedometer + Apple Map"]
    end

    Car -->|telemetry| Fleet
    OAuthMod -->|authorize / refresh| OAuth
    OAuthMod --> FleetClient
    FleetClient -->|bearer poll| Fleet
    FleetClient --> Sources --> Hub
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

## Components

| Layer | Component | Responsibility |
| --- | --- | --- |
| Vehicle | Tesla Model Y | Reports drive, charge, and location telemetry to Tesla. |
| Tesla Cloud | OAuth 2.0 | Authorizes the app and issues access / refresh tokens. |
| Tesla Cloud | Fleet API | Serves `vehicle_data` to authenticated clients. |
| Backend | TeslaOAuth + TokenStore | Runs the OAuth code exchange and caches tokens. |
| Backend | FleetApi | Polls `vehicle_data` with a bearer token. |
| Backend | VehicleSource | Abstracts the data source (Simulator or Tesla). |
| Backend | WsHub | Broadcasts `VehicleState` to connected clients. |
| iOS | VehicleStream | WebSocket client that receives `VehicleState`. |
| iOS | Dashboard | Renders the speedometer and heading-follow Apple Map. |

See the [backend reference](../backend/README.md) and
[Tesla Fleet API setup](TESLA_FLEET_API_SETUP.md) for details.
