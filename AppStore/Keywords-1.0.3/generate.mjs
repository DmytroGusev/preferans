import fs from 'node:fs';
import assert from 'node:assert/strict';

const directory = new URL('./', import.meta.url);
const read = name => JSON.parse(fs.readFileSync(new URL(name, directory), 'utf8'));
const before = read('before.json');
const info = read('app-info-before.json');
const candidates = read('candidates.json');
const fold = value => value.normalize('NFKD').replace(/\p{M}/gu, '').toLowerCase();
const words = value => fold(value).match(/[\p{L}\p{N}]+/gu) ?? [];
const source = before.localizations.data.find(x => x.attributes.locale === 'en-US');
assert(source);
for (const term of ['pref', 'tick']) assert(source.attributes.keywords.split(',').includes(term));
const expected = before.localizations.data.filter(x => x.attributes.locale !== 'en-US').map(x => x.attributes.locale).sort();
assert.deepEqual(Object.keys(candidates).sort(), expected);

const updates = expected.map(locale => {
  const metadata = info.localizations.data.find(x => x.attributes.locale === locale).attributes;
  const indexed = new Set(words(metadata.name + ' ' + metadata.subtitle));
  const seen = new Set();
  const keep = term => {
    const key = fold(term);
    if (seen.has(key) || words(term).some(word => indexed.has(word))) return false;
    seen.add(key);
    return true;
  };
  const [required, choices] = candidates[locale];
  const core = required.filter(keep);
  const optional = choices.filter(keep);
  assert(core.includes('pref') && core.includes('tick'));
  const states = new Map([[core.join(',').length, { terms: core, priority: 0n }]]);
  optional.forEach((term, index) => {
    for (const [length, state] of [...states]) {
      const next = length + 1 + [...term].length;
      if (next > 100) continue;
      const priority = state.priority + (1n << BigInt(optional.length - index));
      if (!states.has(next) || priority > states.get(next).priority) {
        states.set(next, { terms: [...state.terms, term], priority });
      }
    }
  });
  const keywords = states.get(Math.max(...states.keys())).terms.join(',');
  assert([...keywords].length <= 100 && !keywords.endsWith(','));
  const original = before.localizations.data.find(x => x.attributes.locale === locale);
  return { locale, id: original.id, before: original.attributes.keywords, keywords,
    characters: [...keywords].length, utf8Bytes: Buffer.byteLength(keywords) };
});
const plan = { appID: '6763581975', versionID: '708305c7-7af1-42fb-9614-df78e0743cb5',
  version: '1.0.3', protectedLocale: 'en-US', sourceKeywords: source.attributes.keywords, updates };
fs.writeFileSync(new URL('plan.json', directory), JSON.stringify(plan, null, 2) + '\n');
for (const x of updates) console.log(`${x.locale}: ${x.characters}/100 ${x.keywords}`);
