cask "tymeline" do
  version "0.1.31"
  sha256 "9be4bc5de5fe282df7c7405cef9ffb1faf3d05298ce827e145ec3383a0e3afa8"

  url "https://github.com/darioristic/tymeline/releases/download/v#{version}/tymeline-v#{version}-macos.zip"
  name "tymeline"
  desc "Menubar app that syncs Linear issues to Clockify timers"
  homepage "https://github.com/darioristic/tymeline"

  depends_on macos: ">= :sonoma"

  app "tymeline.app"

  postflight do
    system "xattr", "-cr", "#{appdir}/tymeline.app"
  end

  zap trash: [
    "~/Library/Application Support/tymeline",
    "~/Library/Preferences/app.tymeline.plist",
  ]
end
