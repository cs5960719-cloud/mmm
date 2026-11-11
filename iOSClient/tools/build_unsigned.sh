#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [ "$(uname -s)" != Darwin ]; then
  echo 'This script requires macOS and Xcode (a cloud macOS runner is supported).' >&2
  exit 1
fi
xcodebuild -project Lanpangzi.xcodeproj -scheme Lanpangzi \
  -configuration Release -sdk iphoneos -destination 'generic/platform=iOS' \
  -derivedDataPath build/Device CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
mkdir -p build/package/Payload
ditto build/Device/Build/Products/Release-iphoneos/Lanpangzi.app build/package/Payload/Lanpangzi.app
cd build/package
ditto -c -k --keepParent Payload ../Lanpangzi-unsigned.ipa
echo 'Created build/Lanpangzi-unsigned.ipa. This file requires signing before installation.'
