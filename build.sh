#!/bin/bash
set -e

DEPLOY=false
for arg in "$@"; do
  if [ "$arg" = "-deploy" ]; then
    DEPLOY=true
  fi
done

echo "Building AudioPriorityBar..."

xcodebuild -scheme AudioPriorityBar \
  -configuration Release \
  -derivedDataPath .build \
  -arch arm64 -arch x86_64 \
  ONLY_ACTIVE_ARCH=NO \
  CODE_SIGN_IDENTITY="-" \
  CODE_SIGNING_REQUIRED=NO \
  CODE_SIGNING_ALLOWED=NO \
  build

mkdir -p dist
rm -rf dist/AudioPriorityBar.app
cp -R .build/Build/Products/Release/AudioPriorityBar.app dist/

echo ""
echo "Build complete: dist/AudioPriorityBar.app"

if [ "$DEPLOY" = true ]; then
  echo ""
  echo "Deploying to /Applications..."

  pkill -x AudioPriorityBar 2>/dev/null || true

  rm -rf /Applications/AudioPriorityBar.app
  cp -R dist/AudioPriorityBar.app /Applications/

  open /Applications/AudioPriorityBar.app

  echo "Deployed and launched: /Applications/AudioPriorityBar.app"
fi
