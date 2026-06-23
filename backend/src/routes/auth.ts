import { Router } from 'express';
import { randomBytes } from 'node:crypto';
import type { TeslaOAuth } from '../tesla/oauth.js';

/**
 * Browser-based OAuth routes. Visit /auth/login once to connect your Tesla
 * account; Tesla redirects back to /auth/callback where we store the tokens.
 */
export function authRoutes(oauth: TeslaOAuth): Router {
  const router = Router();
  const pendingStates = new Set<string>();

  router.get('/login', (_req, res) => {
    const state = randomBytes(16).toString('hex');
    pendingStates.add(state);
    res.redirect(oauth.authorizeUrl(state));
  });

  router.get('/callback', async (req, res) => {
    const { code, state } = req.query as { code?: string; state?: string };
    if (!code || !state || !pendingStates.has(state)) {
      res.status(400).send('Invalid or expired OAuth state. Try /auth/login again.');
      return;
    }
    pendingStates.delete(state);
    try {
      await oauth.exchangeCode(code);
      res.send(
        '<h2>Tesla connected ✅</h2><p>You can close this tab and open the app.</p>',
      );
    } catch (err) {
      const msg = err instanceof Error ? err.message : String(err);
      res.status(500).send(`Token exchange failed: ${msg}`);
    }
  });

  return router;
}
