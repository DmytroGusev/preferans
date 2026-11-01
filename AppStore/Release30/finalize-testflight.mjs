import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

const buildID = 'eef9c00f-9198-43a7-a3a6-4ed12d3ed52a';
const versionID = '708305c7-7af1-42fb-9614-df78e0743cb5';
const directory = new URL('./', import.meta.url);
const save = (file, value) => fs.writeFileSync(new URL(file, directory), JSON.stringify(value, null, 2) + '\n');
const before = JSON.parse(fs.readFileSync(new URL('store-before.json', directory)));
const versions = await asc('/v1/apps/6763581975/appStoreVersions?include=build&limit=10');
const localizations = await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`);
const protectedVersions = response => response.data.map(row => ({ id: row.id,
  attributes: row.attributes, build: row.relationships.build.data })).sort((a, b) => a.id.localeCompare(b.id));
const protectedLocalizations = response => response.data.map(row => ({ id: row.id,
  attributes: row.attributes })).sort((a, b) => a.id.localeCompare(b.id));
assert.deepEqual(protectedVersions(versions), protectedVersions(before.versions), 'Store versions/build selections changed');
assert.deepEqual(protectedLocalizations(localizations), protectedLocalizations(before.keywords), 'Store localizations changed');
save('store-after.json', { checkedAt: new Date().toISOString(), versions: protectedVersions(versions),
  localizations: protectedLocalizations(localizations), unchanged: true });

const build = await asc(`/v1/builds/${buildID}?include=buildBetaDetail,betaGroups,betaBuildLocalizations`);
assert.equal(build.data.attributes.version, '30');
assert.equal(build.data.attributes.processingState, 'VALID');
assert.equal(build.data.attributes.usesNonExemptEncryption, false);
const note = build.included.find(row => row.type === 'betaBuildLocalizations' && row.attributes.locale === 'en-US');
assert(note, 'Expected English TestFlight localization');
const whatsNew = fs.readFileSync(new URL('what-to-test.txt', directory), 'utf8');
await asc(`/v1/betaBuildLocalizations/${note.id}`, { method: 'PATCH', body: {
  data: { type: 'betaBuildLocalizations', id: note.id, attributes: { whatsNew } }
} });
const groups = build.included.filter(row => row.type === 'betaGroups' && row.attributes.isInternalGroup);
const access = [];
for (const group of groups) {
  const testers = await asc(`/v1/betaGroups/${group.id}/betaTesters?limit=1`);
  access.push({ id: group.id, name: group.attributes.name, testerCount: testers.meta.paging.total });
}
const final = await asc(`/v1/builds/${buildID}?include=buildBetaDetail,betaBuildLocalizations`);
assert.equal(final.included.find(row => row.type === 'betaBuildLocalizations' && row.attributes.locale === 'en-US').attributes.whatsNew, whatsNew);
const status = { checkedAt: new Date().toISOString(), id: buildID, ...final.data.attributes,
  version: '1.0.3', build: '30', beta: final.included.find(row => row.type === 'buildBetaDetails').attributes,
  groups: access, whatToTestVerified: true, appReviewSubmitted: false, storeMetadataUnchanged: true };
delete status.iconAssetToken;
save('testflight-final.json', status);
console.log(JSON.stringify(status, null, 2));
