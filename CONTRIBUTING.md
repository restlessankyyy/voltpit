# Contributing to Voltpit

Thanks for your interest in Voltpit, a Tesla Model Y style driving dashboard for
iPhone with a Node/TypeScript backend. This guide covers how to set up the
project, the conventions to follow, and how to get a change merged.

## Prerequisites

- **Node.js** >= 18 (the backend `engines` field requires it)
- **Xcode** (latest) and **XcodeGen** (`brew install xcodegen`) for the iOS app
- **Terraform** and the **Azure CLI** only if you touch `infra/`
- A Tesla developer account only if you work against the real Fleet API; the
  simulator needs none

## Repo layout

| Path | What it is |
| --- | --- |
| [`backend/`](backend/) | Node + TypeScript service: Tesla OAuth, token storage, data sources (simulator, Fleet API poll, Fleet Telemetry push), Cosmos DB persistence, and the WebSocket hub that streams `VehicleState`. |
| [`ios/`](ios/) | SwiftUI iPhone app: Apple MapKit background, Tesla-style speedometer, heading-follow camera, realtime WebSocket client. |
| [`infra/`](infra/) | Terraform for the Azure Container Apps deployment. |
| [`docs/`](docs/) | Architecture overview and Tesla Fleet API setup guide. |

## Local development

### Backend (from `backend/`)

```bash
cp .env.example .env          # SOURCE=simulator is the default
npm install
npm run dev                   # ws://localhost:8080/stream
curl localhost:8080/health    # {"ok":true,"source":...}
```

`npm run dev` runs the simulator source by default, so you get fake but realistic
driving data with no Tesla account. Set `SOURCE=tesla` in `.env` (and follow
[`docs/TESLA_FLEET_API_SETUP.md`](docs/TESLA_FLEET_API_SETUP.md)) to use a real car.

Before pushing backend changes, make sure the project type-checks and builds:

```bash
npx tsc --noEmit              # type check
npm run build                 # compile to dist/
```

### iOS app (from `ios/`)

```bash
brew install xcodegen         # one-time
xcodegen generate             # regenerates TeslaDash.xcodeproj from project.yml
open TeslaDash.xcodeproj
```

`TeslaDash.xcodeproj/` is generated, so edit `project.yml` (not the project file)
when changing build settings, then re-run `xcodegen generate`.

## Conventions

- **Data-source abstraction.** A `VehicleSource` (in `backend/src/sources/`)
  produces `VehicleState` messages, selected via the `SOURCE` env var. To add a
  new data path, add a source that feeds the same `WsHub.broadcast()`; the app
  needs no change.
- **Keep the payload in sync.** Both backend sources emit the same
  `VehicleState` / `ServerMessage` types from
  [`backend/src/types.ts`](backend/src/types.ts). When you change the payload,
  update the iOS model in
  [`ios/TeslaDash/Models/VehicleState.swift`](ios/TeslaDash/Models/VehicleState.swift)
  in the same change.
- **Units.** Speeds carry both `speedMph` and `speedKph`; `primaryUnit`
  (`mph` | `kph`) selects which the UI emphasizes. It defaults to `kph` locally.
- **Stream auth.** The `/stream` WebSocket is guarded by `STREAM_TOKEN`. An empty
  token means open, which is for local dev only. The iOS app reads its token from
  UserDefaults; never hardcode it.

## Secret hygiene (critical)

Never commit any of these (they are gitignored):

- `backend/.env`, `*.tokens.json` (OAuth tokens)
- `backend/keys/*.pem` (Fleet API key pair)
- `infra/terraform.tfstate*`, `infra/terraform.tfvars` (subscription IDs, creds)
- generated `ios/TeslaDash.xcodeproj/` and the large `ios/build/` artifacts

`*.example` files must contain only placeholders, never real values. The default
stream URL in `AppConfig.swift` must stay generic (`ws://localhost:8080/stream`).

## Branches, commits, and pull requests

1. Branch off `main` with a short, descriptive name (for example
   `feat/heading-smoothing` or `fix/token-refresh`).
2. Keep commits focused and write clear messages. Conventional prefixes
   (`feat:`, `fix:`, `docs:`, `chore:`) are appreciated.
3. Before opening a PR, review whether your change affects the architecture. If
   it does, update [`docs/ARCHITECTURE.md`](docs/ARCHITECTURE.md) (and the
   relevant README sections) in the same PR.
4. Open the PR against `main` with a summary of what changed and why, and note
   how you tested it. When you push more commits to an open PR, keep the PR
   description in sync with the full state of the branch.

## Questions

Open an issue if anything here is unclear or out of date.
