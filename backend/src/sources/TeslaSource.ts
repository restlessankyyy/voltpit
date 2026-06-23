import type { VehicleSource } from './VehicleSource.js';
import type { ServerMessage, VehicleState, Unit } from '../types.js';
import { kphFromMph } from '../types.js';
import type { FleetApi, VehicleData, DriveState } from '../tesla/fleetApi.js';

/**
 * Polls the Tesla Fleet API `vehicle_data` endpoint and maps `drive_state` to
 * the app's VehicleState. Tesla discourages aggressive polling, so this:
 *   - polls at the configured interval (default 2.5s) only,
 *   - backs off when the vehicle is asleep/offline,
 *   - wakes the car once when polling starts.
 *
 * For sub-second realtime, configure Fleet Telemetry instead (see docs); this
 * source can then be swapped for a telemetry receiver feeding the same WsHub.
 */
export class TeslaSource implements VehicleSource {
  readonly name = 'tesla';

  private timer: ReturnType<typeof setTimeout> | null = null;
  private stopped = false;
  private vin: string | null = null;
  private consecutiveAsleep = 0;

  constructor(
    private readonly api: FleetApi,
    private readonly primaryUnit: Unit,
    private readonly pollIntervalMs: number,
  ) {}

  async start(emit: (message: ServerMessage) => void): Promise<void> {
    this.stopped = false;
    try {
      this.vin = await this.api.resolveVin();
      emit(status('info', `Connected to vehicle ${maskVin(this.vin)}`));
      await this.api.wake(this.vin).catch(() => undefined);
    } catch (err) {
      emit(status('error', `Tesla setup failed: ${errText(err)}`));
      return;
    }
    this.scheduleNext(emit, 0);
  }

  stop(): void {
    this.stopped = true;
    if (this.timer) clearTimeout(this.timer);
    this.timer = null;
  }

  private scheduleNext(emit: (m: ServerMessage) => void, delay: number): void {
    if (this.stopped) return;
    this.timer = setTimeout(() => this.poll(emit), delay);
  }

  private async poll(emit: (m: ServerMessage) => void): Promise<void> {
    if (this.stopped || !this.vin) return;
    try {
      const data = await this.api.getVehicleData(this.vin);
      if (!data) {
        // Asleep/offline: back off increasingly (cap ~30s) to respect limits.
        this.consecutiveAsleep += 1;
        const backoff = Math.min(30_000, this.pollIntervalMs * 2 ** this.consecutiveAsleep);
        emit(offlineState(this.primaryUnit));
        this.scheduleNext(emit, backoff);
        return;
      }
      this.consecutiveAsleep = 0;
      emit(this.mapToState(data));
    } catch (err) {
      emit(status('warn', `Poll error: ${errText(err)}`));
    }
    this.scheduleNext(emit, this.pollIntervalMs);
  }

  private mapToState(data: VehicleData): VehicleState {
    const ds: DriveState = data.drive_state ?? { speed: null };
    const speedMph = typeof ds.speed === 'number' ? ds.speed : null;
    return {
      type: 'vehicle_state',
      ts: Date.now(),
      speedMph,
      speedKph: speedMph === null ? null : round(kphFromMph(speedMph), 1),
      primaryUnit: this.primaryUnit,
      lat: ds.latitude ?? null,
      lng: ds.longitude ?? null,
      heading: ds.heading ?? null,
      shiftState: ds.shift_state ?? 'P',
      power: ds.power ?? null,
      batteryLevel: data.charge_state?.battery_level ?? null,
      source: 'tesla',
      online: (data.state ?? 'online') === 'online',
    };
  }
}

function offlineState(unit: Unit): VehicleState {
  return {
    type: 'vehicle_state',
    ts: Date.now(),
    speedMph: null,
    speedKph: null,
    primaryUnit: unit,
    lat: null,
    lng: null,
    heading: null,
    shiftState: 'P',
    power: null,
    batteryLevel: null,
    source: 'tesla',
    online: false,
  };
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

function maskVin(vin: string): string {
  return vin.length > 4 ? `…${vin.slice(-4)}` : vin;
}

function errText(err: unknown): string {
  return err instanceof Error ? err.message : String(err);
}
