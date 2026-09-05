#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/popover-layout.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
app_dir="$test_dir/PopoverLayoutTests.app"
mkdir -p "$app_dir/Contents/MacOS"
cat > "$app_dir/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>app.audioprioritybar.layouttests.$(uuidgen)</string>
<key>CFBundleExecutable</key><string>PopoverLayoutTests</string>
<key>LSUIElement</key><true/>
</dict></plist>
PLIST
if [ "${POPOVER_LAYOUT_HOLD:-0}" = 1 ]; then printf '%s\n' "$app_dir"; fi
# Use the real views and manager, replacing only the app entry point.
sed '/^@main$/d' "$repo_dir/AudioPriorityBar/AudioPriorityBarApp.swift" > "$test_dir/AudioPriorityBarApp.swift"
xcrun swiftc -module-cache-path "$test_dir/modules" \
    "$test_dir/AudioPriorityBarApp.swift" \
    "$repo_dir"/AudioPriorityBar/Models/*.swift \
    "$repo_dir"/AudioPriorityBar/Services/*.swift \
    "$repo_dir"/AudioPriorityBar/Views/*.swift \
    "$repo_dir/Tests/PopoverLayoutTests.swift" \
    -o "$app_dir/Contents/MacOS/PopoverLayoutTests"
"$app_dir/Contents/MacOS/PopoverLayoutTests"
