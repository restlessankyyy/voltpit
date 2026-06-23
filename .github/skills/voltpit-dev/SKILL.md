---
name: voltpit-dev
description: >
  USE FOR: Working in the Voltpit (tesla-dash) repo — a SwiftUI iPhone Tesla
  dashboard with a Node/TypeScript backend that streams VehicleState over a
  WebSocket, fed by the Tesla Fleet API (or a simulator), deployed to Azure
  Container Apps via Terraform. Covers run/build commands, the data-source
  abstraction, secret hygiene, and Tesla Fleet API gotchas. DO NOT USE FOR:
  unrelated repos.
---

# Voltpit (tesla-dash) Development

Voltpit is a Tesla Model Y style driving dashboard: a big speedometer over a
live Apple Map that follows your heading, fed by your car's data through the
Tesla Fleet API with realtime updates over WebSocket.

## Architecture

```
Tesla vehicle ─▶ Tesla Fleet API ◀─ backend (Node) ──ws──▶ iPhone app (SwiftUI)
                                     OAuth + tokens
                                     WebSocket hub
```

| Path | What it is |
| --- | --- |
| `backend/` | Node + TypeScript: Tesla OAuth, token storage, data sources (simulator, Fleet API poll, Fleet Telemetry push), Cosmos DB event persistence, WebSocket hub broadcasting `VehicleState`. |
| `ios/` | SwiftUI app: Apple MapKit background (no API key), Tesla-style speedometer, heading-follow camera, WebSocket client. |
| `infra/` | Terraform for Azure Container Apps deployment. |
| `docs/TESLA_FLEET_API_SETUP.md` | Tesla Fleet API onboarding (developer app, keys, OAuth, scopes). |

## Key conventions

- **Data-source abstraction.** A `VehicleSource` (in `backend/src/sources/`)
  produces `VehicleState` messages. `SimulatorSource` emits fake-but-realistic
  drives (no Tesla account); `TeslaSource` polls the Fleet API;
  `TeslaTelemetrySource` receives pushed fleet-telemetry records on an ingest
  endpoint. Selected via the `SOURCE` env var
  (`simulator` | `tesla` | `tesla_telemetry`). All sources feed the same
  `WsHub.broadcast()`, so the app needs no change.
- **Persistence.** `CosmosEventStore` (in `backend/src/storage/`) best-effort
  writes streamed events to Cosmos DB with a 30-day TTL via managed identity.
  Auto-disabled when `COSMOS_ENDPOINT` is unset; failures never break the stream.
- **Message shape.** Both sources emit the same `VehicleState` / `ServerMessage`
  types from `backend/src/types.ts`. Keep the iOS `VehicleState.swift` model in
  sync when changing the payload.
- **Stream auth.** The `/stream` WebSocket is guarded by `STREAM_TOKEN` (bearer
  header or `?token=`). Empty token = open (local dev only). The iOS app reads
  its token from UserDefaults (`stream_token`), never hardcoded.
- **Units.** Speeds carry both `speedMph` and `speedKph`; `primaryUnit` selects
  which the UI emphasizes.

## Common commands

Backend (from `backend/`):
```bash
cp .env.example .env          # SOURCE=simulator by default
npm install
npm run dev                   # ws://localhost:8080/stream
curl localhost:8080/health    # {"ok":true,"source":...}
```

iOS (from `ios/`):
```bash
brew install xcodegen          # one-time
xcodegen generate              # regenerates TeslaDash.xcodeproj from project.yml
open TeslaDash.xcodeproj
```
Build/install on a device with `xcodebuild ... -destination 'id=<UDID>'` then
`xcrun devicectl device install app --device <UDID> <path>.app`.

Infra (from `infra/`):
```bash
terraform output -raw stream_token   # bearer token for the app
terraform output                     # FQDN / stream_url / health_url
```

## Secret hygiene (critical)

Never commit any of these — they are gitignored at root and per-subdir:

- `backend/.env`, `*.tokens.json` (OAuth tokens)
- `backend/keys/*.pem` (Fleet API key pair)
- `infra/terraform.tfstate*`, `infra/terraform.tfvars` (subscription IDs, creds)
- `.azure/` (internal deployment notes: subscription IDs, account names, FQDNs)
- generated `ios/TeslaDash.xcodeproj/` and the large `ios/build/` artifacts

`*.example` files must contain only placeholders (e.g. all-zero subscription id),
never real values. The default stream URL in `ios/.../AppConfig.swift` must stay
generic (`ws://localhost:8080/stream`), not a personal cloud FQDN.

## Tesla Fleet API gotchas

- **`Not authorized yet`**: no stored OAuth tokens. Visit `/auth/login` once.
- **`403 account disabled: EXCEEDED_LIMIT`**: the developer account blew through
  the free Fleet API quota. Polling every 2.5s (`POLL_INTERVAL_MS`) burns it
  fast — raise the interval (30–60s) and rely on the asleep back-off, or move to
  Fleet Telemetry (push). Resolve by waiting for the monthly reset or adding
  billing in the Tesla developer portal.
- **`401 / invalid_token`**: refresh failed — delete `.tokens.json` and re-auth.
- **No GPS**: needs the `vehicle_location` scope and `location_data` endpoint
  (firmware 2023.38+). Re-authorize after changing scopes.
- **Token storage is ephemeral** on Container Apps local disk; a restart loses
  `.tokens.json`. Persist to a mounted volume / Key Vault for durability.

## GitHub account

This is a personal repo. Switch with `ghswitch restlessankyyy` before any
commit/push (see the `ghswitch-account` skill) and verify with
`git config user.name` + `gh auth status`.
