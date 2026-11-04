#!/bin/sh
# openGym Plus beside openGym on the same iPhone: its own bundle ids (ch.opengym.plus, and the watch
# app's, the widgets', the downloader's under it) and its own App Group, so installing Plus never
# replaces the official app, and "openGym Plus" under the icon. plus-ipa.yml runs it after the ruby
# scripts, which write the extensions' ids into the project, and before the archive. The committed
# files keep openGym's ids, so merging a new openGym brings no conflicts here.
set -eu
cd "$(dirname "$0")/../App"
FROM='ch\.opengym\.app'
TO='ch.opengym.plus'
grep -rlI --exclude-dir=Pods --exclude-dir=build "$FROM" . | while IFS= read -r f; do
  sed -i '' "s/$FROM/$TO/g" "$f"
  echo "  $f"
done
for p in App/Info.plist Watch/Info.plist; do
  /usr/libexec/PlistBuddy -c 'Set :CFBundleDisplayName openGym Plus' "$p"
done
if grep -rnI --exclude-dir=Pods --exclude-dir=build "$FROM" .; then
  echo "openGym's ids are still above"
  exit 1
fi
grep -n 'PRODUCT_BUNDLE_IDENTIFIER' App.xcodeproj/project.pbxproj | sort -u -k2
