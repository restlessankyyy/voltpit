# Tesla Fleet API setup

This walks you through connecting Tesla Dash to your real Model Y. Tesla's
official path is the **Fleet API**. You only have to do this once.

> You can skip all of this and run the app today with `SOURCE=simulator`. Come
> back when you're ready for live data.

## What you'll end up with

- A registered Tesla developer **application** (client ID + secret).
- A **public domain** hosting your EC public key (required even for read-only).
- OAuth tokens stored by the backend so it can read your car's `drive_state`.

## Prerequisites

- A Tesla account that owns (or is a driver on) the Model Y, with a **verified
  email** and **MFA enabled**.
- A **public HTTPS domain** you control (e.g. `dash.yourdomain.com`). This is a
  hard Tesla requirement: it hosts your public key and is your OAuth redirect
  host in production. For local dev you can tunnel (see step 5).

---

## Step 1 — Create the application

1. Go to the [Tesla Developer dashboard](https://developer.tesla.com/dashboard)
   and sign in with your Tesla account.
2. Create an application. Provide business/legal details, a name, and purpose.
3. Set the **OAuth redirect URI**. For local development use
   `http://localhost:8080/auth/callback` (matches `TESLA_REDIRECT_URI`). You can
   add your production `https://<domain>/auth/callback` later.
4. Select scopes:
   - `openid`
   - `offline_access`  (so the backend can refresh tokens)
   - `vehicle_device_data`  (read `drive_state`, `charge_state`)
   - `vehicle_location`  (GPS — required for the moving map)
5. Copy the **Client ID** and **Client Secret** into `backend/.env`:

   ```ini
   TESLA_CLIENT_ID=...
   TESLA_CLIENT_SECRET=...
   TESLA_SCOPES=openid offline_access vehicle_device_data vehicle_location
   ```

## Step 2 — Pick your region base URL

Set `TESLA_FLEET_BASE_URL` to the region your Tesla account belongs to:

| Region | Base URL |
| --- | --- |
| North America / Asia-Pacific (excl. China) | `https://fleet-api.prd.na.vn.cloud.tesla.com` |
| Europe / Middle East / Africa | `https://fleet-api.prd.eu.vn.cloud.tesla.com` |

## Step 3 — Generate your key pair

Tesla requires an EC (P-256) public key hosted on your domain. The backend has a
helper that creates the same keys as the official `openssl` commands:

```bash
cd backend
npm run keys
# writes keys/private-key.pem (keep secret) and keys/public-key.pem (host it)
```

## Step 4 — Host the public key

The public key must be reachable at exactly:

```
https://<your-domain>/.well-known/appspecific/com.tesla.3p.public-key.pem
```

The backend already serves this route from `keys/public-key.pem`, so if you
deploy the backend to your domain it's handled. Set:

```ini
TESLA_APP_DOMAIN=your-domain.com
TESLA_REDIRECT_URI=https://your-domain.com/auth/callback
```

Verify it's live:

```bash
curl https://your-domain.com/.well-known/appspecific/com.tesla.3p.public-key.pem
```

## Step 5 — Local development without a public server

For local testing you still need the key reachable over HTTPS. Use a tunnel:

```bash
# Example with cloudflared (or use ngrok)
cloudflared tunnel --url http://localhost:8080
```

Use the tunnel's HTTPS hostname as `TESLA_APP_DOMAIN` and in the redirect URI,
and register that redirect URI on the Tesla dashboard.

## Step 6 — Register your partner account (per region)

Registration tells Tesla your domain is ready. Generate a **partner token** and
call the register endpoint once per region. With the backend running and your
`.env` filled, you can do it with `curl`:

```bash
# 1. Partner (client_credentials) token
PARTNER_TOKEN=$(curl -s --request POST \
  'https://auth.tesla.com/oauth2/v3/token' \
  --header 'Content-Type: application/x-www-form-urlencoded' \
  --data-urlencode "grant_type=client_credentials" \
  --data-urlencode "client_id=$TESLA_CLIENT_ID" \
  --data-urlencode "client_secret=$TESLA_CLIENT_SECRET" \
  --data-urlencode "scope=openid vehicle_device_data vehicle_location" \
  --data-urlencode "audience=$TESLA_FLEET_BASE_URL" | python3 -c 'import sys,json;print(json.load(sys.stdin)["access_token"])')

# 2. Register your domain
curl --request POST "$TESLA_FLEET_BASE_URL/api/1/partner_accounts" \
  --header "Authorization: Bearer $PARTNER_TOKEN" \
  --header 'Content-Type: application/json' \
  --data "{\"domain\": \"$TESLA_APP_DOMAIN\"}"
```

A `200` with your domain echoed back means you're registered.

## Step 7 — Authorize your Tesla account

1. Set `SOURCE=tesla` in `backend/.env`.
2. `npm run dev`.
3. Open `http://localhost:8080/auth/login` in a browser, sign in to Tesla, and
   approve the scopes. You'll be redirected back and see "Tesla connected ✅".
4. Tokens are saved to `.tokens.json` (gitignored) and auto-refreshed.

Open the iPhone app — when the car is awake you'll see live speed, position, and
heading.

---

## Upgrade to Fleet Telemetry (true realtime)

Polling `vehicle_data` is fine for a casual dashboard, but Tesla rate-limits it
and the car must be awake. For sub-second streaming, configure **Fleet
Telemetry**: the car opens a connection to *your* TLS server and pushes fields
like `Location`, `VehicleSpeed`, `Gear`, and `Heading`.

High level:

1. Add your public key to the vehicle (virtual key pairing) — see Tesla's
   [vehicle-command](https://github.com/teslamotors/vehicle-command) tooling.
2. Stand up a `fleet-telemetry` server with a valid TLS cert and CA.
3. Call `POST /api/1/vehicles/fleet_telemetry_config` (via the vehicle-command
   proxy) with your hostname, port, CA, and the fields above.
4. Replace `TeslaSource` with a small telemetry receiver that decodes the stream
   and calls `WsHub.broadcast()` with the same `VehicleState` shape — the app
   needs no changes.

Reference: <https://developer.tesla.com/docs/fleet-api/fleet-telemetry>

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| App shows "Asleep" | Car is asleep; the backend wakes it on start and backs off. Open the Tesla app or drive to wake it. |
| `Not authorized yet` in logs | Visit `/auth/login` to complete OAuth. |
| No GPS / map not moving | Missing `vehicle_location` scope, or firmware 2023.38+ needs `location_data` (already requested). Re-authorize after adding the scope. |
| `401`/`invalid_token` | Token expired and refresh failed; delete `.tokens.json` and re-authorize. |
| Register call fails | Public key not reachable at the well-known URL, or wrong region base URL. |
