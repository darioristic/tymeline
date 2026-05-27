cask "tymeline" do
  version "0.1.26"
  sha256 "7ae451d203c238a6736830c961f479d747777e76c86e5f7bc11e311dcdf77e10"

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
