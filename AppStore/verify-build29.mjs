import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const ipa = path.resolve('build/export29/Preferans.ipa');
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'preferans29-verify-'));
try {
  execFileSync('unzip', ['-q', ipa, '-d', temp]);
  const app = path.join(temp, 'Payload/Preferans.app');
  const plist = file => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' }));
  const info = plist(path.join(app, 'Info.plist'));
  assert.equal(info.CFBundleIdentifier, 'com.mixandmatch.preferans');
  assert.equal(info.CFBundleShortVersionString, '1.0.3');
  assert.equal(info.CFBundleVersion, '29');
  assert.equal(info.DTXcodeBuild, '27A9275');
  assert(info.CFBundleURLTypes.some(x => x.CFBundleURLSchemes.includes('com.mixandmatch.preferans')));
  execFileSync('codesign', ['--verify', '--deep', '--strict', app]);
  const xml = execFileSync('codesign', ['-d', '--entitlements', ':-', app], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const entitlements = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', '-'], { input: xml, encoding: 'utf8' }));
  assert.equal(entitlements['application-identifier'], '3WSQ6X9CDT.com.mixandmatch.preferans');
  assert.equal(entitlements['get-task-allow'], false);
  assert(entitlements['com.apple.developer.applesignin'].includes('Default'));
  assert(entitlements['com.apple.developer.associated-domains'].includes('applinks:preferans-room-worker.dmytro-gusev.workers.dev'));
  const binary = fs.readFileSync(path.join(app, 'Preferans'));
  assert(binary.includes(Buffer.from('https://preferans-room-worker.dmytro-gusev.workers.dev')));
  assert(binary.includes(Buffer.from('.owner-v1')));
  assert(binary.includes(Buffer.from('https://guruofcards.com/apps/preferans/privacy/')));
  assert(!binary.includes(Buffer.from('preferans.club.monthly')));
  const result = {
    version: info.CFBundleShortVersionString, build: info.CFBundleVersion,
    xcode: info.DTXcodeBuild, sdk: info.DTSDKName,
    ipa: path.relative(process.cwd(), ipa), bytes: fs.statSync(ipa).size,
    sha256: createHash('sha256').update(fs.readFileSync(ipa)).digest('hex'),
    signatureVerified: true, appleSignIn: true, ownerDomain: true,
    backend: 'https://preferans-room-worker.dmytro-gusev.workers.dev',
    storageNamespace: '.owner-v1', subscriptionDraftExcluded: true
  };
  fs.writeFileSync('AppStore/Release29/package-verification.json', JSON.stringify(result, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
