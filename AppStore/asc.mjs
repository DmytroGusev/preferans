import { readFileSync, writeFileSync } from 'node:fs';
import { createPrivateKey, sign } from 'node:crypto';

const keyID = process.env.ASC_KEY_ID || 'BQR53J468H';
const issuer = process.env.ASC_ISSUER_ID || '82681f77-3b09-484e-8c60-3851d2aceb19';
const keyPath = process.env.ASC_KEY_PATH;
function token() {
  if (!keyPath) throw new Error('Set ASC_KEY_PATH to your private key outside the repository.');
  const now = Math.floor(Date.now() / 1000);
  const encode = value => Buffer.from(JSON.stringify(value)).toString('base64url');
  const unsigned = `${encode({ alg: 'ES256', kid: keyID, typ: 'JWT' })}.${encode({ iss: issuer, iat: now, exp: now + 1200, aud: 'appstoreconnect-v1' })}`;
  return `${unsigned}.${sign('sha256', Buffer.from(unsigned), { key: createPrivateKey(readFileSync(keyPath)), dsaEncoding: 'ieee-p1363' }).toString('base64url')}`;
}
export async function asc(path, { method = 'GET', body } = {}) {
  if (!path.startsWith('/v1/') && !path.startsWith('/v2/')) throw new Error('Only App Store Connect API paths are allowed.');
  const response = await fetch(`https://api.appstoreconnect.apple.com${path}`, {
    method, headers: { Authorization: `Bearer ${token()}`, 'Content-Type': 'application/json' },
    body: body === undefined ? undefined : JSON.stringify(body),
    signal: AbortSignal.timeout(60000),
  });
  const text = await response.text();
  if (!response.ok) throw new Error(`${response.status} ${method} ${path}: ${text}`);
  return text ? JSON.parse(text) : {};
}
if (process.argv[1]?.endsWith('/asc.mjs')) {
  const [method, path, bodyFile, output] = process.argv.slice(2);
  const result = await asc(path, { method, body: bodyFile && bodyFile !== '-' ? JSON.parse(readFileSync(bodyFile, 'utf8')) : undefined });
  if (output) writeFileSync(output, JSON.stringify(result, null, 2));
  else console.log(JSON.stringify(result, null, 2));
}
