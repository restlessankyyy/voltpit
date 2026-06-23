import { Router } from 'express';
import { readFile } from 'node:fs/promises';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

const __dirname = dirname(fileURLToPath(import.meta.url));
const PUBLIC_KEY_PATH = join(__dirname, '..', '..', 'keys', 'public-key.pem');

/**
 * Serves the EC public key Tesla requires at the well-known location during
 * partner registration:
 *   https://<domain>/.well-known/appspecific/com.tesla.3p.public-key.pem
 *
 * Generate the key pair with `npm run keys`. In production this domain must be
 * publicly reachable over HTTPS and match TESLA_APP_DOMAIN.
 */
export function wellKnownRoutes(): Router {
  const router = Router();

  router.get('/appspecific/com.tesla.3p.public-key.pem', async (_req, res) => {
    try {
      const pem = await readFile(PUBLIC_KEY_PATH, 'utf8');
      res.type('application/x-pem-file').send(pem);
    } catch {
      res
        .status(404)
        .send('public-key.pem not found. Run `npm run keys` to generate it.');
    }
  });

  return router;
}
