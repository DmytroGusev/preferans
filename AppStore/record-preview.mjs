import { spawn } from 'node:child_process';
import { createWriteStream, mkdirSync } from 'node:fs';

const device = process.env.DEST_ID;
if (!device) throw new Error('Set DEST_ID to an iPhone simulator UDID.');
const derived = process.env.DERIVED || '/tmp/preferans28-simderived';
const directory = new URL('../build/media/', import.meta.url);
mkdirSync(directory, { recursive: true });
const log = createWriteStream(new URL('preview-record.log', directory));
let recorder;
let captured = false;
let stopping = false;
let recordingDone = Promise.resolve();
const stop = () => { if (recorder && !stopping) { stopping = true; recorder.kill('SIGINT'); } };
const test = spawn('xcodebuild', ['test-without-building', '-project', 'Preferans.xcodeproj', '-scheme', 'Preferans',
  '-destination', `platform=iOS Simulator,id=${device}`, '-derivedDataPath', derived, '-parallel-testing-enabled', 'NO',
  '-test-timeouts-enabled', 'YES', '-default-test-execution-time-allowance', '60', '-maximum-test-execution-time-allowance', '90',
  '-only-testing:PreferansUITests/RedesignScreenshotTests/testRecordAppStorePreview'], { stdio: ['ignore', 'pipe', 'pipe'] });
let lines = '';
function output(data) {
  log.write(data);
  lines += data.toString();
  if (lines.includes('PREFERANS_PREVIEW_START') && !recorder) {
    captured = true;
    recorder = spawn('xcrun', ['simctl', 'io', device, 'recordVideo', '--codec=h264', '--force', new URL('preview-raw.mp4', directory).pathname], { stdio: 'ignore' });
    recordingDone = new Promise((resolve, reject) => { recorder.on('error', reject); recorder.on('exit', resolve); });
    console.log('Recording real game interface.');
  }
  if (lines.includes('PREFERANS_PREVIEW_END')) stop();
  lines = lines.slice(-1000);
}
test.stdout.on('data', output); test.stderr.on('data', output);
const deadline = setTimeout(() => { stop(); test.kill('SIGTERM'); }, 150000);
test.on('exit', async code => {
  clearTimeout(deadline); stop(); await recordingDone; log.end();
  if (code !== 0 || !captured) { console.error('Recording test failed; inspect build/media/preview-record.log'); process.exitCode = 1; }
  else console.log('Recorded build/media/preview-raw.mp4');
});
