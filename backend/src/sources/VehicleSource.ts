import type { ServerMessage } from '../types.js';

/** A source produces a stream of messages via the provided emit callback. */
export interface VehicleSource {
  readonly name: string;
  start(emit: (message: ServerMessage) => void): Promise<void> | void;
  stop(): Promise<void> | void;
}
