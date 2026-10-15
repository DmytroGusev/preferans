import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { asc } from './asc.mjs';

const file = new URL('./ReleaseEvidence/header-experiment.json', import.meta.url);
const evidence = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : { localizations: [] };
const save = () => writeFileSync(file, JSON.stringify(evidence, null, 2));
const uploaded = JSON.parse(readFileSync(new URL('./ReleaseEvidence/media-uploaded.json', import.meta.url), 'utf8'));
const imageID = uploaded.find(x => x.file.endsWith('header-b-table.png'))?.id;
if (!imageID) throw new Error('Upload Header B first.');
if (!evidence.experimentID) {
  const existing = await asc('/v1/apps/6763581975/appStoreVersionExperimentsV2');
  const match = existing.data.find(x => x.attributes.name === 'Preferans 1.0.2 header: cards vs table');
  const experiment = match || (await asc('/v2/appStoreVersionExperiments', { method: 'POST', body: { data: {
    type: 'appStoreVersionExperiments', attributes: { name: 'Preferans 1.0.2 header: cards vs table', platform: 'IOS', trafficProportion: 50 },
    relationships: { app: { data: { type: 'apps', id: '6763581975' } } },
  } } })).data;
  evidence.experimentID = experiment.id;
  evidence.state = experiment.attributes.state;
  evidence.baseline = 'Header A: navy card fan on version 1.0.2; publish that version before starting.';
  evidence.treatment = 'Header B: actual auction UI. Search Results remains Header A in both groups.';
  evidence.traffic = '50% original / 50% treatment';
  evidence.started = false;
  evidence.startPrerequisites = ['Production backend deployed and verified', 'Version 1.0.2 tested, reviewed and released with Header A', 'Header B and PPO treatment approved by Apple'];
  save();
}
if (!evidence.treatmentID) {
  const treatment = await asc('/v1/appStoreVersionExperimentTreatments', { method: 'POST', body: { data: {
    type: 'appStoreVersionExperimentTreatments', attributes: { name: 'Header B: the actual table' },
    relationships: { appStoreVersionExperimentV2: { data: { type: 'appStoreVersionExperiments', id: evidence.experimentID } } },
  } } });
  evidence.treatmentID = treatment.data.id; save();
}
const locales = JSON.parse(readFileSync(new URL('./ReleaseEvidence/localizations-applied.json', import.meta.url), 'utf8'));
const versions = await asc('/v1/apps/6763581975/appStoreVersions?filter[platform]=IOS');
const live = versions.data.find(x => x.attributes.appStoreState === 'READY_FOR_SALE');
if (!live) throw new Error('PPO requires a live app.');
const published = await asc(`/v1/appStoreVersions/${live.id}/appStoreVersionLocalizations?limit=200`);
const supported = new Set(published.data.map(x => x.attributes.locale));
evidence.pendingLocalesUntilVersionRelease = locales.filter(x => !supported.has(x.locale)).map(x => x.locale);
save();
for (const x of locales) {
  // Apple binds experiment locales to the released version, not the new draft.
  if (!supported.has(x.locale)) continue;
  let entry = evidence.localizations.find(l => l.locale === x.locale);
  if (!entry) {
    const localized = await asc('/v1/appStoreVersionExperimentTreatmentLocalizations', { method: 'POST', body: { data: {
      type: 'appStoreVersionExperimentTreatmentLocalizations', attributes: { locale: x.locale },
      relationships: { appStoreVersionExperimentTreatment: { data: { type: 'appStoreVersionExperimentTreatments', id: evidence.treatmentID } } },
    } } });
    entry = { locale: x.locale, id: localized.data.id }; evidence.localizations.push(entry); save();
  }
  if (entry.placementID) continue;
  const placement = await asc('/v1/appAssetLibraryPlacements', { method: 'POST', body: { data: {
    type: 'appAssetLibraryPlacements', attributes: { placementType: 'PRODUCT_PAGE_HEADER_ASSET', placementGroup: 'DEFAULT_PROFILE' },
    relationships: { image: { data: { type: 'appAssetLibraryImages', id: imageID } },
      appStoreVersionExperimentTreatmentLocalization: { data: { type: 'appStoreVersionExperimentTreatmentLocalizations', id: entry.id } } },
  } } });
  entry.placementID = placement.data.id; save();
  console.log(`Prepared header experiment: ${x.locale}`);
}
console.log('Draft experiment prepared. Not submitted, not started.');
