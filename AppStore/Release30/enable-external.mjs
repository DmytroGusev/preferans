import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

assert(process.argv.includes('--enable-external'), 'Explicit --enable-external is required');
const appID = '6763581975';
const buildID = 'eef9c00f-9198-43a7-a3a6-4ed12d3ed52a';
const groupID = 'bd14644b-667a-47ce-b543-57118aedf8bd';
const getBuild = () => asc(`/v1/builds/${buildID}?include=buildBetaDetail,betaGroups,betaAppReviewSubmission`);
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
const existingTesters = await list(`/v1/betaGroups/${groupID}/betaTesters?limit=200`);
const appTesters = await list(`/v1/betaTesters?filter[apps]=${appID}&limit=200`);
assert(appTesters.length > 0);
assert(appTesters.every(tester => existingTesters.some(member => member.id === tester.id)),
  'Existing external group must already contain every app tester; inspect before changing membership');
const before = await getBuild();
assert.equal(before.data.attributes.processingState, 'VALID');
assert.equal(before.data.attributes.version, '30');
assert.equal(before.data.attributes.expired, false);
const localization = (await asc(`/v1/apps/${appID}/betaAppLocalizations?limit=200`)).data.find(row => row.attributes.locale === 'en-US');
assert(localization);
const description = 'Play Preferans, the classic trick-taking card game, with bots or friends. This beta focuses on public tables, room-code invitations, reconnect recovery and final match scores. Use build 30 on every test device to play together on the updated server.';
await asc(`/v1/betaAppLocalizations/${localization.id}`, { method: 'PATCH', body: {
  data: { type: 'betaAppLocalizations', id: localization.id, attributes: { description } }
} });
const notes = 'Build 1.0.3 (30) tests the updated owner-hosted multiplayer service. No purchased subscription or demo credentials are needed. Open Play online, enter a display name and tap Continue as Guest (Sign in with Apple is also available). Choose Create a table, or Find a table to join another device running build 30. Players mark Ready before the first deal. Local bot play is also available. Focus: public creation/join, reconnection after backgrounding, starting the next deal when the table manager is offline, and final balances in game history. Settings contains account deletion and legal links.';
await asc(`/v1/betaAppReviewDetails/${appID}`, { method: 'PATCH', body: {
  data: { type: 'betaAppReviewDetails', id: appID, attributes: { notes, demoAccountRequired: false } }
} });
await asc(`/v1/buildBetaDetails/${buildID}`, { method: 'PATCH', body: {
  data: { type: 'buildBetaDetails', id: buildID, attributes: { autoNotifyEnabled: true } }
} });
if (!before.included?.some(row => row.type === 'betaGroups' && row.id === groupID)) {
  await asc(`/v1/betaGroups/${groupID}/relationships/builds`, { method: 'POST', body: {
    data: [{ type: 'builds', id: buildID }]
  } });
}
let build = await getBuild();
const detail = () => build.included.find(row => row.type === 'buildBetaDetails').attributes;
if (detail().externalBuildState === 'READY_FOR_BETA_SUBMISSION') {
  await asc('/v1/betaAppReviewSubmissions', { method: 'POST', body: {
    data: { type: 'betaAppReviewSubmissions', relationships: { build: { data: { type: 'builds', id: buildID } } } }
  } });
  build = await getBuild();
}
assert(build.included.some(row => row.type === 'betaGroups' && row.id === groupID));
const members = await list(`/v1/betaGroups/${groupID}/betaTesters?limit=200`);
assert.deepEqual(members.map(row => row.id).sort(), existingTesters.map(row => row.id).sort());
const finalGroup = (await asc(`/v1/betaGroups/${groupID}`)).data;
assert.equal(finalGroup.attributes.publicLinkEnabled, group.attributes.publicLinkEnabled);
const receipt = { checkedAt: new Date().toISOString(), appID, version: '1.0.3', build: '30', buildID,
  group: { id: groupID, name: group.attributes.name, testerCount: members.length, allExistingAppTestersIncluded: true,
    membershipUnchanged: true, publicLinkEnabled: finalGroup.attributes.publicLinkEnabled },
  processingState: build.data.attributes.processingState, beta: detail(),
  betaReview: build.included.find(row => row.type === 'betaAppReviewSubmissions')?.attributes ?? null,
  betaDescription: description, betaReviewNotes: notes, appStoreReviewSubmitted: false };
fs.writeFileSync(new URL('external-testing.json', import.meta.url), JSON.stringify(receipt, null, 2) + '\n');
console.log(JSON.stringify(receipt, null, 2));
