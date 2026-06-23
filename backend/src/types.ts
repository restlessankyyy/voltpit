/**
 * The single message shape streamed to the iPhone app over WebSocket.
 * Keep this in sync with `VehicleState` in the Swift app.
 */
export type Unit = 'mph' | 'kph';

export interface VehicleState {
  type: 'vehicle_state';
  /** Unix epoch milliseconds when this sample was produced. */
  ts: number;
  /** Speed in miles per hour (null when parked / unknown). */
  speedMph: number | null;
  /** Speed in kilometers per hour (null when parked / unknown). */
  speedKph: number | null;
  /** Which unit the app should show large. */
  primaryUnit: 'mph' | 'kph';
  /** Latitude in decimal degrees. */
  lat: number | null;
  /** Longitude in decimal degrees. */
  lng: number | null;
  /** Compass heading 0–360 (0 = north), used to rotate the map + arrow. */
  heading: number | null;
  /** Gear: 'P' | 'R' | 'N' | 'D' or null. */
  shiftState: string | null;
  /** Instantaneous power in kW (positive = drawing, negative = regen). */
  power: number | null;
  /** Battery state of charge, percent. */
  batteryLevel: number | null;
  /** Where this data came from. */
  source: 'simulator' | 'tesla';
  /** True when the vehicle is awake and reporting. */
  online: boolean;
}

/** Status/diagnostic messages (e.g. vehicle asleep, auth needed). */
export interface StatusMessage {
  type: 'status';
  ts: number;
  level: 'info' | 'warn' | 'error';
  message: string;
}

export type ServerMessage = VehicleState | StatusMessage;

const MPH_PER_KPH = 0.621371;

export function kphFromMph(mph: number): number {
  return mph / MPH_PER_KPH;
}

export function mphFromKph(kph: number): number {
  return kph * MPH_PER_KPH;
}
