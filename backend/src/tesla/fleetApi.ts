import { config } from '../config.js';
import type { TeslaOAuth } from './oauth.js';

export interface DriveState {
  speed: number | null; // mph, null when parked
  latitude?: number;
  longitude?: number;
  heading?: number; // 0-360
  shift_state?: string | null; // 'P' | 'R' | 'N' | 'D'
  power?: number; // kW
  gps_as_of?: number;
}

export interface ChargeState {
  battery_level?: number;
}

export interface VehicleData {
  drive_state?: DriveState;
  charge_state?: ChargeState;
  state?: string; // 'online' | 'asleep' | 'offline'
}

export interface VehicleSummary {
  id: number;
  vehicle_id: number;
  vin: string;
  display_name: string;
  state: string; // online | asleep | offline
}

/**
 * Thin client over the Tesla Fleet API endpoints this app needs.
 * Docs: https://developer.tesla.com/docs/fleet-api/endpoints/vehicle-endpoints
 */
export class FleetApi {
  constructor(private readonly oauth: TeslaOAuth) {}

  private async authedFetch(path: string, init?: RequestInit): Promise<Response> {
    const token = await this.oauth.getAccessToken();
    return fetch(`${config.tesla.fleetBaseUrl}${path}`, {
      ...init,
      headers: {
        Authorization: `Bearer ${token}`,
        'Content-Type': 'application/json',
        ...(init?.headers ?? {}),
      },
    });
  }

  /** Lists vehicles on the account. */
  async listVehicles(): Promise<VehicleSummary[]> {
    const res = await this.authedFetch('/api/1/vehicles');
    if (!res.ok) {
      throw new Error(`listVehicles failed (${res.status}): ${await res.text()}`);
    }
    const json = (await res.json()) as { response: VehicleSummary[] };
    return json.response ?? [];
  }

  /** Resolves the VIN to operate on (configured VIN or first vehicle). */
  async resolveVin(): Promise<string> {
    if (config.tesla.vin) return config.tesla.vin;
    const vehicles = await this.listVehicles();
    if (vehicles.length === 0) {
      throw new Error('No vehicles on this Tesla account.');
    }
    return vehicles[0].vin;
  }

  /** Wakes the vehicle (needed before it will report fresh drive data). */
  async wake(vin: string): Promise<void> {
    await this.authedFetch(`/api/1/vehicles/${vin}/wake_up`, { method: 'POST' });
  }

  /**
   * Live vehicle data including drive_state. `location_data` is required to get
   * GPS on 2023.38+ firmware and needs the `vehicle_location` scope.
   * Returns null if the vehicle is asleep/offline (HTTP 408).
   */
  async getVehicleData(vin: string): Promise<VehicleData | null> {
    const res = await this.authedFetch(
      `/api/1/vehicles/${vin}/vehicle_data?endpoints=${encodeURIComponent(
        'drive_state;charge_state;location_data',
      )}`,
    );
    if (res.status === 408) return null; // vehicle unavailable / asleep
    if (!res.ok) {
      throw new Error(`vehicle_data failed (${res.status}): ${await res.text()}`);
    }
    const json = (await res.json()) as { response: VehicleData };
    return json.response;
  }
}
