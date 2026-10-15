import { readdirSync, readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { asc } from './asc.mjs';

const root = new URL('./Localizations/', import.meta.url);
const locales = readdirSync(root).filter(f => f.endsWith('.json')).sort().map(f => JSON.parse(readFileSync(new URL(f, root), 'utf8')));
const valid = new Set(['en-US', 'en-GB', 'ca', 'hr', 'cs', 'da', 'nl-NL', 'fi', 'fr-FR', 'de-DE', 'el', 'hu', 'it', 'no', 'pl', 'pt-PT', 'ro', 'ru', 'sk', 'sl-SI', 'es-ES', 'sv', 'tr', 'uk']);
for (const x of locales) {
  if (!valid.has(x.locale)) throw new Error(`Unsupported locale: ${x.locale}`);
  for (const [key, max] of Object.entries({ name: 30, subtitle: 30, promotionalText: 170, description: 4000, whatsNew: 4000, keywords: 100 })) {
    if (typeof x[key] !== 'string' || !x[key].trim() || [...x[key]].length > max) throw new Error(`${x.locale}: invalid ${key}`);
  }
  for (const key of ['supportUrl', 'marketingUrl', 'privacyPolicyUrl']) if (new URL(x[key]).protocol !== 'https:') throw new Error(`${x.locale}: invalid ${key}`);
}
if (!process.argv.includes('--apply')) {
  console.log(`Validated ${locales.length} localizations. Use --apply to update the editable version only.`);
  process.exit(0);
}
const versionID = process.env.ASC_VERSION_ID;
const appInfoID = process.env.ASC_APP_INFO_ID;
if (!versionID || !appInfoID) throw new Error('Set ASC_VERSION_ID and ASC_APP_INFO_ID.');
const version = await asc(`/v1/appStoreVersions/${versionID}`);
if (version.data.attributes.appStoreState !== 'PREPARE_FOR_SUBMISSION') throw new Error('Only a draft version may be edited.');
const appInfo = await asc(`/v1/appInfos/${appInfoID}`);
if (appInfo.data.attributes.appStoreState !== 'PREPARE_FOR_SUBMISSION') throw new Error('Only draft App Information may be edited.');
const versions = await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`);
const infos = await asc(`/v1/appInfos/${appInfoID}/appInfoLocalizations?limit=200`);
mkdirSync(new URL('./ReleaseEvidence/', import.meta.url), { recursive: true });
const backup = new URL('./ReleaseEvidence/localizations-before.json', import.meta.url);
if (!existsSync(backup)) writeFileSync(backup, JSON.stringify({ versionID, appInfoID, versions, infos }, null, 2));
const result = [];
for (const x of locales) {
  const oldInfo = infos.data.find(a => a.attributes.locale === x.locale);
  const infoAttributes = { name: x.name, subtitle: x.subtitle, privacyPolicyUrl: x.privacyPolicyUrl };
  const versionAttributes = Object.fromEntries(['description', 'keywords', 'promotionalText', 'whatsNew', 'supportUrl', 'marketingUrl'].map(k => [k, x[k]]));
  const info = await asc(oldInfo ? `/v1/appInfoLocalizations/${oldInfo.id}` : '/v1/appInfoLocalizations', {
    method: oldInfo ? 'PATCH' : 'POST', body: { data: { type: 'appInfoLocalizations', ...(oldInfo ? { id: oldInfo.id } : {}),
      attributes: { ...infoAttributes, ...(!oldInfo ? { locale: x.locale } : {}) },
      ...(!oldInfo ? { relationships: { appInfo: { data: { type: 'appInfos', id: appInfoID } } } } : {}) } },
  });
  // Adding App Information may automatically create the version localization.
  const currentVersions = await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`);
  const oldVersion = currentVersions.data.find(a => a.attributes.locale === x.locale);
  const localized = await asc(oldVersion ? `/v1/appStoreVersionLocalizations/${oldVersion.id}` : '/v1/appStoreVersionLocalizations', {
    method: oldVersion ? 'PATCH' : 'POST', body: { data: { type: 'appStoreVersionLocalizations', ...(oldVersion ? { id: oldVersion.id } : {}),
      attributes: { ...versionAttributes, ...(!oldVersion ? { locale: x.locale } : {}) },
      ...(!oldVersion ? { relationships: { appStoreVersion: { data: { type: 'appStoreVersions', id: versionID } } } } : {}) } },
  });
  result.push({ locale: x.locale, appInfoLocalizationID: info.data.id, versionLocalizationID: localized.data.id });
  writeFileSync(new URL('./ReleaseEvidence/localizations-applied.json', import.meta.url), JSON.stringify(result, null, 2));
  console.log(`Saved ${x.locale}`);
}
