import type { WebSocket } from 'ws';
import type { ServerMessage } from './types.js';

/**
 * Tracks connected app clients and broadcasts the latest vehicle state to all
 * of them. New clients immediately receive the last known state so the UI is
 * never blank on connect.
 */
export class WsHub {
  private clients = new Set<WebSocket>();
  private last: ServerMessage | null = null;

  add(socket: WebSocket): void {
    this.clients.add(socket);
    if (this.last) {
      this.sendTo(socket, this.last);
    }
    socket.on('close', () => this.clients.delete(socket));
    socket.on('error', () => this.clients.delete(socket));
  }

  get clientCount(): number {
    return this.clients.size;
  }

  broadcast(message: ServerMessage): void {
    if (message.type === 'vehicle_state') {
      this.last = message;
    }
    const payload = JSON.stringify(message);
    for (const socket of this.clients) {
      if (socket.readyState === socket.OPEN) {
        socket.send(payload);
      }
    }
  }

  private sendTo(socket: WebSocket, message: ServerMessage): void {
    if (socket.readyState === socket.OPEN) {
      socket.send(JSON.stringify(message));
    }
  }
}
