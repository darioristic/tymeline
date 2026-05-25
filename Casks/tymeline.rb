cask "tymeline" do
  version "0.1.6"
  sha256 "a73d8fd2fae609e85feca08ad84d61e19ebd5fb0ab13a5d9a904de9fc8de671b"

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
