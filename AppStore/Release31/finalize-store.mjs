import fs from 'node:fs';
import assert from 'node:assert/strict';
import { asc } from '../asc.mjs';

const app = '6763581975';
const version = '708305c7-7af1-42fb-9614-df78e0743cb5';
const dir = new URL('./', import.meta.url);
const save = (file, data) => fs.writeFileSync(new URL(file, dir), JSON.stringify(data, null, 2) + '\n');
const builds = await asc(`/v1/builds?filter[app]=${app}&filter[version]=31&limit=10`);
assert(builds.data.length <= 1, 'Ambiguous build 31');
const build = builds.data[0];
console.log(JSON.stringify({ build: build?.attributes.version, id: build?.id, processingState: build?.attributes.processingState }));
if (!process.argv.includes('--apply')) process.exit(0);
assert.equal(build?.attributes.processingState, 'VALID');
const snapshot = async () => {
  const current = await asc(`/v1/appStoreVersions/${version}`);
  assert.equal(current.data.attributes.versionString, '1.0.3');
  assert.equal(current.data.attributes.appStoreState, 'PREPARE_FOR_SUBMISSION');
  const selected = await asc(`/v1/appStoreVersions/${version}/build`);
  const locales = await asc(`/v1/appStoreVersions/${version}/appStoreVersionLocalizations?limit=100`);
  const review = await asc(`/v1/appStoreVersions/${version}/appStoreReviewDetail`);
  return {
    version: { id: version, version: '1.0.3', state: current.data.attributes.appStoreState },
    build: { id: selected.data.id, version: selected.data.attributes.version },
    locales: locales.data.map(item => ({ id: item.id, attributes: item.attributes })),
    review: { id: review.data.id, notes: review.data.attributes.notes, demoAccountRequired: review.data.attributes.demoAccountRequired },
  };
};
const before = await snapshot();
assert(['30', '31'].includes(before.build.version), 'Unexpected selected build');
const beforeFile = new URL('store-before.json', dir);
if (!fs.existsSync(beforeFile)) save('store-before.json', before);
const additions = {
  ca: 'Hem eliminat la sol·licitud de seguiment no utilitzada i hem actualitzat la informació de privadesa.',
  cs: 'Odstranili jsme nepoužívanou žádost o sledování a aktualizovali informace o soukromí.',
  da: 'Vi har fjernet den ubrugte sporingsanmodning og opdateret oplysningerne om privatliv.',
  'de-DE': 'Die ungenutzte Tracking-Abfrage wurde entfernt und die Datenschutzhinweise wurden aktualisiert.',
  el: 'Καταργήθηκε το μη χρησιμοποιούμενο αίτημα παρακολούθησης και ενημερώθηκαν οι πληροφορίες απορρήτου.',
  'en-GB': 'Removed the unused tracking-permission request and updated privacy information.',
  'en-US': 'Removed the unused tracking-permission request and updated privacy information.',
  'es-ES': 'Eliminamos la solicitud de seguimiento no utilizada y actualizamos la información de privacidad.',
  fi: 'Poistimme käyttämättömän seurantalupapyynnön ja päivitimme tietosuojatiedot.',
  'fr-FR': 'La demande de suivi inutilisée a été supprimée et les informations de confidentialité ont été mises à jour.',
  hr: 'Uklonjen je nekorišteni zahtjev za praćenje i ažurirane su informacije o privatnosti.',
  hu: 'Eltávolítottuk a nem használt követési engedélykérést, és frissítettük az adatvédelmi tájékoztatást.',
  it: 'Abbiamo rimosso la richiesta di tracciamento inutilizzata e aggiornato le informazioni sulla privacy.',
  'nl-NL': 'Het ongebruikte verzoek om trackingtoestemming is verwijderd en de privacyinformatie is bijgewerkt.',
  no: 'Vi har fjernet den ubrukte sporingsforespørselen og oppdatert personverninformasjonen.',
  pl: 'Usunięto nieużywaną prośbę o zgodę na śledzenie i zaktualizowano informacje o prywatności.',
  'pt-PT': 'Removemos o pedido de rastreio não utilizado e atualizámos as informações de privacidade.',
  ro: 'Am eliminat solicitarea de urmărire neutilizată și am actualizat informațiile de confidențialitate.',
  ru: 'Удалён неиспользуемый запрос разрешения на трекинг и обновлена информация о конфиденциальности.',
  sk: 'Odstránili sme nepoužívanú žiadosť o sledovanie a aktualizovali informácie o súkromí.',
  'sl-SI': 'Odstranili smo neuporabljeno zahtevo za sledenje in posodobili informacije o zasebnosti.',
  sv: 'Vi har tagit bort den oanvända spårningsförfrågan och uppdaterat integritetsinformationen.',
  tr: 'Kullanılmayan izleme izni isteği kaldırıldı ve gizlilik bilgileri güncellendi.',
  uk: 'Видалено невикористаний запит дозволу на відстеження й оновлено інформацію про приватність.',
};
const notes = fs.readFileSync(new URL('review-notes.txt', dir), 'utf8').trim();
if (before.build.id !== build.id) {
  await asc(`/v1/appStoreVersions/${version}/relationships/build`, { method: 'PATCH', body: { data: { type: 'builds', id: build.id } } });
}
if (before.review.notes !== notes) {
  await asc(`/v1/appStoreReviewDetails/${before.review.id}`, { method: 'PATCH', body: { data: { type: 'appStoreReviewDetails', id: before.review.id, attributes: { notes } } } });
}
for (const item of before.locales) {
  const extra = additions[item.attributes.locale];
  assert(extra, `Missing privacy release translation: ${item.attributes.locale}`);
  assert(item.attributes.whatsNew?.trim(), 'Do not overwrite missing release copy');
  if (!item.attributes.whatsNew.includes(extra)) {
    const whatsNew = item.attributes.whatsNew.trim() + '\n\n' + extra;
    assert(whatsNew.length <= 4000);
    await asc(`/v1/appStoreVersionLocalizations/${item.id}`, { method: 'PATCH', body: { data: { type: 'appStoreVersionLocalizations', id: item.id, attributes: { whatsNew } } } });
  }
}
const after = await snapshot();
assert.equal(after.build.id, build.id);
assert.equal(after.review.notes, notes);
assert.equal(after.review.demoAccountRequired, before.review.demoAccountRequired);
for (const item of after.locales) {
  const previous = before.locales.find(old => old.id === item.id);
  const omitWhatsNew = ({ whatsNew, ...attrs }) => attrs;
  assert.deepEqual(omitWhatsNew(item.attributes), omitWhatsNew(previous.attributes));
  assert(item.attributes.whatsNew.includes(additions[item.attributes.locale]));
  const local = new URL(`../Localizations/${item.attributes.locale}.json`, dir);
  const data = JSON.parse(fs.readFileSync(local, 'utf8'));
  data.whatsNew = item.attributes.whatsNew;
  fs.writeFileSync(local, JSON.stringify(data, null, 2) + '\n');
}
const metadata = new URL('../Metadata.json', dir);
const data = JSON.parse(fs.readFileSync(metadata, 'utf8'));
data.review_notes = notes;
fs.writeFileSync(metadata, JSON.stringify(data, null, 2) + '\n');
save('store-after.json', after);
save('store-verification.json', { checkedAt: new Date().toISOString(), buildId: build.id, selectedBuild: '31', versionState: after.version.state, localesUpdated: after.locales.length, onlyWhatsNewAndReviewNotesChanged: true, appReviewSubmitted: false, serverDeployed: false });
console.log('Selected build 31, updated review notes and release copy; other metadata preserved.');
