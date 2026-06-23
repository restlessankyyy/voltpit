import { readFile, writeFile } from 'node:fs/promises';

export interface StoredTokens {
  accessToken: string;
  refreshToken: string;
  /** Unix epoch ms when the access token expires. */
  expiresAt: number;
  scope?: string;
}

/**
 * Minimal on-disk token cache. For a single-user personal app this is fine; a
 * multi-user deployment should swap this for a database.
 */
export class TokenStore {
  private cache: StoredTokens | null = null;

  constructor(private readonly path: string) {}

  async load(): Promise<StoredTokens | null> {
    if (this.cache) return this.cache;
    try {
      const raw = await readFile(this.path, 'utf8');
      this.cache = JSON.parse(raw) as StoredTokens;
      return this.cache;
    } catch {
      return null;
    }
  }

  async save(tokens: StoredTokens): Promise<void> {
    this.cache = tokens;
    await writeFile(this.path, JSON.stringify(tokens, null, 2), 'utf8');
  }

  async clear(): Promise<void> {
    this.cache = null;
    await writeFile(this.path, '{}', 'utf8').catch(() => undefined);
  }
}
