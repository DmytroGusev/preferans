import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

assert(process.argv.includes('--enable-external'), 'Explicit --enable-external required');
const appID = '6763581975';
const groupID = 'bd14644b-667a-47ce-b543-57118aedf8bd';
const builds = await asc(`/v1/builds?filter[app]=${appID}&filter[version]=31&limit=10`);
assert.equal(builds.data.length, 1);
const buildID = builds.data[0].id;
assert.equal(builds.data[0].attributes.processingState, 'VALID');
assert.equal(builds.data[0].attributes.expired, false);
const getBuild = () => asc(`/v1/builds/${buildID}?include=buildBetaDetail,betaGroups,betaAppReviewSubmission,betaBuildLocalizations`);
const list = async path => {
  const rows = [];
  while (path) {
    const page = await asc(path);
    rows.push(...page.data);
    path = page.links?.next ? new URL(page.links.next).pathname + new URL(page.links.next).search : null;
  }
  return rows;
};
const group = (await asc(`/v1/betaGroups/${groupID}`)).data;
assert.equal(group.attributes.isInternalGroup, false);
const originalMembers = await list(`/v1/betaGroups/${groupID}/betaTesters?limit=200`);
const appMembers = await list(`/v1/betaTesters?filter[apps]=${appID}&limit=200`);
assert(appMembers.length > 0);
assert(appMembers.every(tester => originalMembers.some(member => member.id === tester.id)));
let build = await getBuild();
const whatToTest = fs.readFileSync(new URL('what-to-test.txt', import.meta.url), 'utf8');
const english = build.included?.find(row => row.type === 'betaBuildLocalizations' && row.attributes.locale === 'en-US');
if (english) {
  await asc(`/v1/betaBuildLocalizations/${english.id}`, { method: 'PATCH', body: { data: { type: 'betaBuildLocalizations', id: english.id, attributes: { whatsNew: whatToTest } } } });
} else {
  await asc('/v1/betaBuildLocalizations', { method: 'POST', body: { data: { type: 'betaBuildLocalizations', attributes: { locale: 'en-US', whatsNew: whatToTest }, relationships: { build: { data: { type: 'builds', id: buildID } } } } } });
}
const localization = (await asc(`/v1/apps/${appID}/betaAppLocalizations?limit=200`)).data.find(row => row.attributes.locale === 'en-US');
assert(localization);
const description = 'Play classic Preferans with bots or friends. Test public and invite-only tables, reconnect recovery and final match scores. Build 31 removes the unused tracking-permission prompt and IDFA helper. Build 30 and 31 devices use the same owner-hosted multiplayer service. No purchase is required.';
await asc(`/v1/betaAppLocalizations/${localization.id}`, { method: 'PATCH', body: { data: { type: 'betaAppLocalizations', id: localization.id, attributes: { description } } } });
const notes = fs.readFileSync(new URL('review-notes.txt', import.meta.url), 'utf8').trim();
await asc(`/v1/betaAppReviewDetails/${appID}`, { method: 'PATCH', body: { data: { type: 'betaAppReviewDetails', id: appID, attributes: { notes, demoAccountRequired: false } } } });
await asc(`/v1/buildBetaDetails/${buildID}`, { method: 'PATCH', body: { data: { type: 'buildBetaDetails', id: buildID, attributes: { autoNotifyEnabled: true } } } });
if (!build.included?.some(row => row.type === 'betaGroups' && row.id === groupID)) {
  await asc(`/v1/betaGroups/${groupID}/relationships/builds`, { method: 'POST', body: { data: [{ type: 'builds', id: buildID }] } });
}
build = await getBuild();
const detail = () => build.included.find(row => row.type === 'buildBetaDetails').attributes;
if (detail().externalBuildState === 'READY_FOR_BETA_SUBMISSION') {
  await asc('/v1/betaAppReviewSubmissions', { method: 'POST', body: { data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: buildID } } } } } });
  build = await getBuild();
}
const members = await list(`/v1/betaGroups/${groupID}/betaTesters?limit=200`);
assert.deepEqual(members.map(row => row.id).sort(), originalMembers.map(row => row.id).sort());
const finalGroup = (await asc(`/v1/betaGroups/${groupID}`)).data;
assert.equal(finalGroup.attributes.publicLinkEnabled, group.attributes.publicLinkEnabled);
assert(build.included.some(row => row.type === 'betaGroups' && row.id === groupID));
assert.equal(build.included.find(row => row.type === 'betaBuildLocalizations' && row.attributes.locale === 'en-US').attributes.whatsNew, whatToTest);
const receipt = { checkedAt: new Date().toISOString(), appID, build: '31', buildID,
  group: { id: groupID, testerCount: members.length, allExistingAppTestersIncluded: true, membershipUnchanged: true, publicLinkEnabled: finalGroup.attributes.publicLinkEnabled },
  processingState: build.data.attributes.processingState, beta: detail(),
  betaReview: build.included.find(row => row.type === 'betaAppReviewSubmissions')?.attributes ?? null,
  whatToTestVerified: true, appStoreReviewSubmitted: false, serverDeployed: false };
fs.writeFileSync(new URL('external-testing.json', import.meta.url), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt, null, 2));
