#!/bin/sh
# device.sh builds Snack, signs it for development, installs it on the iPhone
# plugged in (or the one DEVICE=<udid> names) and opens it.
#
# Signing needs Xcode signed in to the developer account (Xcode › Settings ›
# Accounts). The first build makes the App ID, the iCloud container
# iCloud.com.kadaliao.snack and the profile; an App Store Connect API key
# cannot make an iCloud container, so the account has to be there.
set -eu
here=$(cd "$(dirname "$0")/.." && pwd)

if [ -z "${DEVICE:-}" ]; then
	list=$(mktemp)
	xcrun devicectl list devices --json-output "$list" >/dev/null
	DEVICE=$(/usr/bin/python3 -I -c '
import json, sys
for d in json.load(open(sys.argv[1]))["result"]["devices"]:
    hw = d.get("hardwareProperties", {})
    if hw.get("platform") == "iOS" and hw.get("reality") == "physical" and d.get("connectionProperties", {}).get("pairingState") == "paired":
        print(hw.get("udid", "")); break
' "$list")
	rm -f "$list"
fi
[ -n "$DEVICE" ] || { echo "no paired iPhone: plug one in, or pass DEVICE=<udid>" >&2; exit 1; }

(cd "$here" && xcodegen generate --quiet)
echo "[1/3] 编译并签名"
xcodebuild -project "$here/Snack.xcodeproj" -scheme Snack -configuration Debug \
	-destination "id=$DEVICE" -derivedDataPath "$here/build/device" -allowProvisioningUpdates build -quiet
echo "[2/3] 安装"
xcrun devicectl device install app --device "$DEVICE" "$here/build/device/Build/Products/Debug-iphoneos/Snack.app" >/dev/null
echo "[3/3] 打开"
xcrun devicectl device process launch --device "$DEVICE" com.kadaliao.snack >/dev/null
echo "已装到手机上并打开"
