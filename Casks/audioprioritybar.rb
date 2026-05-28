cask "audioprioritybar" do
  version "1.2.1"
  sha256 "f29f23d8cfcb90765aa5716983254d8aa6ac3c725de87b3aed8614eef0873bc0"

  url "https://github.com/tobi/AudioPriorityBar/releases/download/v#{version}/AudioPriorityBar.zip"
  name "Audio Priority Bar"
  desc "Manage audio device priorities from the menu bar"
  homepage "https://github.com/tobi/AudioPriorityBar"

  livecheck do
    url :url
    strategy :github_latest
  end

  depends_on macos: :ventura

  app "AudioPriorityBar.app"

  zap trash: [
    "~/Library/Preferences/app.audioprioritybar.plist",
    "~/Library/Saved Application State/app.audioprioritybar.savedState",
  ]
end
