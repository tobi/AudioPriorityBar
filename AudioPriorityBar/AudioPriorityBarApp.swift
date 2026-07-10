import SwiftUI

@main
struct AudioPriorityBarApp: App {
    @StateObject private var audioManager = AudioManager()

    var body: some Scene {
        MenuBarExtra {
            MenuBarView()
                .environmentObject(audioManager)
        } label: {
            Image(systemName: audioManager.menuBarIcon)
        }
        .menuBarExtraStyle(.window)
    }
}
