import fs from 'node:fs';
import path from 'node:path';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

const directory = new URL('./', import.meta.url);
const appID = '6763581975';
const versionID = '708305c7-7af1-42fb-9614-df78e0743cb5';
const appInfoID = '1c594ee3-5392-4bcb-82bd-da4b9c5eabe1';
const selectedBuildID = 'eef9c00f-9198-43a7-a3a6-4ed12d3ed52a';
const notes = fs.readFileSync(new URL('review-notes-build30.txt', directory), 'utf8');
assert(notes.length <= 4000);
const base = locale => 'https://guruofcards.com/apps/preferans/' + (['ru', 'uk'].includes(locale) ? locale + '/' : '');
const save = (file, value) => fs.writeFileSync(new URL(file, directory), JSON.stringify(value, null, 2) + '\n');
const getState = async () => {
  const version = (await asc(`/v1/appStoreVersions/${versionID}?include=build`)).data;
  const localizations = (await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`)).data;
  const appInfo = (await asc(`/v1/appInfos/${appInfoID}`)).data;
  const privacy = (await asc(`/v1/appInfos/${appInfoID}/appInfoLocalizations?limit=200`)).data;
  const review = (await asc(`/v1/appStoreVersions/${versionID}/appStoreReviewDetail`)).data;
  return { version: { id: version.id, attributes: version.attributes, build: version.relationships.build.data },
    appInfo: { id: appInfo.id, attributes: appInfo.attributes },
    localizations: localizations.map(row => ({ id: row.id, attributes: row.attributes })),
    privacy: privacy.map(row => ({ id: row.id, attributes: row.attributes })),
    review: { id: review.id, notes: review.attributes.notes, demoAccountRequired: review.attributes.demoAccountRequired } };
};
if (process.argv.includes('--sync-local-sources')) {
  for (const name of fs.readdirSync('AppStore/Localizations').filter(file => file.endsWith('.json'))) {
    const file = path.join('AppStore/Localizations', name);
    const row = JSON.parse(fs.readFileSync(file));
    row.supportUrl = base(row.locale) + 'support/';
    row.marketingUrl = base(row.locale);
    row.privacyPolicyUrl = base(row.locale) + 'privacy/';
    fs.writeFileSync(file, JSON.stringify(row, null, 2) + '\n');
  }
  const metadata = JSON.parse(fs.readFileSync('AppStore/Metadata.json'));
  Object.assign(metadata, { support_url: base('en-US') + 'support/', marketing_url: base('en-US'),
    privacy_policy_url: base('en-US') + 'privacy/', review_notes: notes });
  fs.writeFileSync('AppStore/Metadata.json', JSON.stringify(metadata, null, 2) + '\n');
  console.log('Updated only canonical URL fields and generic review notes in local metadata sources.');
  process.exit(0);
}
const before = await getState();
assert.equal(before.version.attributes.versionString, '1.0.3');
assert.equal(before.version.attributes.appStoreState, 'PREPARE_FOR_SUBMISSION');
assert.equal(before.version.build.id, selectedBuildID, 'Notes must match selected build 30');
assert.equal(before.appInfo.attributes.appStoreState, 'PREPARE_FOR_SUBMISSION');
if (!process.argv.includes('--apply')) {
  save('before.json', before);
  console.log(JSON.stringify({ captured: true, locales: before.localizations.length, privacyLocales: before.privacy.length,
    selectedBuildID, currentNotesMentionBuild27: before.review.notes?.includes('build 27') }));
  process.exit(0);
}
const initial = JSON.parse(fs.readFileSync(new URL('before.json', directory)));
assert.deepEqual(before, initial, 'Metadata changed since capture; inspect instead of overwriting it');
const protectedReview = attributes => Object.fromEntries(Object.entries(attributes).filter(([key]) => key !== 'notes'));
const privateReviewBefore = protectedReview((await asc(`/v1/appStoreReviewDetails/${initial.review.id}`)).data.attributes);
for (const locale of initial.localizations) {
  const root = base(locale.attributes.locale);
  await asc(`/v1/appStoreVersionLocalizations/${locale.id}`, { method: 'PATCH', body: {
    data: { type: 'appStoreVersionLocalizations', id: locale.id,
      attributes: { supportUrl: root + 'support/', marketingUrl: root } }
  } });
}
for (const locale of initial.privacy) {
  const root = base(locale.attributes.locale);
  await asc(`/v1/appInfoLocalizations/${locale.id}`, { method: 'PATCH', body: {
    data: { type: 'appInfoLocalizations', id: locale.id,
      attributes: { privacyPolicyUrl: root + 'privacy/', privacyChoicesUrl: root + 'support/#account-deletion' } }
  } });
}
await asc(`/v1/appStoreReviewDetails/${initial.review.id}`, { method: 'PATCH', body: {
  data: { type: 'appStoreReviewDetails', id: initial.review.id, attributes: { notes } }
} });
const after = await getState();
assert.deepEqual(after.version, initial.version, 'Version state or selected build changed');
assert.deepEqual(after.appInfo, initial.appInfo);
for (const locale of after.localizations) {
  const old = initial.localizations.find(row => row.id === locale.id).attributes;
  const root = base(old.locale);
  assert.deepEqual(locale.attributes, { ...old, supportUrl: root + 'support/', marketingUrl: root });
}
for (const locale of after.privacy) {
  const old = initial.privacy.find(row => row.id === locale.id).attributes;
  const root = base(old.locale);
  assert.deepEqual(locale.attributes, { ...old, privacyPolicyUrl: root + 'privacy/', privacyChoicesUrl: root + 'support/#account-deletion' });
}
assert.deepEqual(after.review, { ...initial.review, notes });
assert.deepEqual(protectedReview((await asc(`/v1/appStoreReviewDetails/${initial.review.id}`)).data.attributes), privateReviewBefore,
  'Private review contact or demo-account fields changed');
save('after.json', after);
save('verification.json', { checkedAt: new Date().toISOString(), version: '1.0.3', selectedBuild: '30', selectedBuildID,
  supportAndMarketingLocales: after.localizations.length, privacyLocales: after.privacy.length,
  reviewNotesUpdated: true, keywordsDescriptionsAndNamesUnchanged: true, privateReviewContactsUnchanged: true,
  buildSelectionUnchanged: true, appStoreReviewSubmitted: false, betaReviewModified: false,
  backendDeployed: false, newBuildUploaded: false });
console.log('Verified all draft links and build-30 review notes; other metadata and selected build unchanged.');
