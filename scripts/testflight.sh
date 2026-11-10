#!/bin/sh
# testflight.sh archives Snack, signs it for the App Store and uploads it to
# App Store Connect; then beta-review.sh hands it to the testers.
#
#   ASC_KEY_ID=<key id> ASC_ISSUER_ID=<issuer id> scripts/testflight.sh
#
# Signing goes through the account Xcode is signed in to (Xcode › Settings ›
# Accounts): the app has iCloud, CloudKit and an App Group, which an App Store
# Connect API key cannot set up. The upload uses the API key, read from
# ~/.appstoreconnect/private_keys/AuthKey_<key id>.p8 (or ASC_KEY_PATH).
#
# Every upload needs a build number above the last one: raise
# CURRENT_PROJECT_VERSION in project.yml, or pass BUILD_NUMBER=<n>.
set -eu
: "${ASC_KEY_ID:?set ASC_KEY_ID to the App Store Connect API key ID}"
: "${ASC_ISSUER_ID:?set ASC_ISSUER_ID to the API key issuer ID}"
here=$(cd "$(dirname "$0")/.." && pwd)
out=$here/build/release
build=${BUILD_NUMBER:+CURRENT_PROJECT_VERSION=$BUILD_NUMBER}

"$here/scripts/app-id.sh" >/dev/null
(cd "$here" && xcodegen generate --quiet)
rm -rf "$out"
mkdir -p "$out"

echo "[1/3] 归档"
# shellcheck disable=SC2086 # build is a list of words
xcodebuild archive -project "$here/Snack.xcodeproj" -scheme Snack -configuration Release \
	-destination 'generic/platform=iOS' -archivePath "$out/Snack.xcarchive" -allowProvisioningUpdates $build -quiet

echo "[2/3] 导出"
cat >"$out/ExportOptions.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>method</key>
	<string>app-store-connect</string>
	<key>signingStyle</key>
	<string>automatic</string>
	<key>teamID</key>
	<string>HMDAVG9B8J</string>
	<key>uploadSymbols</key>
	<true/>
</dict>
</plist>
PLIST
xcodebuild -exportArchive -archivePath "$out/Snack.xcarchive" -exportPath "$out/export" \
	-exportOptionsPlist "$out/ExportOptions.plist" -allowProvisioningUpdates -quiet

echo "[3/3] 上传"
xcrun altool --upload-app -f "$out/export/Snack.ipa" -t ios --apiKey "$ASC_KEY_ID" --apiIssuer "$ASC_ISSUER_ID"
plist=$out/Snack.xcarchive/Info.plist
version=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleShortVersionString' "$plist")
number=$(/usr/libexec/PlistBuddy -c 'Print :ApplicationProperties:CFBundleVersion' "$plist")
echo "已上传 $version ($number)，内部测试处理完就能装"

echo
"$here/scripts/beta-review.sh" "$version" "$number"
