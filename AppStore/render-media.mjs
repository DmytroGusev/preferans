import { readFileSync, writeFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { execFileSync } from 'node:child_process';
const require = createRequire(import.meta.url);
const sharp = require('sharp');

// Only consume captures whose source manifest matches this checkout.
execFileSync('bin/screens-latest', { stdio: 'inherit' });
const phoneRun = process.env.IPHONE_CAPTURE;
const padRun = process.env.IPAD_CAPTURE;
if (!phoneRun || !padRun) throw new Error('Set IPHONE_CAPTURE and IPAD_CAPTURE to verified bin/screens run directories.');
const output = new URL('./Media/1.0.2/', import.meta.url);
const provenance = [];
const captures = [['iphone', phoneRun], ['ipad', padRun]];
if (process.env.MEDIUM_CAPTURE) captures.push(['iphone-medium', process.env.MEDIUM_CAPTURE]);
for (const [kind, run] of captures) {
  execFileSync('python3', ['bin/lib/screen-provenance.py', 'check', `${run}/build-source.json`]);
  const manifest = JSON.parse(readFileSync(`${run}/manifest.json`, 'utf8'));
  const attachments = manifest.flatMap(x => x.attachments);
  for (const [index, capture] of ['03-bidding-east', '06-talon-exchange', '01-lobby'].entries()) {
    const item = attachments.find(x => x.suggestedHumanReadableName.startsWith(capture));
    if (!item || item.isAssociatedWithFailure) throw new Error(`Missing successful capture ${capture}`);
    const target = new URL(`${kind}/${index + 1}-${capture}.png`, output);
    mkdirSync(new URL(`${kind}/`, output), { recursive: true });
    await sharp(`${run}/${item.exportedFileName}`).flatten({ background: '#10271f' }).png().toFile(target.pathname);
    provenance.push({ file: `${kind}/${index + 1}-${capture}.png`, source: `${run}/${item.exportedFileName}`, captureTimestamp: item.timestamp });
  }
}
const width = 5244, height = 2950;
function card(rank, suit, x, y, angle) {
  const color = ['♥', '♦'].includes(suit) ? '#b62e38' : '#152022';
  return `<g transform="translate(${x} ${y}) rotate(${angle} 360 510)"><rect x="18" y="30" width="720" height="1020" rx="48" fill="#000" opacity=".17"/><rect width="720" height="1020" rx="48" fill="#fcfbf4" stroke="#d9d5c7" stroke-width="5"/><text x="65" y="160" font-family="Georgia" font-size="130" font-weight="bold" fill="${color}">${rank}</text><text x="72" y="290" font-size="120" fill="${color}">${suit}</text><text x="360" y="670" text-anchor="middle" font-size="410" fill="${color}">${suit}</text></g>`;
}
const base = `<defs><radialGradient id="b"><stop stop-color="#243f59"/><stop offset="1" stop-color="#091625"/></radialGradient></defs><rect width="5244" height="2950" fill="url(#b)"/><ellipse cx="3250" cy="1550" rx="1910" ry="1110" fill="none" stroke="#d9c38b" stroke-opacity=".17" stroke-width="3"/><ellipse cx="3250" cy="1550" rx="1780" ry="1000" fill="none" stroke="#d9c38b" stroke-opacity=".10" stroke-width="2"/>`;
const a = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">${base}<text x="450" y="1260" font-family="Georgia" font-size="330" fill="#f4eedb">Preferans</text><path d="M470 1390h1170" stroke="#c8ad6f" stroke-width="6"/>${card('J', '♣', 2520, 980, -24)}${card('Q', '♦', 2860, 840, -9)}${card('K', '♥', 3230, 860, 9)}${card('A', '♠', 3550, 1050, 25)}</svg>`;
const b = `<svg xmlns="http://www.w3.org/2000/svg" width="${width}" height="${height}">${base}<text x="460" y="1130" font-family="Georgia" font-size="330" fill="#f4eedb">Preferans</text><path d="M480 1270h1170" stroke="#c8ad6f" stroke-width="6"/><text x="480" y="1550" font-size="170" fill="#c8ad6f">♠  ♥  ♦  ♣</text></svg>`;
mkdirSync(new URL('creatives/', output), { recursive: true });
await sharp(Buffer.from(a)).flatten().png().toFile(new URL('creatives/header-a-cards.png', output).pathname);
const screen = await sharp(new URL('iphone/1-03-bidding-east.png', output).pathname).resize({ height: 2500 }).toBuffer();
await sharp(Buffer.from(b)).composite([{ input: screen, left: 3040, top: 220 }]).flatten().png().toFile(new URL('creatives/header-b-table.png', output).pathname);
writeFileSync(new URL('provenance.json', output), JSON.stringify({ version: '1.0.2', build: 28, sources: provenance,
  creativeVariants: { A: 'Navy card fan and brand', B: 'Same navy background and brand with actual auction UI' },
  preview: 'Real simulator screen recording with a final-frame editorial hold, H.264 30 fps, silent stereo AAC.' }, null, 2));
console.log('Rendered current screenshots and two universal 5244×2950 creative treatments.');
