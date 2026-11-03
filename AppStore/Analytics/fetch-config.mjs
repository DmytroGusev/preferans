import fs from 'node:fs';
import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { google } from './google.mjs';

const app = 'projects/guru-preferans-20261030/iosApps/1:333127048917:ios:07fabd60aff528315f4c5c';
const config = await google(`https://firebase.googleapis.com/v1beta1/${app}/config`);
const bytes = Buffer.from(config.configFileContents, 'base64');
const data = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', '-'], { input: bytes, encoding: 'utf8' }));
assert.equal(data.BUNDLE_ID, 'com.mixandmatch.preferans');
assert.equal(data.PROJECT_ID, 'guru-preferans-20261030');
assert.equal(data.GOOGLE_APP_ID, '1:333127048917:ios:07fabd60aff528315f4c5c');
assert(data.API_KEY);
fs.writeFileSync(new URL('../../Preferans/Resources/GoogleService-Info.plist', import.meta.url), bytes, { mode: 0o600 });
console.log('Fetched verified Preferans iOS configuration into its gitignored resource file; no key printed.');
