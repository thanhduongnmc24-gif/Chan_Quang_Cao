#!/usr/bin/env bash
set -euo pipefail

echo "==> [1/4] Generating Xcode project via XcodeGen..."
xcodegen generate

echo "==> [2/4] Building AdShieldPro (Release - iphoneos, unsigned)..."
xcodebuild clean build \
  -project AdShieldPro.xcodeproj \
  -scheme AdShieldPro \
  -configuration Release \
  -sdk iphoneos \
  -derivedDataPath build \
  CODE_SIGN_IDENTITY="" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO

echo "==> [3/4] Packaging Payload into AdShieldPro-Unsigned.ipa..."
rm -rf Payload AdShieldPro-Unsigned.ipa
mkdir -p Payload
cp -R "build/Build/Products/Release-iphoneos/AdShieldPro.app" Payload/
zip -r9 AdShieldPro-Unsigned.ipa Payload
rm -rf Payload

echo "==> [4/4] Done! Output: AdShieldPro-Unsigned.ipa"
