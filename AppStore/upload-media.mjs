import { readFileSync, writeFileSync, existsSync } from 'node:fs';
import { basename } from 'node:path';
import { createHash } from 'node:crypto';
import { asc } from './asc.mjs';

export async function upload(resource, attributes, relationships, file) {
  const bytes = readFileSync(file);
  const reserved = await asc(`/v1/${resource}`, { method: 'POST', body: { data: {
    type: resource, attributes: { ...attributes, fileName: basename(file), fileSize: bytes.length }, relationships,
  } } });
  for (const operation of reserved.data.attributes.uploadOperations) {
    const headers = Object.fromEntries((operation.requestHeaders || []).map(x => [x.name, x.value]));
    const response = await fetch(operation.url, { method: operation.method, headers,
      body: bytes.subarray(operation.offset, operation.offset + operation.length), signal: AbortSignal.timeout(120000) });
    if (!response.ok) throw new Error(`Asset bytes upload failed: ${response.status}`);
  }
  const checksum = createHash('md5').update(bytes).digest('hex');
  return (await asc(`/v1/${resource}/${reserved.data.id}`, { method: 'PATCH', body: { data: {
    type: resource, id: reserved.data.id,
    attributes: { uploaded: true, ...(resource.startsWith('appAssetLibrary') ? {} : { sourceFileChecksum: checksum }) },
  } } })).data;
}

if (process.argv[1]?.endsWith('/upload-media.mjs')) {
  const versionID = process.env.ASC_VERSION_ID;
  if (!versionID) throw new Error('Set ASC_VERSION_ID to the editable draft.');
  const version = await asc(`/v1/appStoreVersions/${versionID}`);
  if (version.data.attributes.appStoreState !== 'PREPARE_FOR_SUBMISSION') throw new Error('Refusing to edit a non-draft version.');
  const locales = await asc(`/v1/appStoreVersions/${versionID}/appStoreVersionLocalizations?limit=200`);
  const primary = locales.data.find(x => x.attributes.locale === 'en-US');
  const old = await asc(`/v1/appStoreVersionLocalizations/${primary.id}/appScreenshotSets?include=appScreenshots`);
  const backup = new URL('./ReleaseEvidence/screenshots-before.json', import.meta.url);
  if (!existsSync(backup)) writeFileSync(backup, JSON.stringify(old, null, 2));
  const completedFile = new URL('./ReleaseEvidence/media-uploaded.json', import.meta.url);
  const completed = existsSync(completedFile) ? JSON.parse(readFileSync(completedFile, 'utf8')) : [];
  const record = entry => { completed.push(entry); writeFileSync(completedFile, JSON.stringify(completed, null, 2)); };
  for (const [kind, display] of [['iphone', 'APP_IPHONE_67'], ['ipad', 'APP_IPAD_PRO_3GEN_129'], ['iphone-medium', 'APP_IPHONE_61']]) {
    let set = old.data.find(x => x.attributes.screenshotDisplayType === display);
    if (!set) set = (await asc('/v1/appScreenshotSets', { method: 'POST', body: { data: { type: 'appScreenshotSets', attributes: { screenshotDisplayType: display },
      relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: primary.id } } } } } })).data;
    const existing = await asc(`/v1/appScreenshotSets/${set.id}/appScreenshots`);
    const desired = [];
    for (const filename of ['1-03-bidding-east.png', '2-06-talon-exchange.png', '3-01-lobby.png']) {
      const file = new URL(`./Media/1.0.2/${kind}/${filename}`, import.meta.url).pathname;
      let item = completed.find(x => x.file === file);
      if (!item) { const asset = await upload('appScreenshots', {}, { appScreenshotSet: { data: { type: 'appScreenshotSets', id: set.id } } }, file); item = { file, id: asset.id, type: asset.type }; record(item); }
      desired.push({ type: 'appScreenshots', id: item.id });
    }
    // Delete only the copied screenshots on the editable draft after replacements exist.
    for (const item of existing.data) if (!desired.some(x => x.id === item.id)) await asc(`/v1/appScreenshots/${item.id}`, { method: 'DELETE' });
    await asc(`/v1/appScreenshotSets/${set.id}/relationships/appScreenshots`, { method: 'PATCH', body: { data: desired } });
    console.log(`Updated ${kind} screenshots on en-US; other store locales inherit the primary images.`);
  }
  const previews = await asc(`/v1/appStoreVersionLocalizations/${primary.id}/appPreviewSets`);
  let previewSet = previews.data.find(x => x.attributes.previewType === 'IPHONE_67');
  if (!previewSet) previewSet = (await asc('/v1/appPreviewSets', { method: 'POST', body: { data: { type: 'appPreviewSets', attributes: { previewType: 'IPHONE_67' },
    relationships: { appStoreVersionLocalization: { data: { type: 'appStoreVersionLocalizations', id: primary.id } } } } } })).data;
  const preview = new URL('./Media/1.0.2/iphone/app-preview.mp4', import.meta.url).pathname;
  if (!completed.some(x => x.file === preview)) {
    const asset = await upload('appPreviews', { mimeType: 'video/mp4', previewFrameTimeCode: '00:00:06:00' }, { appPreviewSet: { data: { type: 'appPreviewSets', id: previewSet.id } } }, preview);
    record({ file: preview, id: asset.id, type: asset.type });
    console.log('Uploaded real app preview.');
  }
  for (const filename of ['header-a-cards.png', 'header-b-table.png']) {
    const file = new URL(`./Media/1.0.2/creatives/${filename}`, import.meta.url).pathname;
    if (completed.some(x => x.file === file)) continue;
    const asset = await upload('appAssetLibraryImages', { category: 'CREATIVE_ASSETS', referenceName: `Preferans 1.0.2 ${filename}` },
      { assetLibrary: { data: { type: 'appAssetLibraries', id: '6763581975' } } }, file);
    record({ file, id: asset.id, type: asset.type });
    console.log(`Uploaded ${filename} to creative library.`);
  }
}
