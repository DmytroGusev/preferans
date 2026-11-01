import fs from 'node:fs';
import os from 'node:os';
import { createHash } from 'node:crypto';
import { spawnSync } from 'node:child_process';
import assert from 'node:assert/strict';

const account = 'df302a84563143eb92fc75a7277079ec';
const source = 'c4621082a8a36c3cffdbf58d1f7a01faff64cefa';
const directory = '/private/tmp/preferans-owner-image30';
const regctl = '/private/tmp/preferans-regctl/regctl-darwin-arm64';
const hash = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');
assert.equal(hash(regctl), '8ac077a1eeb834d3053714e86ccbd838d0da46567df8cd7c2695d1a19135bf60');
assert.equal(fs.readFileSync(`${directory}/source-commit.txt`, 'utf8').trim(), source);
const archiveHash = fs.readFileSync(`${directory}/SHA256SUMS`, 'utf8').split(/\s+/)[0];
assert.equal(hash(`${directory}/preferans-engine-linux-amd64.tar.gz`), archiveHash);
const target = `registry.cloudflare.com/${account}/preferans-engine:main-${source.slice(0, 12)}`;
if (!process.argv.includes('--push')) {
  console.log(JSON.stringify({ verified: true, source, target, archiveHash }));
  process.exit(0);
}

process.umask(0o077);
const config = fs.mkdtempSync('/private/tmp/preferans30-registry-auth-');
const token = process.env.CLOUDFLARE_API_TOKEN ?? fs.readFileSync(
  `${os.homedir()}/Library/Preferences/.wrangler/config/default.toml`, 'utf8'
).match(/^oauth_token\s*=\s*"([^"\r\n]+)"/m)?.[1];
assert(token, 'Authorize Wrangler first');
try {
  const response = await fetch(`https://api.cloudflare.com/client/v4/accounts/${account}/containers/registries/registry.cloudflare.com/credentials`, {
    method: 'POST', headers: { authorization: `Bearer ${token}`, 'content-type': 'application/json' },
    body: JSON.stringify({ expiration_minutes: 15, permissions: ['push', 'pull'] }),
    signal: AbortSignal.timeout(15000)
  });
  const body = await response.json();
  assert(response.ok && body.success, `Registry authorization failed (${response.status})`);
  const credentials = body.result;
  assert.equal(credentials.account_id, account);
  assert.equal(credentials.registry_host, 'registry.cloudflare.com');
  const env = { ...process.env, REGCTL_CONFIG: `${config}/config.json` };
  const run = (args, input) => {
    const result = spawnSync(regctl, args, { env, input, encoding: 'utf8', maxBuffer: 1024 * 1024, timeout: 180000 });
    assert.equal(result.status, 0, `Registry ${args[0]} command failed`);
    return result.stdout.trim();
  };
  run(['registry', 'login', 'registry.cloudflare.com', '--user', credentials.username, '--pass-stdin'], credentials.password);
  run(['image', 'import', target, `${directory}/preferans-engine-linux-amd64.tar`]);
  const digest = run(['image', 'digest', target]);
  assert.match(digest, /^sha256:[a-f0-9]{64}$/);
  const result = { source, ciRun: '41339653980', target, digest, archiveHash };
  fs.writeFileSync(new URL('./image-publication.json', import.meta.url), JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result));
} finally {
  fs.rmSync(config, { recursive: true, force: true });
}
