# Audio Priority Bar

<p align="center">
  <img src="icon.png" width="128" height="128" alt="Audio Priority Bar Icon">
</p>

A native macOS menu bar app that automatically manages audio device priorities. Set your preferred order for output and input devices - the app automatically switches each role to the highest-priority connected device.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

## Features

- **Priority-based auto-switching**: Devices are ranked by priority. When a higher-priority eligible device connects, it automatically becomes active for that role.
- **Output and input priority lists**: Output devices share one priority list, and input devices share a separate priority list.
- **Independent automation**: Output and Input Auto-switch can be enabled or disabled without affecting the other role.
- **Pause all automation**: Temporarily stop both roles, then resume their unchanged individual settings.
- **Role-specific auto-use controls**: Disable automatic use for input or output without affecting the other role.
- **Device memory**: Remembers all devices you've ever connected, even when disconnected. Edit mode shows disconnected devices with "last seen" timestamps.
- **Per-role ignore**: Hide a device from the normal list and exclude it from automatic selection for that role.
- **Drag-to-reorder**: Reorder devices by dragging the priority handle.
- **Volume control**: Adjust volume with slider or scroll wheel.
- **Menu bar integration**: Shows audio status from the macOS menu bar.

## Installation

### Requirements
- macOS 13.0 (Ventura) or later

### Build from Source

1. Clone the repository:
   ```bash
   git clone https://github.com/tobi/AudioPriorityBar.git
   cd AudioPriorityBar
   ```

2. Build using the build script:
   ```bash
   ./build.sh
   ```

3. The app will be at `dist/AudioPriorityBar.app`

Or open `AudioPriorityBar.xcodeproj` in Xcode and build with ⌘R.

### Download Release
Check the [Releases](https://github.com/tobi/AudioPriorityBar/releases) page for pre-built binaries.

## Usage

### Priority Roles

The menu shows two priority lists:

- **Output**: All output devices in priority order. Row 1 is the highest-priority output.
- **Input**: All input devices in priority order. Row 1 is the highest-priority input.

Changing input priority does not change output priority, and changing output priority does not change input priority.

### Common setup: headphones for output, USB microphone for input

1. Connect your Bluetooth headphones and external USB microphone.
2. In **Output**, drag the Bluetooth headphones to the top of the output priority list.
3. In **Input**, drag the external USB microphone to the top of the input priority list.
4. If the Bluetooth headset microphone appears in **Input**, use its row menu and choose **Never use as input**, or leave it below the external microphone as a fallback.
5. Leave built-in Mac devices lower in their input/output lists so they remain available as fallbacks.
6. If a display, dock, or audio interface exposes both input and output, configure each role separately from its own row/list.

### Managing Priorities

- **Click a device**: When Auto-switch is on for that role, moves the device to #1 priority and selects it. When Auto-switch is off or all automation is paused, selects it without changing saved priority.
- **Drag devices**: Reorder by dragging the handle

### Device Actions (hover menu)

- **Ignore as input/output**: Hide the device and exclude it from automatic selection for that role
- **Never use as input/output**: Keep the device visible, but skip it when auto-selecting that role
- **Allow auto-use as input/output**: Let the app automatically select that role for the device again
- **Forget Device**: Remove disconnected device from memory

### Automation controls

- **Output Auto-switch**: Controls automatic Output selection only.
- **Input Auto-switch**: Controls automatic Input selection only.
- **Pause all auto-switching**: Temporarily stops both Output and Input automation without changing either role's setting. Resume restores the same role settings.

Each device list scrolls independently when it contains more devices than fit in the menu. Section controls and the footer stay visible.

### Edit Mode

Click "Edit" in the footer to:
- See all devices ever connected (disconnected ones grayed out)
- See ignored devices and stop ignoring them
- Change Auto-use eligibility for connected or remembered devices
- Reorder disconnected devices in the priority list
- View "last seen" timestamps
- Forget old devices you no longer use

## How It Works

1. **Device Discovery**: Uses CoreAudio to enumerate audio devices and listen for changes.
2. **Priority Storage**: Device priorities are stored in UserDefaults, keyed by CoreAudio device UID (stable across reconnects).
3. **Role-Specific Auto-Use**: Input and output auto-use settings are stored separately, so disabling automatic input use does not disable output use for the same device.
4. **Auto-Switching**: When devices connect/disconnect, each enabled role automatically selects its highest-priority connected device that is neither ignored nor set to Auto-use off, unless all automation is paused.

When upgrading from an older version with global "Never Use" settings, those devices are migrated to auto-use off for both input and output to preserve prior behavior. You can then allow auto-use for input or output independently from the device row menu.

When upgrading from an older version with separate speaker and headphone output priority lists, those lists are merged into one Output priority list. The list for the previously active mode is placed first, followed by the other list, with duplicates removed. A missing or invalid legacy mode uses the older app's default Speakers mode. Existing unified Output priorities remain authoritative, and all legacy keys are left in place.

Older Custom/Manual automation settings are migrated to the new role controls while preserving their effective behavior. Legacy preference keys remain in place.

On a new install, the app waits for you to set a priority list before auto-selecting a role. This avoids changing the current macOS input or output based only on CoreAudio enumeration order.

## Project Structure

```
AudioPriorityBar/
├── AudioPriorityBarApp.swift    # App entry, MenuBarExtra, AudioManager
├── Models/
│   └── AudioDevice.swift        # Device model
├── Services/
│   ├── AudioDeviceService.swift # CoreAudio wrapper
│   └── PriorityManager.swift    # Priority persistence
└── Views/
    ├── AdaptiveDeviceListLayout.swift # Screen-bounded list height allocation
    ├── MenuBarView.swift        # Main popover UI
    └── DeviceListView.swift     # Device list and row components
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built with SwiftUI and CoreAudio for macOS.
