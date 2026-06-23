import { generateKeyPairSync } from 'node:crypto';
import { mkdirSync, writeFileSync, existsSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { dirname, join } from 'node:path';

/**
 * Generates the EC (prime256v1 / P-256) key pair Tesla requires for Fleet API
 * domain registration and vehicle command signing. Equivalent to:
 *   openssl ecparam -name prime256v1 -genkey -noout -out private-key.pem
 *   openssl ec -in private-key.pem -pubout -out public-key.pem
 *
 * The public key is later hosted at:
 *   https://<domain>/.well-known/appspecific/com.tesla.3p.public-key.pem
 */
const __dirname = dirname(fileURLToPath(import.meta.url));
const keysDir = join(__dirname, '..', '..', 'keys');
const privatePath = join(keysDir, 'private-key.pem');
const publicPath = join(keysDir, 'public-key.pem');

if (existsSync(privatePath)) {
  console.log(`Keys already exist at ${keysDir}. Delete them first to regenerate.`);
  process.exit(0);
}

mkdirSync(keysDir, { recursive: true });

const { privateKey, publicKey } = generateKeyPairSync('ec', {
  namedCurve: 'prime256v1',
  publicKeyEncoding: { type: 'spki', format: 'pem' },
  privateKeyEncoding: { type: 'pkcs8', format: 'pem' },
});

writeFileSync(privatePath, privateKey, { mode: 0o600 });
writeFileSync(publicPath, publicKey);

console.log(`✅ Wrote:\n  ${privatePath} (keep secret!)\n  ${publicPath} (host publicly)`);
