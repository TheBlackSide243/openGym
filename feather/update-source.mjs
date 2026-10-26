// openGym Plus as a Feather / AltStore source: feather/apps.json, which Feather reads at
// https://raw.githubusercontent.com/TheBlackSide243/openGym/plus/feather/apps.json and installs
// the .ipa of a release from. Run after publishing a plus release, then commit the file on plus:
//
//   node feather/update-source.mjs <version> <path/to/openGym-plus-unsigned.ipa>
//
// Only the fields Feather's own source has: Feather on the iPhone refused this source while it
// also carried build numbers, minimum iOS, permissions and a category. The newest version goes
// first; the last ten are kept. The .ipa is read only for its size. It writes apps.json and
// source.json, the same bytes: never remove or rename either, a Feather that added one keeps it.
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const [version, ipa] = process.argv.slice(2);
if (!version || !ipa) {
  console.error('usage: node feather/update-source.mjs <version> <ipa>');
  process.exit(1);
}
const REPO = 'TheBlackSide243/openGym';
const file = path.join(path.dirname(fileURLToPath(import.meta.url)), 'apps.json');
const src = JSON.parse(fs.readFileSync(file, 'utf8'));
const app = src.apps[0];
const entry = {
  version,
  date: new Date().toISOString().replace(/\.\d+Z$/, 'Z'),
  size: fs.statSync(ipa).size,
  downloadURL: `https://github.com/${REPO}/releases/download/plus-${version}/openGym-plus-unsigned.ipa`,
};
app.versions = [entry, ...(app.versions || []).filter(v => v.version !== version)].slice(0, 10);
// The same, on the app itself, for readers that look there.
Object.assign(app, { version: entry.version, versionDate: entry.date, size: entry.size, downloadURL: entry.downloadURL });
// Written at both addresses the source has had, the same bytes: a Feather keeps the address it
// added the source from and spins forever if that one goes. Neither file is ever removed.
for (const name of ['apps.json', 'source.json']) {
  fs.writeFileSync(path.join(path.dirname(file), name), JSON.stringify(src, null, 2) + '\n');
}
console.log(`feather/apps.json: ${version}, ${entry.size} bytes`);
