import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import assert from 'node:assert/strict';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { inspectApp, assertNonTracking } from '../../bin/audit-privacy-package.mjs';

const [ipa, source] = process.argv.slice(2);
assert(ipa && /^[0-9a-f]{40}$/.test(source ?? ''), 'Usage: node record-package.mjs IPA SOURCE_COMMIT');
const hash = bytes => createHash('sha256').update(bytes).digest('hex');
const tracked = execFileSync('git', ['ls-tree', '-r', '--name-only', source], { encoding: 'utf8' }).trim().split('\n')
  .filter(file => file.startsWith('Preferans/') || file.startsWith('Sources/PreferansEngine/') || ['Preferans.xcodeproj/project.pbxproj', 'Package.swift', 'Package.resolved'].includes(file));
const files = tracked.map(file => {
  const sha256 = hash(fs.readFileSync(file));
  assert.equal(sha256, hash(execFileSync('git', ['show', `${source}:${file}`], { maxBuffer: 16 * 1024 * 1024 })), `Source drift: ${file}`);
  return { path: file, sha256 };
});
const temp = fs.mkdtempSync(path.join(os.tmpdir(), 'preferans33-package-'));
const save = (name, value) => fs.writeFileSync(new URL(name, import.meta.url), JSON.stringify(value, null, 2) + '\n');
try {
  execFileSync('unzip', ['-q', path.resolve(ipa), '-d', temp]);
  const app = path.join(temp, 'Payload/Preferans.app');
  const report = inspectApp(app);
  assertNonTracking(report, { requireManifest: true });
  assert.equal(report.bundleID, 'com.mixandmatch.preferans');
  assert.equal(report.version, '1.0.3');
  assert.equal(report.build, '33');
  assert.equal(report.xcode, '27A9275');
  const xml = execFileSync('codesign', ['-d', '--entitlements', ':-', app], { encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] });
  const entitlements = JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', '-'], { input: xml, encoding: 'utf8' }));
  assert.equal(entitlements['application-identifier'], '3WSQ6X9CDT.com.mixandmatch.preferans');
  assert.equal(entitlements['get-task-allow'], false);
  assert(entitlements['com.apple.developer.applesignin'].includes('Default'));
  assert(entitlements['com.apple.developer.associated-domains'].includes('applinks:preferans-room-worker.dmytro-gusev.workers.dev'));
  const binary = fs.readFileSync(path.join(app, 'Preferans'));
  for (const required of ['https://preferans-room-worker.dmytro-gusev.workers.dev', '.owner-v1', 'BotSeatMutationRequest', 'https://guruofcards.com/apps/preferans/club/']) assert(binary.includes(Buffer.from(required)), required);
  assert(!binary.includes(Buffer.from('preferans.club.monthly')));
  const manifest = report.plists.find(x => x.path === 'PrivacyInfo.xcprivacy');
  assert.equal(manifest.sha256, hash(fs.readFileSync('Preferans/PrivacyInfo.xcprivacy')));
  assert.equal(manifest.manifest.NSPrivacyCollectedDataTypes.length, 5);
  for (const item of manifest.manifest.NSPrivacyCollectedDataTypes) {
    assert.equal(item.NSPrivacyCollectedDataTypeTracking, false);
    assert.equal(item.NSPrivacyCollectedDataTypeLinked, true);
    assert.deepEqual(item.NSPrivacyCollectedDataTypePurposes, ['NSPrivacyCollectedDataTypePurposeAppFunctionality']);
  }
  const receipt = { checkedAt: new Date().toISOString(), sourceCommit: source, version: report.version, build: report.build, xcode: report.xcode,
    bytes: fs.statSync(ipa).size, sha256: hash(fs.readFileSync(ipa)), signatureVerified: true,
    nonTrackingGuardPassed: true, manifestInMainBundle: true, manifestSHA256: manifest.sha256,
    accountGameplayAndDiagnosticDisclosuresPreserved: true, localUserDefaultsReason: 'CA92.1',
    appleSignInAndInvitesPreserved: true, ownerBackendAndNamespacePreserved: true, onlineBotControlsPreserved: true,
    subscriptionsActivated: false, serverDeployed: false };
  save('./source-manifest.json', { sourceCommit: source, files });
  save('./package-audit.json', report);
  save('./package-verification.json', receipt);
  console.log(JSON.stringify(receipt, null, 2));
} finally {
  fs.rmSync(temp, { recursive: true, force: true });
}
