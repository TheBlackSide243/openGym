// openGym Plus as a Feather / AltStore source: feather/source.json, which Feather reads at
// https://raw.githubusercontent.com/TheBlackSide243/openGym/plus/feather/source.json and installs
// the .ipa of a release from. Run after publishing a plus release, then commit the file on plus:
//
//   node feather/update-source.mjs <version> <path/to/openGym-plus-unsigned.ipa> "<what changed>"
//
// The newest version goes first; the last ten are kept. The .ipa is read only for its size.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [version, ipa, notes = ''] = process.argv.slice(2);
if (!version || !ipa) {
  console.error('usage: node feather/update-source.mjs <version> <ipa> "<what changed>"');
  process.exit(1);
}
const REPO = 'TheBlackSide243/openGym';
const file = path.join(path.dirname(fileURLToPath(import.meta.url)), 'source.json');
const src = JSON.parse(fs.readFileSync(file, 'utf8'));
const app = src.apps[0];
const entry = {
  version,
  buildVersion: app.versions?.[0]?.buildVersion || '1',
  date: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
  localizedDescription: notes,
  downloadURL: `https://github.com/${REPO}/releases/download/plus-${version}/openGym-plus-unsigned.ipa`,
  size: fs.statSync(ipa).size,
  minOSVersion: app.versions?.[0]?.minOSVersion || '15.5',
};
app.versions = [entry, ...(app.versions || []).filter(v => v.version !== version)].slice(0, 10);
// The fields older AltStore readers (and some Feather builds) take from the app itself.
Object.assign(app, { version: entry.version, versionDate: entry.date, versionDescription: entry.localizedDescription, downloadURL: entry.downloadURL, size: entry.size });
fs.writeFileSync(file, JSON.stringify(src, null, 2) + '\n');
console.log(`feather/source.json: ${version}, ${entry.size} bytes`);
