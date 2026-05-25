cask "tymeline" do
  version "0.1.0"
  sha256 "0e5308852bf1a8b90f98410c3bcf4eaa8edfa25521ea622c14124fa7cbdaf08e"

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
