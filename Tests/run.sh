#!/bin/sh
set -eu
repo_dir=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
test_dir=$(mktemp -d "${TMPDIR:-/tmp}/audiopriority-tests.XXXXXX")
trap 'rm -rf "$test_dir"' EXIT HUP INT TERM
xcrun swiftc -module-cache-path "$test_dir/module-cache" \
    "$repo_dir/AudioPriorityBar/Models/AudioDevice.swift" \
    "$repo_dir/AudioPriorityBar/Models/MicrophoneAutomation.swift" \
    "$repo_dir/AudioPriorityBar/Services/MicrophoneSettingsStore.swift" \
    "$repo_dir/Tests/MicrophoneAutomationTests.swift" \
    -o "$test_dir/microphone-tests"
"$test_dir/microphone-tests"
