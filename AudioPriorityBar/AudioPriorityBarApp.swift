import SwiftUI
import CoreAudio

@main
struct AudioPriorityBarApp: App {
    @StateObject private var audioManager = AudioManager()
    @StateObject private var nowPlayingService = NowPlayingService()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(audioManager)
                .environmentObject(nowPlayingService)
        } label: {
            MenuBarLabel(
                volume: audioManager.volume,
                isOutputMuted: audioManager.isActiveOutputMuted,
                isInputMuted: audioManager.isActiveInputMuted,
                isCustomMode: audioManager.isCustomMode,
                mode: audioManager.currentMode,
                micFlash: audioManager.micFlashState
            )
        }
        .menuBarExtraStyle(.window)
    }
}

// MARK: - Menu Bar Icon

struct MenuBarLabel: View {
    let volume: Float
    let isOutputMuted: Bool
    let isInputMuted: Bool
    let isCustomMode: Bool
    let mode: OutputCategory
    let micFlash: Bool

    var body: some View {
        HStack(spacing: 2) {
            if isInputMuted {
                Image(systemName: micFlash ? "mic.fill" : "mic.slash.fill")
            }
            if isCustomMode {
                Image(systemName: "hand.raised.fill")
            } else if mode == .headphone {
                Image(systemName: "headphones")
            }
            // Speaker with volume always last
            if isOutputMuted {
                Image(systemName: "speaker.slash.fill")
            } else {
                Image(systemName: "speaker.wave.3.fill", variableValue: Double(volume))
            }
        }
    }
}

// MARK: - Volume Meter (for potential future use)

struct VolumeMeterView: View {
    let volume: Float
    let isMuted: Bool

    private let barCount = 4
    private let barSpacing: CGFloat = 1

    var body: some View {
        Canvas { context, size in
            let barWidth = (size.width - CGFloat(barCount - 1) * barSpacing) / CGFloat(barCount)
            let filledBars = isMuted ? 0 : Int(ceil(Double(volume) * Double(barCount)))

            for i in 0..<barCount {
                let x = CGFloat(i) * (barWidth + barSpacing)
                let barHeight = size.height * CGFloat(i + 1) / CGFloat(barCount)
                let y = size.height - barHeight

                let rect = CGRect(x: x, y: y, width: barWidth, height: barHeight)
                let path = Path(roundedRect: rect, cornerRadius: 1)

                if i < filledBars {
                    context.fill(path, with: .color(isMuted ? .red : .primary))
                } else {
                    context.fill(path, with: .color(.primary.opacity(0.25)))
                }
            }
        }
    }
}
