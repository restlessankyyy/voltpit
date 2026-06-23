import { config } from '../config.js';
import { TokenStore, type StoredTokens } from './tokenStore.js';

const AUTH_BASE = 'https://auth.tesla.com/oauth2/v3';

/**
 * Implements the Tesla OAuth 2.0 Authorization Code flow used by Fleet API.
 * Docs: https://developer.tesla.com/docs/fleet-api/authentication/overview
 */
export class TeslaOAuth {
  constructor(private readonly store: TokenStore) {}

  /** URL to send the user to in order to grant access. */
  authorizeUrl(state: string): string {
    const params = new URLSearchParams({
      response_type: 'code',
      client_id: config.tesla.clientId,
      redirect_uri: config.tesla.redirectUri,
      scope: config.tesla.scopes,
      state,
    });
    return `${AUTH_BASE}/authorize?${params.toString()}`;
  }

  /** Exchanges an authorization code for tokens and persists them. */
  async exchangeCode(code: string): Promise<StoredTokens> {
    const body = new URLSearchParams({
      grant_type: 'authorization_code',
      client_id: config.tesla.clientId,
      client_secret: config.tesla.clientSecret,
      code,
      redirect_uri: config.tesla.redirectUri,
    });
    const tokens = await this.postToken(body);
    await this.store.save(tokens);
    return tokens;
  }

  /**
   * Returns a valid access token, refreshing it if it expires within 60s.
   * Throws if the user has never authorized (run /auth/login first).
   */
  async getAccessToken(): Promise<string> {
    const tokens = await this.store.load();
    if (!tokens?.refreshToken) {
      throw new Error('Not authorized yet. Visit /auth/login to connect Tesla.');
    }
    if (tokens.expiresAt - Date.now() > 60_000) {
      return tokens.accessToken;
    }
    const refreshed = await this.refresh(tokens.refreshToken);
    await this.store.save(refreshed);
    return refreshed.accessToken;
  }

  /** A partner (client_credentials) token, used for registration only. */
  async getPartnerToken(): Promise<string> {
    const body = new URLSearchParams({
      grant_type: 'client_credentials',
      client_id: config.tesla.clientId,
      client_secret: config.tesla.clientSecret,
      scope: config.tesla.scopes,
      audience: config.tesla.fleetBaseUrl,
    });
    const tokens = await this.postToken(body, /* persist */ false);
    return tokens.accessToken;
  }

  private async refresh(refreshToken: string): Promise<StoredTokens> {
    const body = new URLSearchParams({
      grant_type: 'refresh_token',
      client_id: config.tesla.clientId,
      refresh_token: refreshToken,
    });
    return this.postToken(body);
  }

  private async postToken(
    body: URLSearchParams,
    _persist = true,
  ): Promise<StoredTokens> {
    const res = await fetch(`${AUTH_BASE}/token`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
      body,
    });
    if (!res.ok) {
      const text = await res.text();
      throw new Error(`Tesla token request failed (${res.status}): ${text}`);
    }
    const json = (await res.json()) as {
      access_token: string;
      refresh_token?: string;
      expires_in: number;
      scope?: string;
    };
    return {
      accessToken: json.access_token,
      // client_credentials responses have no refresh token; keep the old one.
      refreshToken: json.refresh_token ?? '',
      expiresAt: Date.now() + json.expires_in * 1000,
      scope: json.scope,
    };
  }
}
