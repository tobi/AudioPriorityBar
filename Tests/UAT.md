# Microphone automation UAT

Run `sh Tests/run.sh` and a Release build first. Use Custom mode during UI checks so editing rules does not change the system audio route. For isolation, build a preview with a separate bundle identifier and launch with the existing `customMode` preference supplied on the command line:

```sh
xcodebuild -scheme AudioPriorityBar -configuration Release \
  -derivedDataPath .build-preview -arch arm64 ONLY_ACTIVE_ARCH=YES \
  PRODUCT_BUNDLE_IDENTIFIER=app.audioprioritybar.preview PRODUCT_NAME=AudioPriorityBarPreview \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO build
open .build-preview/Build/Products/Release/AudioPriorityBarPreview.app --args -customMode YES
```

Use `-arch x86_64` on an Intel Mac. This uses the normal saved-preference path; there is no test-only audio or access bypass.

## Native controls

1. Open the speaker menu-bar icon. This feature does not change the existing popover sizing. On affected macOS versions the separate popover layout fix is needed to see the device list; the Microphone automation button remains above that list.
2. Open **Microphone automation…**. Check that the titled window remains open when the menu-bar panel closes.
3. Check that rules default to off with fresh preferences, and that the status says manual mode pauses automatic switching.
4. Enable rules. Move Camera microphone earlier, change its condition to When lid is closed, and check that the row stays in place with its condition intact.
5. Scroll to Microphone types. Check that all connected microphones appear and each Auto value has an explanation. USB webcam inputs must not appear as wired headsets just because they use USB.
6. Change a device type, close and reopen the window, and confirm the override remains. Select Auto and confirm the detection result returns.
7. Restart the preview with the same arguments. Confirm rule order, conditions, and overrides persist.
8. Click Restore default rules. Confirm all types appear once and overrides are retained.
9. Verify the system input/output routes remain unchanged during these manual-mode UI actions.

## Physical hardware checks

Run separately when switching the active microphone is acceptable. Use system Sound settings and a call or recorder set to system default to check actual audible input.

- Enable rules outside Custom mode. Order camera before built-in and confirm the active system input changes to the connected camera.
- Configure built-in for lid open and camera for lid closed. Close/open the lid while the Mac stays awake with an external display. Confirm the active system input follows the conditions.
- Unplug the selected device. Confirm the next eligible connected input becomes active.
- Reconnect it and confirm a saved type override still applies. Reorder two devices of the same type and confirm device priority breaks the tie.
- Mark an input Ignore or Never Use, including in Edit mode. Confirm rules exclude it.
- Exclude all connected input types. Confirm the status reports no eligible microphone and the current input stays unchanged.
- Enter Custom mode, reorder inputs and edit rules. Confirm no automatic switch occurs. Leave Custom mode and confirm the rules apply.
- Disable rules and confirm normal device-priority selection returns. Output selection must retain upstream behavior.

Metadata tests simulate Bluetooth, USB headset, virtual/aggregate, missing metadata, and unknown lid cases. Simulation is not proof of audible input or a wireless dongle's physical link state.
