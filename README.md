# Audio Priority Bar

<p align="center">
  <img src="icon.png" width="128" height="128" alt="Audio Priority Bar Icon">
</p>

A native macOS menu bar app that intelligently manages your audio devices. Organize speakers, headphones, and microphones by priority, and let the app automatically switch to your preferred device when you plug it in. Perfect for users who frequently switch between multiple audio setups.

![macOS 13+](https://img.shields.io/badge/macOS-13%2B-blue)
![Swift](https://img.shields.io/badge/Swift-5.9-orange)
![License](https://img.shields.io/badge/license-MIT-green)

![Screenshot](screenshot.jpeg)

## Features

### Smart Audio Management
- **Priority-based auto-switching**: Rank your devices by preference. When you connect a higher-priority device, it automatically becomes active - no manual switching needed.
- **Dual-mode operation**: Separate priority lists for speakers and headphones. Switch modes manually or enable quick-switch for one-click toggling.
- **Fast switching**: Enable quick-switch mode in preferences to toggle between speakers and headphones with a single left-click on the menu bar icon. Only switches when devices are available in the target mode.
- **Manual mode**: Toggle "Custom" mode (✋ hand icon) to disable auto-switching and control devices manually.
- **Persistent device memory**: Remembers every device you've connected, even when unplugged. Maintains priority order and preferences across reconnections.

### Volume & Mute Controls
- **Integrated volume control**: Adjust output volume via slider, scroll wheel, or system keys.
- **Smart mute handling**: Click the volume icon to mute/unmute. Adjusting volume automatically unmutes if currently muted.
- **Visual feedback**: Menu bar icon shows current mode, volume level, mute status, and microphone state.

### Device Organization
- **Drag-to-reorder**: Reorder devices by dragging or using up/down arrows.
- **Per-category customization**: Assign output devices to speaker or headphone categories. Hide devices from specific categories without affecting others.
- **Device filtering**: Hide devices you don't use or mark them as "never use" to exclude them from auto-switching.
- **Preferred input pairing**: Assign specific microphones to specific output devices for automatic switching.

### Edit Mode & History
- **Comprehensive edit mode**: See all devices ever connected, including disconnected ones (shown grayed out).
- **Timestamp tracking**: View "last seen" timestamps for disconnected devices.
- **Device management**: Forget old devices you no longer use to keep your lists clean.

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

### Operating Modes

| Mode | Icon | Behavior |
|------|------|----------|
| **Speakers** | 🔊 | Shows speaker devices, auto-switches to highest priority |
| **Headphones** | 🎧 | Shows headphone devices, auto-switches to highest priority |
| **Custom** | ✋ | Shows all devices, disables auto-switching for manual control |

### Quick Access (Menu Bar Icon)

- **Left-click**: Open main menu (default) or toggle speaker/headphone mode (if quick-switch enabled in preferences)
- **Right-click**: Always opens main menu when quick-switch is enabled
- **Icon display**: Shows current mode icon, volume level, mute status (🔇), and microphone mute indicator

### Volume & Mute

- **Volume slider**: Drag to adjust output volume
- **Scroll wheel**: Hover over volume slider and scroll to adjust
- **Volume icon**: Click to toggle mute/unmute
- **Smart unmute**: Adjusting volume when muted automatically unmutes

### Managing Device Priorities

- **Click a device**: Makes it active and moves it to #1 priority (in auto-switch modes) or just selects it (in custom mode)
- **Drag to reorder**: Grab the handle (≡) and drag devices up/down
- **Arrow controls**: Hover over a device to reveal up/down arrows for fine-tuning order
- **Reordering behavior**: In speaker/headphone modes, moving a device to #1 automatically activates it

### Device Actions (Edit Mode Menu)

- **Move to Speakers/Headphones**: Re-categorize output devices
- **Ignore as [category]**: Hide device from current category only
- **Ignore entirely**: Hide from both speaker and headphone categories
- **Never use**: Exclude device from auto-switching but keep it visible
- **Set preferred input**: Pair a specific microphone with an output device
- **Forget device**: Remove disconnected device from app memory

### Edit Mode

Click **Edit** in the footer to access advanced features:
- View all devices ever connected, including disconnected ones (grayed out with timestamps)
- Reorder disconnected devices to set their priority for when they reconnect
- Manage hidden/ignored devices
- Forget old devices you no longer use
- Click **Done** to return to normal view

### Preferences

Click the **⚙️ gear icon** in the footer to access preferences:

**Startup**
- **Launch at Login**: Automatically start Audio Priority Bar when you log in to macOS

**Menu Bar**
- **Quick Switch Mode**: Enable single-click toggle between speakers/headphones (requires app restart)

**System Audio**
- **Sync System Sound Effects Output**: Automatically update macOS system sound effects output to match selected device

**Auto-Switching**
- View information about auto-switching behavior and mode controls

## How It Works

1. **Device Discovery**: Uses CoreAudio to enumerate audio devices and listen for hardware changes in real-time.
2. **Priority Storage**: Device priorities, categories, and preferences are stored in UserDefaults, keyed by device UID (stable across reconnects).
3. **Smart Auto-Switching**: When devices connect/disconnect, the app automatically selects the highest-priority available device for the current mode, while avoiding switching loops.
4. **Category System**: Each output device is assigned to either "speaker" or "headphone" category, each with independent priority lists and visibility settings.
5. **Mute & Volume Management**: Volume and mute state are managed through CoreAudio's VirtualMainVolume property. The app automatically unmutes when volume is adjusted and prevents fast-switching to unavailable device categories.
6. **Preferred Input Pairing**: Output devices can be paired with specific input devices for automatic microphone switching based on audio output.

## Project Structure

```
AudioPriorityBar/
├── AudioPriorityBarApp.swift    # App entry, MenuBarExtra, AudioManager
├── Models/
│   └── AudioDevice.swift        # Device model, OutputCategory enum
├── Services/
│   ├── AudioDeviceService.swift # CoreAudio wrapper
│   └── PriorityManager.swift    # Priority persistence
└── Views/
    ├── MenuBarView.swift        # Main popover UI
    └── DeviceListView.swift     # Device list and row components
```

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - see [LICENSE](LICENSE) for details.

## Acknowledgments

Built with SwiftUI and CoreAudio for macOS.
