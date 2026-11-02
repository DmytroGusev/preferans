import fs from 'node:fs';
import assert from 'node:assert/strict';

const log = name => fs.readFileSync(`/private/tmp/preferans32-${name}.log`, 'utf8');
const save = (file, data) => fs.writeFileSync(new URL(file, import.meta.url), JSON.stringify(data, null, 2) + '\n');
const extract = text => JSON.parse(text.slice(text.indexOf('{\n')));
const live = extract(log('bot-live'));
const local = extract(log('bot-loopback'));
for (const run of [live, local]) {
  assert.equal(run.cases.length, 4);
  assert.equal(run.temporaryAccountsDeleted, 8);
  assert(run.cases.every(item => item.firstDealAccepted && item.privateProjections && item.protectedHumanSeat));
}
assert(log('worker-tests').includes('pass 59') && log('worker-tests').includes('fail 0'));
assert(log('worker-runtime').includes('19 passed'));
assert(log('app-tests').includes('Executed 272 tests, with 3 tests skipped and 0 failures'));
assert(log('app-tests').includes('Test run with 24 tests in 3 suites passed'));
assert(log('native-ui').includes('testNativeHostConfiguresBotBesideFriendAndStartsPublicTable]'));
assert(log('native-ui').includes('passed (56.828 seconds)'));
assert(log('settings-ui').includes('passed (16.029 seconds)'));
assert(log('ipad-ui').includes('Executed 2 tests, with 0 failures'));
assert(log('public-loopback').includes('4 players passed'));
save('network-verification.json', { checkedAt: new Date().toISOString(), local, owner: live, humanOnlyPublicRegression: 'passed' });
save('test-results.json', {
  sourceCommit: 'f4b65759eb107c87592e71a84a63307bd43046c0', workerTypecheck: 'passed', workerUnit: { passed: 59, failed: 0 },
  workerdLifecycle: { passed: 19, failed: 0 }, appXCTest: { executed: 272, skipped: 3, failures: 0 }, swiftTesting: { tests: 24, failures: 0 },
  iphone: { botFlowSeconds: 56.828, settingsLinksSeconds: 16.029, passed: true },
  ipad: { botFlowSeconds: 46.552, settingsLinksSeconds: 16.931, passed: true },
  caveats: [
    'The initial Settings test queried a SwiftUI Link as Button; corrected test rerun passed. The first combined iPhone run therefore reports failure although its bot case passed.',
    'The initial IPA verifier hit the default child-process buffer on large icon assets and looked for a joined route literal, although source constructs path components. Both verifier assumptions were corrected, without changing app code.',
    'Three live-backend app test cases are environment-gated skips; separate real-network checks cover the owner service.',
    'First-deal bot admission, not complete-match bot play or physical-device billing, was tested here.'
  ]
});
const deployed = log('worker-deploy');
assert(deployed.includes('no changes preferans-room-worker-preferansenginecontainer'));
const version = deployed.match(/Current Version ID: ([0-9a-f-]+)/)?.[1];
assert(version);
const container = JSON.parse(fs.readFileSync('/private/tmp/preferans32-container-after.json', 'utf8'));
const image = 'registry.cloudflare.com/df302a84563143eb92fc75a7277079ec/preferans-engine@sha256:90d5da73d8fc8cd677e3e4047174b46c03cfd8539005d685a8274c16b1e456dc';
assert.equal(container.configuration.image, image);
assert.equal(container.version, 2);
assert.equal(container.updated_at, '2026-11-01T19:10:35.401999872Z');
assert.equal(container.durable_objects.namespace_id, 'bfbad95f8bf74522bd4dd456bf32cb57');
save('deployment.json', { checkedAt: new Date().toISOString(), sourceCommit: 'f4b65759eb107c87592e71a84a63307bd43046c0',
  endpoint: live.base, previousWorkerVersion: '057ca688-8fb1-4f89-a057-4eea2ce36091', workerVersion: version,
  engine: { id: container.id, version: container.version, image, configurationUpdatedAt: container.updated_at, namespace: container.durable_objects.namespace_id, unchanged: true },
  migrationChanged: false, accountOrGameReset: false, friendServerModified: false, subscriptionsActivated: false,
  liveBotCasesPassed: live.cases.length });
console.log('Recorded Worker, native app and live network verification; engine configuration unchanged.');
