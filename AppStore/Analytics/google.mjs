import { execFileSync } from 'node:child_process';

export async function google(url, { method = 'GET', body } = {}) {
  const target = new URL(url);
  if (target.protocol !== 'https:' || !['firebase.googleapis.com', 'analyticsadmin.googleapis.com', 'analyticsdata.googleapis.com'].includes(target.hostname)) throw new Error('Unexpected Google API destination');
  const token = execFileSync('/opt/homebrew/bin/gcloud', ['auth', 'print-access-token'], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] }).trim();
  const response = await fetch(url, { method, headers: { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json', 'x-goog-user-project': 'guru-preferans-20261030' }, body: body === undefined ? undefined : JSON.stringify(body), signal: AbortSignal.timeout(30000) });
  const text = await response.text();
  if (!response.ok) throw new Error(`${response.status} ${target.hostname}${target.pathname}: ${text}`);
  return text ? JSON.parse(text) : {};
}
