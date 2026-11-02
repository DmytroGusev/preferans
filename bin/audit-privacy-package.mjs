import assert from 'node:assert/strict';
import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { createHash } from 'node:crypto';
import { execFileSync } from 'node:child_process';
import { pathToFileURL } from 'node:url';

const trackingKeys = new Set(['NSUserTrackingUsageDescription', 'NSPrivacyTracking', 'NSPrivacyTrackingDomains', 'NSPrivacyCollectedDataTypeTracking']);
const trackingAPIs = ['ATTrackingManager', 'ASIdentifierManager', 'requestTrackingAuthorization', 'advertisingIdentifier'];
const trackedLibraries = /AppTrackingTransparency|AdSupport|FirebaseAnalytics|GoogleAppMeasurement|FBSDK|AppsFlyer|Adjust|AppLovin|GoogleMobileAds/;
const readPlist = file => JSON.parse(execFileSync('plutil', ['-convert', 'json', '-o', '-', file], { encoding: 'utf8' }));
const sha256 = file => createHash('sha256').update(fs.readFileSync(file)).digest('hex');

function walk(dir) {
  return fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name.localeCompare(b.name)).flatMap(entry => {
    const file = path.join(dir, entry.name);
    // Do not follow bundle symlinks into unrelated filesystem locations.
    return entry.isDirectory() ? walk(file) : entry.isFile() ? [file] : [];
  });
}

function inspectKeys(value, prefix = '') {
  if (!value || typeof value !== 'object') return [];
  return Object.entries(value).flatMap(([key, child]) => [
    ...(trackingKeys.has(key) ? [{ key: `${prefix}${key}`, value: child }] : []),
    ...inspectKeys(child, `${prefix}${key}.`),
  ]);
}

export function inspectApp(app, { verifySignature = true } = {}) {
  const info = readPlist(path.join(app, 'Info.plist'));
  const files = walk(app);
  const plists = files.filter(file => /\.(plist|strings|stringsdict|xcprivacy)$/.test(file)).map(file => {
    const content = readPlist(file);
    return { path: path.relative(app, file), sha256: sha256(file), trackingKeys: inspectKeys(content),
      ...(file.endsWith('.xcprivacy') ? { manifest: content } : {}) };
  });
  const binaries = files.filter(file => {
    const bytes = fs.readFileSync(file);
    return bytes.length >= 4 && ['feedface', 'cefaedfe', 'feedfacf', 'cffaedfe', 'cafebabe', 'bebafeca', 'cafebabf', 'bfbafeca'].includes(bytes.subarray(0, 4).toString('hex'));
  }).map(file => {
    const bytes = fs.readFileSync(file);
    const libraries = execFileSync('otool', ['-L', file], { encoding: 'utf8' }).trim().split('\n').slice(1).map(line => line.trim());
    return { path: path.relative(app, file), sha256: sha256(file), libraries,
      trackingAPIs: trackingAPIs.filter(symbol => bytes.includes(Buffer.from(symbol))),
      trackingOrAnalyticsLibraries: libraries.filter(line => trackedLibraries.test(line)) };
  });
  if (verifySignature) execFileSync('codesign', ['--verify', '--deep', '--strict', app], { stdio: ['ignore', 'pipe', 'pipe'] });
  return { version: info.CFBundleShortVersionString, build: info.CFBundleVersion,
    bundleID: info.CFBundleIdentifier, xcode: info.DTXcodeBuild, sdkBuild: info.DTSDKBuild,
    signatureVerified: verifySignature, fileCount: files.length, plists, binaries,
    nestedBundles: [...new Set(files.flatMap(file => path.relative(app, file).split('/').filter(part => /\.(appex|framework|bundle)$/.test(part))))],
    manifestPresent: plists.some(file => file.path === 'PrivacyInfo.xcprivacy') };
}

export function assertNonTracking(report, { requireManifest = false } = {}) {
  for (const file of report.plists) {
    for (const item of file.trackingKeys) {
      assert(!item.key.endsWith('NSUserTrackingUsageDescription'), `${file.path}: tracking permission key`);
      if (item.key.endsWith('NSPrivacyTrackingDomains')) assert.deepEqual(item.value, [], `${file.path}: tracking domains`);
      else assert.equal(item.value, false, `${file.path}: ${item.key}`);
    }
  }
  for (const file of report.binaries) {
    assert.deepEqual(file.trackingAPIs, [], `${file.path}: ATT/IDFA symbols`);
    assert.deepEqual(file.trackingOrAnalyticsLibraries, [], `${file.path}: tracking/analytics library`);
  }
  if (requireManifest) {
    assert(report.manifestPresent, 'Missing app PrivacyInfo.xcprivacy');
    const manifest = report.plists.find(file => file.path === 'PrivacyInfo.xcprivacy').manifest;
    assert.equal(manifest.NSPrivacyTracking, false);
    assert(manifest.NSPrivacyAccessedAPITypes?.some(api => api.NSPrivacyAccessedAPIType === 'NSPrivacyAccessedAPICategoryUserDefaults' && api.NSPrivacyAccessedAPITypeReasons.includes('CA92.1')), 'Missing app-private UserDefaults reason');
  }
}

if (process.argv[1] && import.meta.url === pathToFileURL(path.resolve(process.argv[1])).href) {
  const args = process.argv.slice(2);
  const input = args.find(arg => !arg.startsWith('--'));
  assert(input, 'Usage: node bin/audit-privacy-package.mjs APP_OR_IPA [--require-manifest]');
  const temp = input.endsWith('.ipa') ? fs.mkdtempSync(path.join(os.tmpdir(), 'preferans-privacy-audit-')) : null;
  try {
    if (temp) execFileSync('unzip', ['-q', path.resolve(input), '-d', temp]);
    const apps = temp ? fs.readdirSync(path.join(temp, 'Payload')).filter(file => file.endsWith('.app')) : [];
    if (temp) assert.equal(apps.length, 1, 'Expected one top-level app');
    const app = temp ? path.join(temp, 'Payload', apps[0]) : path.resolve(input);
    const report = inspectApp(app);
    if (temp) report.ipaSHA256 = sha256(input);
    try {
      assertNonTracking(report, { requireManifest: args.includes('--require-manifest') });
      report.nonTrackingCheckPassed = true;
    } catch (error) {
      report.nonTrackingCheckPassed = false;
      report.failure = error.message;
      process.exitCode = 1;
    }
    console.log(JSON.stringify(report, null, 2));
  } finally {
    if (temp) fs.rmSync(temp, { recursive: true, force: true });
  }
}
