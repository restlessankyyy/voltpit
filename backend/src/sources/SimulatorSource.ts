import type { VehicleSource } from './VehicleSource.js';
import type { ServerMessage, VehicleState, Unit } from '../types.js';
import { kphFromMph } from '../types.js';

interface Waypoint {
  lat: number;
  lng: number;
}

/**
 * A scripted loop drive used for development. It animates a car around a small
 * route, accelerating, cruising, and braking, while reporting consistent
 * speed / heading / position so the app UI behaves exactly as it would with a
 * real car. No Tesla account required.
 */
export class SimulatorSource implements VehicleSource {
  readonly name = 'simulator';

  private timer: ReturnType<typeof setInterval> | null = null;
  private segment = 0;
  private t = 0; // 0..1 progress along the current segment
  private speedMph = 0;
  private targetMph = 35;
  private battery = 82;

  // A loop around a few blocks (San Francisco). Heading is derived from motion.
  private readonly route: Waypoint[] = [
    { lat: 37.7766, lng: -122.4172 },
    { lat: 37.7793, lng: -122.4131 },
    { lat: 37.7821, lng: -122.4089 },
    { lat: 37.7848, lng: -122.4048 },
    { lat: 37.7861, lng: -122.4006 },
    { lat: 37.784, lng: -122.3964 },
    { lat: 37.7807, lng: -122.3983 },
    { lat: 37.7779, lng: -122.4039 },
    { lat: 37.7758, lng: -122.4101 },
  ];

  constructor(
    private readonly primaryUnit: Unit,
    private readonly intervalMs: number = 250,
  ) {}

  start(emit: (message: ServerMessage) => void): void {
    let lastPos = this.route[0];

    this.timer = setInterval(() => {
      // Occasionally pick a new target speed to mimic traffic.
      if (Math.random() < 0.02) {
        this.targetMph = 10 + Math.random() * 45;
      }

      // Ease current speed toward target (simple acceleration model).
      const accel = this.speedMph < this.targetMph ? 0.6 : -0.9;
      this.speedMph = clamp(this.speedMph + accel, 0, 80);

      // Advance along the route proportional to speed.
      const a = this.route[this.segment];
      const b = this.route[(this.segment + 1) % this.route.length];
      const segMeters = haversineMeters(a, b);
      const metersPerTick = (this.speedMph * 0.44704 * this.intervalMs) / 1000;
      this.t += segMeters > 0 ? metersPerTick / segMeters : 1;

      if (this.t >= 1) {
        this.t = 0;
        this.segment = (this.segment + 1) % this.route.length;
      }

      const pos = lerp(a, b, this.t);
      const heading = bearing(lastPos, pos);
      lastPos = pos;

      this.battery = Math.max(5, this.battery - 0.0008);

      const state: VehicleState = {
        type: 'vehicle_state',
        ts: Date.now(),
        speedMph: round(this.speedMph, 1),
        speedKph: round(kphFromMph(this.speedMph), 1),
        primaryUnit: this.primaryUnit,
        lat: round(pos.lat, 6),
        lng: round(pos.lng, 6),
        heading: round(heading, 1),
        shiftState: this.speedMph > 0.5 ? 'D' : 'P',
        power: round(this.speedMph * 0.9 - (accel < 0 ? 30 : 0), 1),
        batteryLevel: Math.round(this.battery),
        source: 'simulator',
        online: true,
      };
      emit(state);
    }, this.intervalMs);
  }

  stop(): void {
    if (this.timer) clearInterval(this.timer);
    this.timer = null;
  }
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(hi, Math.max(lo, v));
}

function round(v: number, decimals: number): number {
  const f = 10 ** decimals;
  return Math.round(v * f) / f;
}

function lerp(a: Waypoint, b: Waypoint, t: number): Waypoint {
  return { lat: a.lat + (b.lat - a.lat) * t, lng: a.lng + (b.lng - a.lng) * t };
}

function toRad(deg: number): number {
  return (deg * Math.PI) / 180;
}

function toDeg(rad: number): number {
  return (rad * 180) / Math.PI;
}

function haversineMeters(a: Waypoint, b: Waypoint): number {
  const R = 6371000;
  const dLat = toRad(b.lat - a.lat);
  const dLng = toRad(b.lng - a.lng);
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const h =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(lat1) * Math.cos(lat2) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(h));
}

function bearing(a: Waypoint, b: Waypoint): number {
  const lat1 = toRad(a.lat);
  const lat2 = toRad(b.lat);
  const dLng = toRad(b.lng - a.lng);
  const y = Math.sin(dLng) * Math.cos(lat2);
  const x =
    Math.cos(lat1) * Math.sin(lat2) -
    Math.sin(lat1) * Math.cos(lat2) * Math.cos(dLng);
  return (toDeg(Math.atan2(y, x)) + 360) % 360;
}
