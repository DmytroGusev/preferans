import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { execFileSync } from 'node:child_process';
import { test } from 'node:test';
import { inspectApp, assertNonTracking } from './audit-privacy-package.mjs';

const plist = file => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' }));
const clean = () => ({ plists: [], binaries: [], manifestPresent: false });

test('legacy non-tracking package passes, but future packages require a manifest', () => {
  assertNonTracking(clean());
  assert.throws(() => assertNonTracking(clean(), { requireManifest: true }), /Missing app/);
});

test('rejects a localized tracking permission, even an empty value', () => {
  const report = clean();
  report.plists.push({ path: 'uk.lproj/InfoPlist.strings', trackingKeys: [{ key: 'NSUserTrackingUsageDescription', value: '' }] });
  assert.throws(() => assertNonTracking(report), /tracking permission key/);
});

test('rejects SDK tracking declarations and domains', () => {
  for (const [key, value] of [['NSPrivacyTracking', true], ['NSPrivacyTrackingDomains', ['ads.example.invalid']], ['NSPrivacyCollectedDataTypes.0.NSPrivacyCollectedDataTypeTracking', true]]) {
    const report = clean();
    report.plists.push({ path: 'SDK.bundle/PrivacyInfo.xcprivacy', trackingKeys: [{ key, value }] });
    assert.throws(() => assertNonTracking(report));
  }
});

test('rejects ATT APIs or analytics linkage in a nested executable', () => {
  for (const [trackingAPIs, trackingOrAnalyticsLibraries] of [[['ATTrackingManager'], []], [[], ['AdSupport.framework/AdSupport']]]) {
    const report = clean();
    report.binaries.push({ path: 'PlugIns/Test.appex/Test', trackingAPIs, trackingOrAnalyticsLibraries });
    assert.throws(() => assertNonTracking(report));
  }
});

test('actual manifest preserves functionality disclosures and adds truthful opt-in analytics types', () => {
  const manifest = plist(new URL('../Preferans/PrivacyInfo.xcprivacy', import.meta.url).pathname);
  const report = clean();
  report.manifestPresent = true;
  report.plists.push({ path: 'PrivacyInfo.xcprivacy', manifest, trackingKeys: [{ key: 'NSPrivacyTracking', value: manifest.NSPrivacyTracking }] });
  assertNonTracking(report, { requireManifest: true });
  assert.deepEqual(manifest.NSPrivacyTrackingDomains, []);
  assert.deepEqual(manifest.NSPrivacyCollectedDataTypes.map(x => x.NSPrivacyCollectedDataType).sort(), ['Name', 'UserID', 'GameplayContent', 'ProductInteraction', 'OtherDiagnosticData', 'DeviceID', 'CoarseLocation'].map(x => `NSPrivacyCollectedDataType${x}`).sort());
  for (const item of manifest.NSPrivacyCollectedDataTypes) {
    assert.equal(item.NSPrivacyCollectedDataTypeLinked, true);
    assert.equal(item.NSPrivacyCollectedDataTypeTracking, false);
    const type = item.NSPrivacyCollectedDataType.replace('NSPrivacyCollectedDataType', '');
    const expected = type === 'DeviceID' || type === 'CoarseLocation' ? ['Analytics'] : type === 'ProductInteraction' ? ['AppFunctionality', 'Analytics'] : ['AppFunctionality'];
    assert.deepEqual(item.NSPrivacyCollectedDataTypePurposes, expected.map(x => `NSPrivacyCollectedDataTypePurpose${x}`));
  }
  const project = plist(new URL('../Preferans.xcodeproj/project.pbxproj', import.meta.url).pathname);
  const phase = project.objects.A00000000000000000000032;
  assert(phase.files.includes('C0DE00000000000000000A02'));
  assert.equal(project.objects.C0DE00000000000000000A01.path, 'PrivacyInfo.xcprivacy');
});

test('scanner reads binary localized plists as well as the main Info.plist', () => {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'preferans-privacy-fixture-'));
  try {
    fs.mkdirSync(path.join(dir, 'uk.lproj'));
    const writePlist = (file, value) => {
      fs.writeFileSync(file, JSON.stringify(value));
      execFileSync('plutil', ['-convert', 'binary1', file]);
    };
    writePlist(path.join(dir, 'Info.plist'), { CFBundleVersion: 'fixture' });
    writePlist(path.join(dir, 'uk.lproj/InfoPlist.strings'), { NSUserTrackingUsageDescription: 'localized' });
    const report = inspectApp(dir, { verifySignature: false });
    assert.equal(report.plists.length, 2);
    assert.throws(() => assertNonTracking(report), /uk.lproj\/InfoPlist.strings/);
  } finally {
    fs.rmSync(dir, { recursive: true, force: true });
  }
});

test('product analytics profile still rejects advertising linkage, unsafe defaults and SDK tracking', () => {
  const report = clean();
  report.analyticsDefaults = plist(new URL('../Preferans/Info.plist', import.meta.url).pathname);
  report.binaries = [{ path: 'FirebaseAnalytics', trackingAPIs: [], advertisingLibraries: [], trackingOrAnalyticsLibraries: ['FirebaseAnalytics.framework/FirebaseAnalytics'] }];
  assertNonTracking(report, { productAnalytics: true });
  assert.throws(() => assertNonTracking(report), /tracking\/analytics library/);
  report.binaries[0].advertisingLibraries = ['AdSupport.framework/AdSupport'];
  assert.throws(() => assertNonTracking(report, { productAnalytics: true }), /advertising library/);
  report.binaries[0].advertisingLibraries = [];
  report.analyticsDefaults.FIREBASE_ANALYTICS_COLLECTION_ENABLED = true;
  assert.throws(() => assertNonTracking(report, { productAnalytics: true }), /Unsafe analytics default/);
  report.analyticsDefaults.FIREBASE_ANALYTICS_COLLECTION_ENABLED = false;
  report.plists.push({ path: 'Vendor.bundle/PrivacyInfo.xcprivacy', trackingKeys: [{ key: 'NSPrivacyTracking', value: true }] });
  assert.throws(() => assertNonTracking(report, { productAnalytics: true }));
});
