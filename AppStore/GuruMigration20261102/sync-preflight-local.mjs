import fs from 'node:fs';
import assert from 'node:assert/strict';
const state = JSON.parse(fs.readFileSync(new URL('preflight-after.json', import.meta.url)));
const expected = new Set(state.locales.map(row => row.attributes.locale));
for (const name of fs.readdirSync('AppStore/Localizations').filter(file => file.endsWith('.json'))) {
  const file = 'AppStore/Localizations/' + name;
  const local = JSON.parse(fs.readFileSync(file));
  const live = state.locales.find(row => row.attributes.locale === local.locale)?.attributes;
  assert(live, `Missing current draft locale ${local.locale}`);
  // Preserve the owner's current ASO keywords rather than shipping the old template later.
  local.keywords = live.keywords;
  local.whatsNew = live.whatsNew;
  fs.writeFileSync(file, JSON.stringify(local, null, 2) + '\n');
  expected.delete(local.locale);
}
assert.equal(expected.size, 0);
console.log('Synchronized local keyword and release-note fields from the verified current draft; no API writes.');
