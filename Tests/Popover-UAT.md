# Popover layout regression check

Build with `./build.sh`. Run the target app in Custom mode so opening the menu does not change the selected audio devices. With macOS Accessibility access for the terminal, run:

```sh
osascript Tests/popover-uat.applescript AudioPriorityBar "MacBook Air Microphone"
```

Replace the process name and optional device name for the test machine. The script checks that the list viewport is at least 200 points high, checks the named rows, closes the panel, then opens and checks it again. The original layout fails the height check on affected macOS versions.

Also check the actual panel with few devices and in Edit mode with enough remembered devices to require scrolling. Confirm that the footer is visible and that scrolling reaches the last row. The fixed 420-point viewport intentionally leaves space when a list is short; this preserves scrolling without adding a content-measurement mechanism.

The regression depends on native MenuBarExtra layout; a source-text assertion would not detect it. The script checks the rendered native viewport instead.
