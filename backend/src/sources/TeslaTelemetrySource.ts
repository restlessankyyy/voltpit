import type { Express, Request, Response } from 'express';
import express from 'express';
import { timingSafeEqual } from 'node:crypto';

import type { VehicleSource } from './VehicleSource.js';
import type { ServerMessage, VehicleState, Unit } from '../types.js';
import { kphFromMph } from '../types.js';

/**
 * Receives realtime telemetry from Tesla's upstream `fleet-telemetry` server.
 *
 * Tesla's fleet-telemetry edge server handles the car's mTLS connection and
 * protobuf decoding, then forwards decoded records to a configured HTTP sink.
 * This source IS that sink: it accepts POSTed JSON on `ingestPath`, maps each
 * record to the app's VehicleState, and emits it to the WsHub. This avoids
 * reimplementing Tesla's protobuf/mTLS stack in Node.
 *
 * The POST body is expected to be either a single record or an array of
 * records, each shaped like fleet-telemetry's JSON config-topic output:
 *   { vin, createdAt, data: [{ key, value }, ...] }
 * where `value` is a oneof such as { stringValue }, { doubleValue },
 * { locationValue: { latitude, longitude } }, etc.
 */
export class TeslaTelemetrySource implements VehicleSource {
  readonly name = 'tesla_telemetry';

  private emit: ((message: ServerMessage) => void) | null = null;
  private lastByVin = new Map<string, VehicleState>();

  constructor(
    private readonly app: Express,
    private readonly ingestPath: string,
    private readonly ingestToken: string,
    private readonly primaryUnit: Unit,
    /** Optional sink so persistence sees the resolved VIN alongside the state. */
    private readonly onState?: (state: VehicleState, vin: string) => void,
  ) {}

  start(emit: (message: ServerMessage) => void): void {
    this.emit = emit;
    // Parse JSON only for the ingest route to keep the rest of the app lean.
    this.app.post(this.ingestPath, express.json({ limit: '1mb' }), (req, res) =>
      this.handleIngest(req, res),
    );
    emit(status('info', `Telemetry receiver ready at ${this.ingestPath}`));
  }

  stop(): void {
    this.emit = null;
    this.lastByVin.clear();
  }

  private handleIngest(req: Request, res: Response): void {
    if (!this.isAuthorized(req)) {
      res.status(401).json({ ok: false, error: 'unauthorized' });
      return;
    }

    const body = req.body as unknown;
    const records = Array.isArray(body) ? body : [body];
    let accepted = 0;
    for (const record of records) {
      const mapped = this.mapRecord(record);
      if (!mapped) continue;
      accepted += 1;
      this.lastByVin.set(mapped.vin, mapped.state);
      this.emit?.(mapped.state);
      this.onState?.(mapped.state, mapped.vin);
    }

    res.json({ ok: true, accepted });
  }

  private isAuthorized(req: Request): boolean {
    if (!this.ingestToken) return true;
    const header = req.headers.authorization;
    const provided = header?.startsWith('Bearer ') ? header.slice(7) : '';
    const a = Buffer.from(provided);
    const b = Buffer.from(this.ingestToken);
    return a.length === b.length && timingSafeEqual(a, b);
  }

  /**
   * Maps one fleet-telemetry record to a VehicleState, merging onto the last
   * known state for that VIN so partial updates (telemetry sends only changed
   * fields) still produce a complete snapshot.
   */
  private mapRecord(
    record: unknown,
  ): { vin: string; state: VehicleState } | null {
    if (!isRecord(record)) return null;
    const vin = typeof record.vin === 'string' ? record.vin : null;
    if (!vin) return null;

    const fields = readFields(record.data);
    const ts = parseTs(record.createdAt) ?? Date.now();
    const prev = this.lastByVin.get(vin);

    const speedMph = numeric(fields, ['VehicleSpeed', 'Speed']);
    const speedKph = speedMph === null ? prev?.speedKph ?? null : round(kphFromMph(speedMph), 1);

    const loc = location(fields, ['Location']);
    const lat = loc?.lat ?? numeric(fields, ['Latitude']) ?? prev?.lat ?? null;
    const lng = loc?.lng ?? numeric(fields, ['Longitude']) ?? prev?.lng ?? null;

    const state: VehicleState = {
      type: 'vehicle_state',
      ts,
      speedMph: speedMph ?? prev?.speedMph ?? null,
      speedKph,
      primaryUnit: this.primaryUnit,
      lat,
      lng,
      heading: numeric(fields, ['GpsHeading', 'Heading']) ?? prev?.heading ?? null,
      shiftState: text(fields, ['Gear', 'ShiftState']) ?? prev?.shiftState ?? 'P',
      power: numeric(fields, ['ACChargingPower', 'Power']) ?? prev?.power ?? null,
      batteryLevel:
        numeric(fields, ['Soc', 'BatteryLevel']) ?? prev?.batteryLevel ?? null,
      source: 'tesla_telemetry',
      online: true,
    };

    return { vin, state };
  }
}

// ── helpers ──────────────────────────────────────────────────────────────────

type FieldMap = Map<string, unknown>;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

/**
 * Flattens fleet-telemetry's `data: [{ key, value }]` array into a key→value
 * map, unwrapping the protobuf-JSON `value` oneof to a plain JS value.
 */
function readFields(data: unknown): FieldMap {
  const map: FieldMap = new Map();
  if (!Array.isArray(data)) return map;
  for (const entry of data) {
    if (!isRecord(entry)) continue;
    const key = typeof entry.key === 'string' ? entry.key : null;
    if (!key) continue;
    map.set(key, unwrapValue(entry.value));
  }
  return map;
}

/** Unwraps a fleet-telemetry value oneof to a plain JS value. */
function unwrapValue(value: unknown): unknown {
  if (!isRecord(value)) return value;
  if ('stringValue' in value) return value.stringValue;
  if ('doubleValue' in value) return value.doubleValue;
  if ('intValue' in value) return value.intValue;
  if ('floatValue' in value) return value.floatValue;
  if ('booleanValue' in value) return value.booleanValue;
  if ('locationValue' in value) return value.locationValue;
  if ('shiftStateValue' in value) return value.shiftStateValue;
  return value;
}

function numeric(fields: FieldMap, keys: string[]): number | null {
  for (const key of keys) {
    if (!fields.has(key)) continue;
    const raw = fields.get(key);
    const n = typeof raw === 'string' ? Number(raw) : raw;
    if (typeof n === 'number' && Number.isFinite(n)) return n;
  }
  return null;
}

function text(fields: FieldMap, keys: string[]): string | null {
  for (const key of keys) {
    if (!fields.has(key)) continue;
    const raw = fields.get(key);
    if (typeof raw === 'string' && raw !== '') return raw;
  }
  return null;
}

function location(
  fields: FieldMap,
  keys: string[],
): { lat: number; lng: number } | null {
  for (const key of keys) {
    if (!fields.has(key)) continue;
    const raw = fields.get(key);
    if (!isRecord(raw)) continue;
    const lat = Number(raw.latitude);
    const lng = Number(raw.longitude);
    if (Number.isFinite(lat) && Number.isFinite(lng)) return { lat, lng };
  }
  return null;
}

function parseTs(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) return value;
  if (typeof value === 'string') {
    const ms = Date.parse(value);
    if (Number.isFinite(ms)) return ms;
  }
  return null;
}

function status(
  level: 'info' | 'warn' | 'error',
  message: string,
): ServerMessage {
  return { type: 'status', ts: Date.now(), level, message };
}

function round(v: number, decimals: number): number {
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}
