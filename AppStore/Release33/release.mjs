import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

const app = '6763581975';
const version = '708305c7-7af1-42fb-9614-df78e0743cb5';
const group = 'bd14644b-667a-47ce-b543-57118aedf8bd';
const dir = new URL('./', import.meta.url);
const save = (name, value) => fs.writeFileSync(new URL(name, dir), JSON.stringify(value, null, 2) + '\n');
const snapshot = async () => {
  const versions = await asc(`/v1/apps/${app}/appStoreVersions?include=build&limit=50`);
  const locales = await asc(`/v1/appStoreVersions/${version}/appStoreVersionLocalizations?limit=100`);
  const review = (await asc(`/v1/appStoreVersions/${version}/appStoreReviewDetail`)).data;
  return { versions: versions.data.map(x => ({ id: x.id, version: x.attributes.versionString, state: x.attributes.appStoreState, copyright: x.attributes.copyright, build: x.relationships.build.data })).sort((a,b) => a.id.localeCompare(b.id)),
    locales: locales.data.map(x => ({ id: x.id, attributes: x.attributes })).sort((a,b) => a.id.localeCompare(b.id)),
    review: { id: review.id, notes: review.attributes.notes, demoAccountRequired: review.attributes.demoAccountRequired } };
};
if (process.argv.includes('--capture')) {
  assert(!fs.existsSync(new URL('store-before.json', dir)), 'Do not overwrite the baseline');
  save('store-before.json', await snapshot());
  console.log('Captured Store baseline without private reviewer contact fields.');
  process.exit(0);
}
const rows = (await asc(`/v1/builds?filter[app]=${app}&filter[version]=33&limit=10`)).data;
assert(rows.length <= 1, 'Ambiguous build 33');
const build = rows[0];
console.log(JSON.stringify({ build: '33', id: build?.id, state: build?.attributes.processingState ?? 'NOT_VISIBLE_YET' }));
if (!process.argv.includes('--select') && !process.argv.includes('--external')) process.exit(0);
assert.equal(build?.attributes.processingState, 'VALID');
assert.equal(build.attributes.expired, false);
const before = JSON.parse(fs.readFileSync(new URL('store-before.json', dir), 'utf8'));
const current = await snapshot();
const currentVersion = current.versions.find(x => x.id === version);
assert(['REJECTED', 'DEVELOPER_REJECTED', 'PREPARE_FOR_SUBMISSION'].includes(currentVersion?.state), 'Never alter a version under review');
assert.equal(currentVersion.version, '1.0.3');
assert.deepEqual(current.locales, before.locales, 'Localizations changed; inspect before modifying');
const unaffected = state => state.versions.filter(x => x.id !== version);
assert.deepEqual(unaffected(current), unaffected(before), 'Other Store version changed');
if (process.argv.includes('--select')) {
  assert([before.versions.find(x => x.id === version).build.id, build.id].includes(currentVersion.build.id));
  assert.deepEqual(current.review, before.review, 'Review details changed; inspect before selection');
  if (currentVersion.build.id !== build.id) await asc(`/v1/appStoreVersions/${version}/relationships/build`, { method: 'PATCH', body: { data: { type: 'builds', id: build.id } } });
  const notes = fs.readFileSync(new URL('review-notes.txt', dir), 'utf8').trim();
  const pending = 'APP PRIVACY STATUS: The legacy Other Diagnostic Data tracking answer is pending correction/validation in App Store Connect. This draft has not been resubmitted.\n\n';
  await asc(`/v1/appStoreReviewDetails/${current.review.id}`, { method: 'PATCH', body: { data: { type: 'appStoreReviewDetails', id: current.review.id, attributes: { notes: pending + notes } } } });
  const after = await snapshot();
  assert.equal(after.versions.find(x => x.id === version).build.id, build.id);
  assert.deepEqual(after.locales, before.locales);
  assert.deepEqual(unaffected(after), unaffected(before));
  assert.equal(after.review.demoAccountRequired, before.review.demoAccountRequired);
  save('store-after-selection.json', after);
  console.log('Selected build 33 and updated only reviewer notes; no review submission.');
}
if (process.argv.includes('--external')) {
  const baseline = fs.existsSync(new URL('store-after-selection.json', dir)) ? JSON.parse(fs.readFileSync(new URL('store-after-selection.json', dir), 'utf8')) : current;
  const betaGroup = (await asc(`/v1/betaGroups/${group}`)).data;
  assert.equal(betaGroup.attributes.isInternalGroup, false);
  const members = (await asc(`/v1/betaGroups/${group}/betaTesters?limit=200`)).data;
  assert(members.length > 0);
  const get = () => asc(`/v1/builds/${build.id}?include=buildBetaDetail,betaGroups,betaAppReviewSubmission,betaBuildLocalizations`);
  let state = await get();
  const text = fs.readFileSync(new URL('what-to-test.txt', dir), 'utf8');
  const english = state.included?.find(x => x.type === 'betaBuildLocalizations' && x.attributes.locale === 'en-US');
  if (english) await asc(`/v1/betaBuildLocalizations/${english.id}`, { method: 'PATCH', body: { data: { type: 'betaBuildLocalizations', id: english.id, attributes: { whatsNew: text } } } });
  else await asc('/v1/betaBuildLocalizations', { method: 'POST', body: { data: { type: 'betaBuildLocalizations', attributes: { locale: 'en-US', whatsNew: text }, relationships: { build: { data: { type: 'builds', id: build.id } } } } } });
  await asc(`/v1/betaAppReviewDetails/${app}`, { method: 'PATCH', body: { data: { type: 'betaAppReviewDetails', id: app, attributes: { notes: fs.readFileSync(new URL('review-notes.txt', dir), 'utf8').trim(), demoAccountRequired: false } } } });
  await asc(`/v1/buildBetaDetails/${build.id}`, { method: 'PATCH', body: { data: { type: 'buildBetaDetails', id: build.id, attributes: { autoNotifyEnabled: true } } } });
  if (!state.included?.some(x => x.type === 'betaGroups' && x.id === group)) await asc(`/v1/betaGroups/${group}/relationships/builds`, { method: 'POST', body: { data: [{ type: 'builds', id: build.id }] } });
  state = await get();
  if (state.included.find(x => x.type === 'buildBetaDetails').attributes.externalBuildState === 'READY_FOR_BETA_SUBMISSION') {
    await asc('/v1/betaAppReviewSubmissions', { method: 'POST', body: { data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: build.id } } } } } });
    state = await get();
  }
  const finalMembers = (await asc(`/v1/betaGroups/${group}/betaTesters?limit=200`)).data;
  assert.deepEqual(finalMembers.map(x => x.id).sort(), members.map(x => x.id).sort());
  const finalGroup = (await asc(`/v1/betaGroups/${group}`)).data;
  assert.equal(finalGroup.attributes.publicLinkEnabled, betaGroup.attributes.publicLinkEnabled);
  assert(state.included.some(x => x.type === 'betaGroups' && x.id === group));
  assert.equal(state.included.find(x => x.type === 'betaBuildLocalizations' && x.attributes.locale === 'en-US').attributes.whatsNew, text);
  assert.deepEqual(await snapshot(), baseline, 'Store changed during beta setup');
  const receipt = { checkedAt: new Date().toISOString(), build: '33', buildID: build.id, processingState: state.data.attributes.processingState,
    beta: state.included.find(x => x.type === 'buildBetaDetails').attributes,
    betaReview: state.included.find(x => x.type === 'betaAppReviewSubmissions')?.attributes ?? null,
    existingExternalTesterCount: members.length, membershipUnchanged: true, publicLinkUnchanged: true, publicReviewSubmitted: false };
  save('testflight.json', receipt);
  console.log(JSON.stringify(receipt, null, 2));
}
