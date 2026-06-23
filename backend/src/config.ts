import 'dotenv/config';

function required(name: string, value: string | undefined): string {
  if (!value || value.trim() === '') {
    throw new Error(
      `Missing required env var ${name}. Copy .env.example to .env and fill it in.`,
    );
  }
  return value;
}

export type SourceKind = 'simulator' | 'tesla';
export type { Unit } from './types.js';
import type { Unit } from './types.js';

export interface Config {
  source: SourceKind;
  port: number;
  pollIntervalMs: number;
  primaryUnit: Unit;
  streamToken: string;
  tesla: {
    clientId: string;
    clientSecret: string;
    redirectUri: string;
    appDomain: string;
    fleetBaseUrl: string;
    scopes: string;
    vin: string | null;
    tokenStorePath: string;
  };
}

const source = (process.env.SOURCE ?? 'simulator') as SourceKind;

export const config: Config = {
  source,
  port: Number(process.env.PORT ?? 8080),
  pollIntervalMs: Number(process.env.POLL_INTERVAL_MS ?? 2500),
  primaryUnit: (process.env.PRIMARY_UNIT as Unit) ?? 'mph',
  // Shared bearer token guarding the /stream WebSocket. When empty (local
  // dev), the stream is open; in the cloud it is always set.
  streamToken: process.env.STREAM_TOKEN?.trim() ?? '',
  tesla: {
    // These are only validated lazily when SOURCE=tesla so simulator mode
    // can run with an empty .env.
    clientId: process.env.TESLA_CLIENT_ID ?? '',
    clientSecret: process.env.TESLA_CLIENT_SECRET ?? '',
    redirectUri:
      process.env.TESLA_REDIRECT_URI ?? 'http://localhost:8080/auth/callback',
    appDomain: process.env.TESLA_APP_DOMAIN ?? '',
    fleetBaseUrl:
      process.env.TESLA_FLEET_BASE_URL ??
      'https://fleet-api.prd.na.vn.cloud.tesla.com',
    scopes:
      process.env.TESLA_SCOPES ??
      'openid offline_access vehicle_device_data vehicle_location',
    vin: process.env.TESLA_VIN?.trim() || null,
    tokenStorePath: process.env.TOKEN_STORE_PATH ?? './.tokens.json',
  },
};

/** Validates Tesla config; call only on the tesla code path. */
export function assertTeslaConfig(): void {
  required('TESLA_CLIENT_ID', config.tesla.clientId);
  required('TESLA_CLIENT_SECRET', config.tesla.clientSecret);
  required('TESLA_APP_DOMAIN', config.tesla.appDomain);
}
