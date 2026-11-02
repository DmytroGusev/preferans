import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const arg = name => process.argv[process.argv.indexOf(name) + 1];
assert(process.argv.includes('--source') && /^[0-9a-f]{40}$/.test(arg('--source')));
assert(process.argv.includes('--ipa'));
const sourceCommit = arg('--source');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const files = execFileSync('git', ['ls-tree', '-r', '--name-only', sourceCommit], { encoding: 'utf8' }).trim().split('\n')
  .filter(file => file.startsWith('Preferans/') || file.startsWith('Sources/PreferansEngine/') || ['Preferans.xcodeproj/project.pbxproj', 'Package.swift'].includes(file));
const manifest = files.map(file => {
  const bytes = fs.readFileSync(file);
  assert.equal(hash(bytes), hash(execFileSync('git', ['show', `${sourceCommit}:${file}`])), `Source drift: ${file}`);
  return { path: file, sha256: hash(bytes) };
});
const ipa = path.resolve(arg('--ipa'));
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'preferans32-verify-'));
const plist = file => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' }));
try {
  execFileSync('unzip', ['-q', ipa, '-d', temp]);
  const app = path.join(temp, 'Payload/Preferans.app');
  const info = plist(path.join(app, 'Info.plist'));
  assert.equal(info.CFBundleIdentifier, 'com.mixandmatch.preferans');
  assert.equal(info.CFBundleVersion, '32');
  assert.equal(info.CFBundleShortVersionString, '1.0.3');
  assert.equal(info.DTXcodeBuild, '27A9275');
  assert.equal(info.ITSAppUsesNonExemptEncryption, false);
  assert.equal(info.NSUserTrackingUsageDescription, undefined);
  assert(info.CFBundleURLTypes.some(type => type.CFBundleURLSchemes.includes('com.mixandmatch.preferans')));
  execFileSync('codesign', ['--verify', '--deep', '--strict', app]);
  const xml = execFileSync('codesign', ['-d', '--entitlements', ':-', app], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const entitlements = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', '-'], { input: xml, encoding: 'utf8' }));
  assert.equal(entitlements['application-identifier'], '3WSQ6X9CDT.com.mixandmatch.preferans');
  assert.equal(entitlements['get-task-allow'], false);
  assert(entitlements['com.apple.developer.applesignin'].includes('Default'));
  assert(entitlements['com.apple.developer.associated-domains'].includes('applinks:preferans-room-worker.dmytro-gusev.workers.dev'));
  const binaryPath = path.join(app, 'Preferans');
  const binary = fs.readFileSync(binaryPath);
  const libraries = execFileSync('otool', ['-L', binaryPath], { encoding: 'utf8' });
  assert(!/AppTrackingTransparency|AdSupport/.test(libraries));
  for (const text of ['ATTrackingManager', 'ASIdentifierManager', 'requestTrackingAuthorization', 'preferans.club.monthly']) assert(!binary.includes(Buffer.from(text)), text);
  for (const text of ['https://preferans-room-worker.dmytro-gusev.workers.dev', '.owner-v1', 'https://guruofcards.com/apps/preferans/club/', 'settings.clubInfo', 'seats/bot']) assert(binary.includes(Buffer.from(text)), text);
  const result = { sourceCommit, version: '1.0.3', build: '32', xcode: info.DTXcodeBuild, sdk: info.DTSDKName,
    bytes: fs.statSync(ipa).size, sha256: hash(fs.readFileSync(ipa)), signatureVerified: true,
    ownerBackendAndNamespacePreserved: true, appleSignInAndInvitesPreserved: true,
    onlineBotSeatRouteIncluded: true, clubInformationLinkIncluded: true,
    trackingUsageAndAPIsAbsent: true, subscriptionPurchasesIncluded: false };
  fs.writeFileSync(new URL('package-verification.json', import.meta.url), JSON.stringify(result, null, 2) + '\n');
  fs.writeFileSync(new URL('source-manifest.json', import.meta.url), JSON.stringify({ sourceCommit, files: manifest }, null, 2) + '\n');
  console.log(JSON.stringify(result, null, 2));
} finally { fs.rmSync(temp, { recursive: true, force: true }); }
