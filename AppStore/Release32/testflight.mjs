import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

const appID = '6763581975';
const versionID = '708305c7-7af1-42fb-9614-df78e0743cb5';
const groupID = 'bd14644b-667a-47ce-b543-57118aedf8bd';
const dir = new URL('./', import.meta.url);
const save = (file, value) => fs.writeFileSync(new URL(file, dir), JSON.stringify(value, null, 2) + '\n');
const snapshot = async () => {
  const versions = await asc(`/v1/apps/${appID}/appStoreVersions?include=build&limit=20`);
  const locales = await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=100`);
  const review = await asc(`/v1/appStoreVersions/${versionID}/appStoreReviewDetail`);
  return { versions: versions.data.map(row => ({ id: row.id, version: row.attributes.versionString, state: row.attributes.appStoreState, copyright: row.attributes.copyright, build: row.relationships.build.data })).sort((a,b) => a.id.localeCompare(b.id)),
    locales: locales.data.map(row => ({ id: row.id, attributes: row.attributes })).sort((a,b) => a.id.localeCompare(b.id)),
    review: { notes: review.data.attributes.notes, demoAccountRequired: review.data.attributes.demoAccountRequired } };
};
if (process.argv.includes('--capture-store')) {
  assert(!fs.existsSync(new URL('protected-store-before.json', dir)), 'Do not overwrite the protected baseline');
  save('protected-store-before.json', await snapshot());
  console.log('Captured public Store versions, selections, localizations and review notes.');
  process.exit(0);
}
const builds = await asc(`/v1/builds?filter[app]=${appID}&filter[version]=32&limit=10`);
assert(builds.data.length <= 1);
const buildRow = builds.data[0];
console.log(JSON.stringify(buildRow ? { id: buildRow.id, build: '32', state: buildRow.attributes.processingState } : { state: 'NOT_VISIBLE_YET' }));
if (!process.argv.includes('--enable-external')) process.exit(0);
assert.equal(buildRow?.attributes.processingState, 'VALID');
const protectedStore = JSON.parse(fs.readFileSync(new URL('protected-store-before.json', dir), 'utf8'));
assert.deepEqual(await snapshot(), protectedStore, 'Store metadata changed; inspect before proceeding');
const buildID = buildRow.id;
const getBuild = () => asc(`/v1/builds/${buildID}?include=buildBetaDetail,betaGroups,betaAppReviewSubmission,betaBuildLocalizations`);
const list = async path => {
  const rows = [];
  while (path) {
    const page = await asc(path); rows.push(...page.data);
    path = page.links?.next ? new URL(page.links.next).pathname + new URL(page.links.next).search : null;
  }
  return rows;
};
const group = (await asc(`/v1/betaGroups/${groupID}`)).data;
assert.equal(group.attributes.isInternalGroup, false);
const members = await list(`/v1/betaGroups/${groupID}/betaTesters?limit=200`);
assert(members.length > 0);
let build = await getBuild();
assert.equal(build.data.attributes.expired, false);
const whatToTest = fs.readFileSync(new URL('what-to-test.txt', dir), 'utf8');
const english = build.included?.find(row => row.type === 'betaBuildLocalizations' && row.attributes.locale === 'en-US');
if (english) await asc(`/v1/betaBuildLocalizations/${english.id}`, { method: 'PATCH', body: { data: { type: 'betaBuildLocalizations', id: english.id, attributes: { whatsNew: whatToTest } } } });
else await asc('/v1/betaBuildLocalizations', { method: 'POST', body: { data: { type: 'betaBuildLocalizations', attributes: { locale: 'en-US', whatsNew: whatToTest }, relationships: { build: { data: { type: 'builds', id: buildID } } } } } });
const localization = (await asc(`/v1/apps/${appID}/betaAppLocalizations?limit=100`)).data.find(row => row.attributes.locale === 'en-US');
assert(localization);
await asc(`/v1/betaAppLocalizations/${localization.id}`, { method: 'PATCH', body: { data: { type: 'betaAppLocalizations', id: localization.id, attributes: { description: 'Classic Preferans with friends or local bots. Build 32 adds host-controlled bot seats with difficulty choices to public and invite-only online waiting rooms. Two friends can complete a three- or four-seat table with bots. Includes clear Club/pricing information; paid subscriptions and online limits are not active. No purchase is required.' } } } });
const notes = fs.readFileSync(new URL('review-notes.txt', dir), 'utf8').trim();
await asc(`/v1/betaAppReviewDetails/${appID}`, { method: 'PATCH', body: { data: { type: 'betaAppReviewDetails', id: appID, attributes: { notes, demoAccountRequired: false } } } });
await asc(`/v1/buildBetaDetails/${buildID}`, { method: 'PATCH', body: { data: { type: 'buildBetaDetails', id: buildID, attributes: { autoNotifyEnabled: true } } } });
if (!build.included?.some(row => row.type === 'betaGroups' && row.id === groupID)) await asc(`/v1/betaGroups/${groupID}/relationships/builds`, { method: 'POST', body: { data: [{ type: 'builds', id: buildID }] } });
build = await getBuild();
const detail = () => build.included.find(row => row.type === 'buildBetaDetails').attributes;
if (detail().externalBuildState === 'READY_FOR_BETA_SUBMISSION') {
  await asc('/v1/betaAppReviewSubmissions', { method: 'POST', body: { data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: buildID } } } } } });
  build = await getBuild();
}
const finalMembers = await list(`/v1/betaGroups/${groupID}/betaTesters?limit=200`);
assert.deepEqual(finalMembers.map(row => row.id).sort(), members.map(row => row.id).sort());
const finalGroup = (await asc(`/v1/betaGroups/${groupID}`)).data;
assert.equal(finalGroup.attributes.publicLinkEnabled, group.attributes.publicLinkEnabled);
assert(build.included.some(row => row.type === 'betaGroups' && row.id === groupID));
assert.equal(build.included.find(row => row.type === 'betaBuildLocalizations' && row.attributes.locale === 'en-US').attributes.whatsNew, whatToTest);
const after = await snapshot(); assert.deepEqual(after, protectedStore);
save('protected-store-after.json', after);
const receipt = { checkedAt: new Date().toISOString(), version: '1.0.3', build: '32', buildID, processingState: build.data.attributes.processingState,
  beta: detail(), betaReview: build.included.find(row => row.type === 'betaAppReviewSubmissions')?.attributes ?? null,
  existingExternalTesterCount: members.length, membershipUnchanged: true, publicLinkUnchanged: true,
  whatToTestVerified: true, storeVersionSelectionsAndMetadataUnchanged: true, publicReviewSubmitted: false, subscriptionsActivated: false };
save('testflight-final.json', receipt); console.log(JSON.stringify(receipt, null, 2));
