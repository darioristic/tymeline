cask "tymeline" do
  version "0.1.15"
  sha256 "937144b6d073fb6c05c37d61f35b4abd6e937aaac8930c1d1961f50d763e6356"

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
