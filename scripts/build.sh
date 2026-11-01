#!/bin/zsh
# Builds a release copy of Ramus into dist/Ramus.app.
set -euo pipefail
cd "$(dirname "$0")/.."

if command -v xcodegen >/dev/null; then
    xcodegen generate --quiet
fi

xcodebuild \
    -project Ramus.xcodeproj \
    -scheme Ramus \
    -configuration Release \
    -derivedDataPath .build \
    -quiet \
    build

rm -rf dist/Ramus.app
mkdir -p dist
cp -R .build/Build/Products/Release/Ramus.app dist/
echo "Built dist/Ramus.app"
