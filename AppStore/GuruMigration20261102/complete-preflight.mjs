import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';
const directory = new URL('./', import.meta.url);
const versionID = '708305c7-7af1-42fb-9614-df78e0743cb5';
const ageID = '1c594ee3-5392-4bcb-82bd-da4b9c5eabe1';
const copy = JSON.parse(fs.readFileSync(new URL('whats-new-build30.json', directory)));
const ageCorrections = { advertising: false, messagingAndChat: false, socialMedia: false, socialMediaAgeRestricted: false };
const save = (file, value) => fs.writeFileSync(new URL(file, directory), JSON.stringify(value, null, 2) + '\n');
const current = async () => ({
  age: (await asc(`/v1/appInfos/${ageID}/ageRatingDeclaration`)).data,
  locales: (await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`)).data,
  version: (await asc(`/v1/appStoreVersions/${versionID}?include=build`)).data
});
const before = await current();
assert.equal(before.version.attributes.appStoreState, 'PREPARE_FOR_SUBMISSION');
assert.equal(before.version.relationships.build.data.id, 'eef9c00f-9198-43a7-a3a6-4ed12d3ed52a');
const target = before.locales.filter(row => !row.attributes.whatsNew);
for (const row of target) assert(copy[row.attributes.locale]?.length > 0);
if (!process.argv.includes('--apply')) {
  save('preflight-before.json', before);
  console.log(JSON.stringify({ missingWhatsNew: target.map(row => row.attributes.locale),
    advertising: before.age.attributes.advertising, messagingAndChat: before.age.attributes.messagingAndChat }));
  process.exit(0);
}
const initial = JSON.parse(fs.readFileSync(new URL('preflight-before.json', directory)));
assert.deepEqual(before.version, initial.version);
for (const row of before.locales) {
  const old = initial.locales.find(item => item.id === row.id).attributes;
  assert.deepEqual(row.attributes, old.whatsNew || !row.attributes.whatsNew ? old : { ...old, whatsNew: copy[old.locale] });
}
const withoutCorrections = attributes => Object.fromEntries(Object.entries(attributes).filter(([key]) => !(key in ageCorrections)));
assert.deepEqual(withoutCorrections(before.age.attributes), withoutCorrections(initial.age.attributes));
for (const row of target) {
  await asc(`/v1/appStoreVersionLocalizations/${row.id}`, { method: 'PATCH', body: {
    data: { type: 'appStoreVersionLocalizations', id: row.id, attributes: { whatsNew: copy[row.attributes.locale] } }
  } });
}
// Neither advertising placements nor player-to-player chat exists in build 30.
await asc(`/v1/ageRatingDeclarations/${ageID}`, { method: 'PATCH', body: {
  data: { type: 'ageRatingDeclarations', id: ageID, attributes: ageCorrections }
} });
const after = await current();
assert.deepEqual(after.version, before.version);
assert.deepEqual(after.age.attributes, { ...initial.age.attributes, ...ageCorrections });
for (const row of after.locales) {
  const old = before.locales.find(item => item.id === row.id).attributes;
  assert.deepEqual(row.attributes, old.whatsNew ? old : { ...old, whatsNew: copy[old.locale] });
}
save('preflight-after.json', after);
save('preflight-verification.json', { checkedAt: new Date().toISOString(), missingWhatsNewFilled: initial.locales.filter(row => !row.attributes.whatsNew).length,
  localesHaveWhatsNew: after.locales.every(row => !!row.attributes.whatsNew),
  draftAgeCorrections: ageCorrections, allOtherAgeAnswersUnchanged: true,
  keywordsDescriptionsAndLinksUnchanged: true, selectedBuildUnchanged: true,
  appPrivacyNutritionLabelModified: false, appReviewSubmitted: false });
console.log('Verified release text and accurate draft advertising/chat answers; all other fields preserved.');
