import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';

const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const plist = file => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' }));
const project = fs.readFileSync('Preferans.xcodeproj/project.pbxproj', 'utf8');
assert(!project.includes('NSUserTrackingUsageDescription'));
assert(!project.includes('TrackingPermissionCenter.swift'));
const sourceFiles = fs.readdirSync('Preferans', { recursive: true })
  .filter(file => file.endsWith('.swift')).map(file => path.join('Preferans', file)).sort();
for (const file of sourceFiles) {
  const source = fs.readFileSync(file, 'utf8');
  assert(!/TrackingPermissionCenter|ATTrackingManager|ASIdentifierManager|import AppTrackingTransparency|import AdSupport/.test(source), file);
}
assert.equal(plist('Preferans/Info.plist').NSUserTrackingUsageDescription, undefined);
const sourceManifest = {
  parent: execFileSync('git', ['rev-parse', 'HEAD'], { encoding: 'utf8' }).trim(),
  baseline: 'c4621082a8a36c3cffdbf58d1f7a01faff64cefa',
  files: [...sourceFiles, 'Preferans/Info.plist', 'Preferans.xcodeproj/project.pbxproj'].map(file => ({ path: file, sha256: hash(fs.readFileSync(file)) })),
};
fs.writeFileSync(new URL('./source-manifest.json', import.meta.url), JSON.stringify(sourceManifest, null, 2) + '\n');
console.log('Source privacy guard passed: no ATT request or IDFA access.');

const ipaIndex = process.argv.indexOf('--ipa');
if (ipaIndex >= 0) {
  const ipa = path.resolve(process.argv[ipaIndex + 1]);
  const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'preferans31-verify-'));
  try {
    execFileSync('unzip', ['-q', ipa, '-d', temp]);
    const app = path.join(temp, 'Payload/Preferans.app');
    const info = plist(path.join(app, 'Info.plist'));
    assert.equal(info.CFBundleIdentifier, 'com.mixandmatch.preferans');
    assert.equal(info.CFBundleVersion, '31');
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
    for (const forbidden of ['ATTrackingManager', 'ASIdentifierManager', 'requestTrackingAuthorization']) {
      assert(!binary.includes(Buffer.from(forbidden)), forbidden);
    }
    for (const required of ['https://preferans-room-worker.dmytro-gusev.workers.dev', '.owner-v1', 'https://guruofcards.com/apps/preferans/privacy/', "Your move hasn't been confirmed yet. Still trying"]) {
      assert(binary.includes(Buffer.from(required)), required);
    }
    assert(!binary.includes(Buffer.from('preferans.club.monthly')));
    const result = {
      version: info.CFBundleShortVersionString, build: info.CFBundleVersion,
      xcode: info.DTXcodeBuild, sdk: info.DTSDKName,
      bytes: fs.statSync(ipa).size, sha256: hash(fs.readFileSync(ipa)),
      signatureVerified: true, trackingUsageDescriptionAbsent: true,
      trackingFrameworksAbsent: true, trackingRequestAndIDFAAbsent: true,
      ownerBackendPreserved: true, appleSignInPreserved: true, inviteSchemePreserved: true,
      serverDeployed: false, onlineBotSeatsIncluded: false,
    };
    fs.writeFileSync(new URL('./package-verification.json', import.meta.url), JSON.stringify(result, null, 2) + '\n');
    console.log(JSON.stringify(result, null, 2));
  } finally {
    fs.rmSync(temp, { recursive: true, force: true });
  }
}
