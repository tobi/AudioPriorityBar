# Popover layout regression checks

Build with `./build.sh`. Run the target app in Custom mode so opening the menu does not change the selected audio devices. With macOS Accessibility access for the terminal, run:

```sh
osascript Tests/popover-uat.applescript AudioPriorityBar "MacBook Air Microphone"
```

Replace the process name and optional device name for the test machine. The script checks a normal-display list viewport, checks the named rows, closes the panel, then opens and checks it again. The original layout fails with height 0 on affected macOS versions.

## Constrained height

```sh
sh Tests/run-popover-layout-tests.sh
```

This compiles the real views and manager with a separate test entry point and a unique preference domain. It enables the existing Custom mode before manager construction and replaces only the displayed rows with fixtures. It does not select or change system audio devices.

For 3 and 20 input rows, the test supplies display height limits of 553, 400, and 300 points. It checks that both the native panel and its fitting height stay within that limit without collapsing. The previous fixed 420-point viewport produces a 553-point panel and fails the 400-point case.

To inspect the final 300-point case, including the footer and scrolling:

```sh
POPOVER_LAYOUT_HOLD=1 sh Tests/run-popover-layout-tests.sh
```

While the fixture is open, `osascript Tests/popover-uat.applescript PopoverLayoutTests --window-only` checks its viewport and that all top-level buttons lie inside the native panel bounds.

The command prints the temporary app path and leaves the fixture visible for two minutes. Check that Login, Edit, and Quit remain visible and that scrolling reaches Test microphone 20. This is a constrained-window test, not a physical display-resolution change.

The app takes the visible height of the popover's own screen and reserves 160 points for its fixed header/footer and edge clearance. It caps the remaining list area at 420 points. The screen observer updates the budget when display parameters or the window's screen change. Check opening on each display after changing scaling or Dock placement when those configurations are available.
