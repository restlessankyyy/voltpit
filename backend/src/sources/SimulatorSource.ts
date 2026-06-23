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

  // A real driving loop through Kungsholmen, Stockholm, road-snapped via the
  // OSRM routing engine so every waypoint sits exactly on the street network.
  // Heading is derived from motion; the dense point spacing keeps the
  // straight-line interpolation hugging the actual roads instead of cutting
  // across blocks.
  private readonly route: Waypoint[] = [
    { lat: 59.332886, lng: 18.029528 },
    { lat: 59.332911, lng: 18.029421 },
    { lat: 59.333366, lng: 18.029718 },
    { lat: 59.333816, lng: 18.027946 },
    { lat: 59.333857, lng: 18.027621 },
    { lat: 59.333941, lng: 18.027829 },
    { lat: 59.334627, lng: 18.028234 },
    { lat: 59.334674, lng: 18.030906 },
    { lat: 59.334501, lng: 18.032073 },
    { lat: 59.33448, lng: 18.032249 },
    { lat: 59.334438, lng: 18.032571 },
    { lat: 59.33425, lng: 18.033999 },
    { lat: 59.334222, lng: 18.034217 },
    { lat: 59.334167, lng: 18.034649 },
    { lat: 59.334045, lng: 18.035576 },
    { lat: 59.334178, lng: 18.035646 },
    { lat: 59.335868, lng: 18.036487 },
    { lat: 59.33641, lng: 18.036753 },
    { lat: 59.336095, lng: 18.038496 },
    { lat: 59.335871, lng: 18.039536 },
    { lat: 59.336095, lng: 18.038496 },
    { lat: 59.33641, lng: 18.036753 },
    { lat: 59.335868, lng: 18.036487 },
    { lat: 59.334178, lng: 18.035646 },
    { lat: 59.334045, lng: 18.035576 },
    { lat: 59.33374, lng: 18.037922 },
    { lat: 59.333701, lng: 18.038228 },
    { lat: 59.333546, lng: 18.039415 },
    { lat: 59.333327, lng: 18.041095 },
    { lat: 59.333031, lng: 18.043382 },
    { lat: 59.332847, lng: 18.044821 },
    { lat: 59.332791, lng: 18.045256 },
    { lat: 59.332615, lng: 18.045202 },
    { lat: 59.331531, lng: 18.044551 },
    { lat: 59.3309, lng: 18.044183 },
    { lat: 59.330418, lng: 18.043943 },
    { lat: 59.329984, lng: 18.043713 },
    { lat: 59.329803, lng: 18.043617 },
    { lat: 59.329075, lng: 18.043218 },
    { lat: 59.329018, lng: 18.043057 },
    { lat: 59.329062, lng: 18.042725 },
    { lat: 59.329235, lng: 18.041428 },
    { lat: 59.32937, lng: 18.040408 },
    { lat: 59.329499, lng: 18.039452 },
    { lat: 59.329685, lng: 18.03808 },
    { lat: 59.329766, lng: 18.037499 },
    { lat: 59.32994, lng: 18.036324 },
    { lat: 59.330307, lng: 18.034694 },
    { lat: 59.330678, lng: 18.032906 },
    { lat: 59.330754, lng: 18.032501 },
    { lat: 59.331082, lng: 18.031082 },
    { lat: 59.331159, lng: 18.030781 },
    { lat: 59.331749, lng: 18.031086 },
    { lat: 59.331926, lng: 18.031186 },
    { lat: 59.332074, lng: 18.031272 },
    { lat: 59.332224, lng: 18.031211 },
    { lat: 59.332169, lng: 18.030796 },
    { lat: 59.332108, lng: 18.028968 },
    { lat: 59.332107, lng: 18.028808 },
    { lat: 59.332236, lng: 18.02867 },
    { lat: 59.332911, lng: 18.029421 },
    { lat: 59.332886, lng: 18.029528 },
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
