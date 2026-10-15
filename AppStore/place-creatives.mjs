import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { asc } from './asc.mjs';

const versionID = process.env.ASC_VERSION_ID;
if (!versionID) throw new Error('Set ASC_VERSION_ID.');
const version = await asc(`/v1/appStoreVersions/${versionID}`);
if (version.data.attributes.appStoreState !== 'PREPARE_FOR_SUBMISSION') throw new Error('Only edit a draft version.');
const uploaded = JSON.parse(readFileSync(new URL('./ReleaseEvidence/media-uploaded.json', import.meta.url), 'utf8'));
const image = uploaded.find(x => x.file.endsWith('header-a-cards.png'));
if (!image) throw new Error('Upload the creative first.');
const state = await asc(`/v1/appAssetLibraryImages/${image.id}`);
if (!['PREPARE_FOR_SUBMISSION', 'APPROVED'].includes(state.data.attributes.state)) throw new Error('Creative has not finished processing.');
const locales = await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`);
const file = new URL('./ReleaseEvidence/creative-placements.json', import.meta.url);
const entries = existsSync(file) ? JSON.parse(readFileSync(file, 'utf8')) : [];
for (const locale of locales.data) for (const placementType of ['PRODUCT_PAGE_HEADER_ASSET', 'APP_STORE_SEARCH_RESULTS_ASSET']) {
  if (entries.some(x => x.locale === locale.attributes.locale && x.placementType === placementType)) continue;
  const result = await asc('/v1/appAssetLibraryPlacements', { method: 'POST', body: { data: {
    type: 'appAssetLibraryPlacements', attributes: { placementType, placementGroup: 'DEFAULT_PROFILE' },
    relationships: { image: { data: { type: 'appAssetLibraryImages', id: image.id } },
      appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: locale.id } } },
  } } });
  entries.push({ locale: locale.attributes.locale, placementType, id: result.data.id, imageID: image.id });
  writeFileSync(file, JSON.stringify(entries, null, 2));
  console.log(`Assigned ${locale.attributes.locale}: ${placementType}`);
}
