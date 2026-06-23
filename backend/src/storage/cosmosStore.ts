import { Agent } from 'node:https';

import { CosmosClient, type Container } from '@azure/cosmos';
import { DefaultAzureCredential } from '@azure/identity';

import { config } from '../config.js';
import type { ServerMessage } from '../types.js';

/**
 * Persists streamed events to Azure Cosmos DB (serverless) with a per-document
 * TTL so they auto-expire after `config.cosmos.ttlSeconds` (30 days by default).
 *
 * Writes are best-effort and fire-and-forget: a Cosmos hiccup must never break
 * the live WebSocket stream, so failures are logged and swallowed.
 */
export class CosmosEventStore {
  private container: Container | null = null;

  /** True only when a Cosmos endpoint is configured. */
  get enabled(): boolean {
    return config.cosmos.endpoint !== '';
  }

  /**
   * Connects to the event store. Two modes:
   *
   * - Production (managed identity, no `COSMOS_KEY`): connects to the existing
   *   database + container provisioned by Terraform. They are NOT created here
   *   on purpose, because the app's managed identity holds a least-privilege,
   *   write-only data-plane role that cannot create databases or containers.
   *
   * - Local dev (`COSMOS_KEY` set, e.g. the Cosmos DB Emulator): creates the
   *   database + container if missing so you can test persistence end to end
   *   without provisioning anything. The emulator's self-signed TLS cert is
   *   trusted only for this client.
   *
   * No-ops when persistence is disabled.
   */
  async init(): Promise<void> {
    if (!this.enabled) {
      console.log('  cosmos:    disabled (no COSMOS_ENDPOINT)');
      return;
    }

    const days = Math.round(config.cosmos.ttlSeconds / 86400);

    if (config.cosmos.key) {
      // Local dev / emulator: key auth, accept the emulator's self-signed cert,
      // and create the database + container on demand.
      const client = new CosmosClient({
        endpoint: config.cosmos.endpoint,
        key: config.cosmos.key,
        agent: new Agent({ rejectUnauthorized: false }),
      });

      const { database } = await client.databases.createIfNotExists({
        id: config.cosmos.database,
      });
      const { container } = await database.containers.createIfNotExists({
        id: config.cosmos.container,
        partitionKey: { paths: ['/vin'] },
        defaultTtl: config.cosmos.ttlSeconds,
      });
      this.container = container;

      console.log(
        `  cosmos:    ${config.cosmos.database}/${config.cosmos.container} (local, TTL ${days}d)`,
      );
      return;
    }

    // Production: managed identity, connect to existing resources only.
    const client = new CosmosClient({
      endpoint: config.cosmos.endpoint,
      aadCredentials: new DefaultAzureCredential(),
    });

    this.container = client
      .database(config.cosmos.database)
      .container(config.cosmos.container);

    console.log(
      `  cosmos:    ${config.cosmos.database}/${config.cosmos.container} (TTL ${days}d)`,
    );
  }

  /**
   * Writes one event document. Best-effort: never throws. The `ttl` field lets
   * Cosmos expire the row even if the container default ever changes.
   */
  save(message: ServerMessage, vin: string): void {
    if (!this.container) return;
    const doc = {
      ...message,
      vin,
      ttl: config.cosmos.ttlSeconds,
    };
    this.container.items.create(doc).catch((err: unknown) => {
      console.warn('cosmos write failed:', err instanceof Error ? err.message : err);
    });
  }
}
