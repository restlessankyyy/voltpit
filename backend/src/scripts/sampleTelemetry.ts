/**
 * Posts a sample Fleet Telemetry record to the running backend's ingest
 * endpoint, shaped like Tesla's fleet-telemetry JSON config-topic output. Use
 * it to exercise the `tesla_telemetry` source (and Cosmos persistence) end to
 * end without a real car.
 *
 *   npm run telemetry:sample
 *
 * Env overrides:
 *   INGEST_URL    full ingest URL  (default http://localhost:8080/telemetry/ingest)
 *   PORT          used to build the default URL when INGEST_URL is unset (8080)
 *   INGEST_PATH   path for the default URL                 (/telemetry/ingest)
 *   TELEMETRY_INGEST_TOKEN  bearer token if the endpoint is guarded
 *   VIN           vehicle VIN to report                    (5YJ3SAMPLE0000001)
 */
const port = process.env.PORT ?? '8080';
const path = process.env.INGEST_PATH ?? '/telemetry/ingest';
const url = process.env.INGEST_URL ?? `http://localhost:${port}${path}`;
const token = process.env.TELEMETRY_INGEST_TOKEN?.trim() ?? '';
const vin = process.env.VIN ?? '5YJ3SAMPLE0000001';

// A plausible moving snapshot: ~88 km/h heading NNE through central Stockholm.
const record = {
  vin,
  createdAt: new Date().toISOString(),
  data: [
    { key: 'VehicleSpeed', value: { doubleValue: 55 } }, // mph
    { key: 'GpsHeading', value: { doubleValue: 24 } },
    {
      key: 'Location',
      value: { locationValue: { latitude: 59.3293, longitude: 18.0686 } },
    },
    { key: 'Soc', value: { doubleValue: 72 } },
    { key: 'Gear', value: { stringValue: 'D' } },
    { key: 'ACChargingPower', value: { doubleValue: 0 } },
  ],
};

const headers: Record<string, string> = {
  'content-type': 'application/json',
};
if (token) headers.authorization = `Bearer ${token}`;

try {
  const res = await fetch(url, {
    method: 'POST',
    headers,
    body: JSON.stringify(record),
  });
  const body = await res.text();
  console.log(`POST ${url} -> ${res.status}`);
  console.log(body);
  if (!res.ok) process.exit(1);
} catch (err) {
  console.error(
    `Failed to reach ${url}. Is the backend running with SOURCE=tesla_telemetry?`,
  );
  console.error(err instanceof Error ? err.message : err);
  process.exit(1);
}
