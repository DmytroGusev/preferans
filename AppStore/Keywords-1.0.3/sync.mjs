import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

const directory = new URL('./', import.meta.url);
const read = name => JSON.parse(fs.readFileSync(new URL(name, directory), 'utf8'));
const save = (name, value) => fs.writeFileSync(new URL(name, directory), JSON.stringify(value, null, 2) + '\n');
const plan = read('plan.json');
const baseline = read('before.json');
const rollback = process.argv.includes('--rollback');
const apply = process.argv.includes('--apply');
assert(!(rollback && apply), 'Choose apply OR rollback');
assert.equal(plan.versionID, '708305c7-7af1-42fb-9614-df78e0743cb5');
assert.equal(new Set(plan.updates.map(x => x.locale)).size, 23);
for (const update of plan.updates) {
  assert.notEqual(update.locale, 'en-US');
  assert.equal([...update.keywords].length, 100);
  assert(!update.keywords.endsWith(',') && !update.keywords.includes(', '));
  assert.equal(new Set(update.keywords.split(',')).size, update.keywords.split(',').length);
  for (const term of ['pref', 'tick']) assert(update.keywords.split(',').includes(term));
}
if (!apply && !rollback) {
  console.log('Validated 23 keyword-only updates at 100 characters each. US stays unchanged. Use --apply or --rollback.');
  process.exit(0);
}

const versionPath = `/v1/appStoreVersions/${plan.versionID}`;
const localizationPath = `${versionPath}/appStoreVersionLocalizations?limit=200`;
const version = await asc(`${versionPath}?include=build`);
assert.equal(version.data.attributes.versionString, '1.0.3');
assert.equal(version.data.attributes.appStoreState, 'PREPARE_FOR_SUBMISSION');
assert.equal(version.data.relationships.build.data.id, baseline.version.data.relationships.build.data.id);
const current = await asc(localizationPath);
assert.equal(current.data.find(x => x.attributes.locale === 'en-US').attributes.keywords, plan.sourceKeywords,
  'US keywords changed since the snapshot; stop instead of replacing user edits');

// Preflight every locale before modifying any; permit a safe partial-run retry.
for (const update of plan.updates) {
  const actual = current.data.find(x => x.id === update.id);
  assert.equal(actual?.attributes.locale, update.locale);
  assert([update.before, update.keywords].includes(actual.attributes.keywords),
    `${update.locale}: concurrent keyword edit detected; nothing will overwrite it`);
}
const applied = [];
for (const update of plan.updates) {
  const target = rollback ? update.before : update.keywords;
  const fresh = await asc(`/v1/appStoreVersionLocalizations/${update.id}`);
  assert([update.before, update.keywords].includes(fresh.data.attributes.keywords),
    `${update.locale}: keyword edit detected during run; stop`);
  if (fresh.data.attributes.keywords !== target) {
    await asc(`/v1/appStoreVersionLocalizations/${update.id}`, {
      method: 'PATCH', body: { data: { type: 'appStoreVersionLocalizations', id: update.id,
        attributes: { keywords: target } } }
    });
  }
  applied.push({ locale: update.locale, keywords: target });
  save(rollback ? 'rollback-progress.json' : 'apply-progress.json', applied);
  console.log(`${rollback ? 'Restored' : 'Saved'} ${update.locale}: ${[...target].length} characters`);
}

const after = await asc(localizationPath);
save(rollback ? 'rollback-after.json' : 'after.json', after);
assert.equal(after.data.find(x => x.attributes.locale === 'en-US').attributes.keywords, plan.sourceKeywords);
for (const update of plan.updates) {
  assert.equal(after.data.find(x => x.id === update.id).attributes.keywords, rollback ? update.before : update.keywords);
}
const versionAfter = await asc(`${versionPath}?include=build`);
assert.equal(versionAfter.data.attributes.appStoreState, version.data.attributes.appStoreState);
assert.deepEqual(versionAfter.data.relationships.build.data, version.data.relationships.build.data);
const unrelatedChanges = [];
for (const locale of after.data) {
  const old = current.data.find(x => x.id === locale.id);
  for (const key of Object.keys(old.attributes).filter(x => x !== 'keywords')) {
    if (JSON.stringify(old.attributes[key]) !== JSON.stringify(locale.attributes[key])) {
      unrelatedChanges.push({ locale: locale.attributes.locale, field: key });
    }
  }
}
save('verification.json', { version: versionAfter, usUnchanged: true,
  action: rollback ? 'rollback' : 'apply', updatedLocales: applied.length,
  characters: Object.fromEntries(applied.map(x => [x.locale, [...x.keywords].length])),
  concurrentNonKeywordChanges: unrelatedChanges, patchFields: ['keywords'],
  reviewSubmitted: false, newBuildUploaded: false });
console.log(JSON.stringify({ verified: applied.length, usUnchanged: true, unrelatedChanges,
  state: versionAfter.data.attributes.appStoreState, buildUnchanged: true }));
