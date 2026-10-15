import { readFileSync, writeFileSync } from 'node:fs';
import { asc } from './asc.mjs';

const versionID = '98378d13-7f10-4728-85bc-a501b9698373';
const appInfoID = 'c4e23e60-d944-4f7e-93e2-c5163b1ec30d';
const versions = await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`);
const infos = await asc(`/v1/appInfos/${appInfoID}/appInfoLocalizations?limit=200`);
const expected = JSON.parse(readFileSync(new URL('./ReleaseEvidence/localizations-applied.json', import.meta.url), 'utf8'));
for (const row of expected) {
  const local = JSON.parse(readFileSync(new URL(`./Localizations/${row.locale}.json`, import.meta.url), 'utf8'));
  const version = versions.data.find(x => x.attributes.locale === row.locale)?.attributes;
  const info = infos.data.find(x => x.attributes.locale === row.locale)?.attributes;
  for (const k of ['description', 'keywords', 'promotionalText', 'whatsNew', 'supportUrl', 'marketingUrl']) if (version?.[k] !== local[k]) throw new Error(`${row.locale}: server mismatch ${k}`);
  for (const k of ['name', 'subtitle', 'privacyPolicyUrl']) if (info?.[k] !== local[k]) throw new Error(`${row.locale}: server mismatch ${k}`);
}
const assets = JSON.parse(readFileSync(new URL('./ReleaseEvidence/media-uploaded.json', import.meta.url), 'utf8'));
const states = [];
for (const asset of assets) {
  const remote = await asc(`/v1/${asset.type}/${asset.id}`);
  const a = remote.data.attributes;
  const state = a.assetDeliveryState?.state || a.state;
  if (state === 'FAILED') throw new Error(`Failed media ${asset.file}: ${JSON.stringify(a.assetDeliveryState)}`);
  states.push({ id: asset.id, type: asset.type, file: asset.file, state, dimensions: a.imageAsset ? [a.imageAsset.width, a.imageAsset.height] : undefined });
  console.log(asset.type, state, asset.file.split('/').at(-1));
}
const build = await asc('/v1/builds/eca4773c-36c9-4ef4-936f-dd7b353fb08e');
const version = await asc(`/v1/appStoreVersions/${versionID}?include=build`);
const group = await asc('/v1/betaGroups/0702be10-ea15-4148-af56-212045b44fa2/builds?limit=200');
const placements = JSON.parse(readFileSync(new URL('./ReleaseEvidence/creative-placements.json', import.meta.url), 'utf8'));
const experiment = JSON.parse(readFileSync(new URL('./ReleaseEvidence/header-experiment.json', import.meta.url), 'utf8'));
const test = await asc(`/v2/appStoreVersionExperiments/${experiment.experimentID}`);
const summary = { verifiedDate: '2026-10-15', metadataLocaleCount: expected.length, metadataMatched: true,
  build: { id: build.data.id, number: build.data.attributes.version, processingState: build.data.attributes.processingState,
    availableInInternalTesters: group.data.some(x => x.id === build.data.id) },
  version: { id: versionID, state: version.data.attributes.appStoreState, releaseType: version.data.attributes.releaseType,
    selectedBuild: version.data.relationships.build.data.id }, assets: states,
  draftCreativePlacements: placements.length, experiment: { id: experiment.experimentID, state: test.data.attributes.state,
    treatmentLocales: experiment.localizations.map(x => x.locale), pendingLocales: experiment.pendingLocalesUntilVersionRelease },
  productionBackendDeployed: false, appReviewSubmitted: false };
writeFileSync(new URL('./ReleaseEvidence/verified-release.json', import.meta.url), JSON.stringify(summary, null, 2));
console.log(`Verified ${expected.length} locales, ${states.length} assets, ${placements.length} creative placements; build ${build.data.attributes.version} ${build.data.attributes.processingState}.`);
