# tymeline

macOS menubar app that watches Linear issue status changes and automatically starts/stops Clockify timers, so time tracking happens with zero manual steps.

**Status:** Pre-release, v1 in active development. See [DESIGN.md](DESIGN.md) for the full spec, scope, and roadmap.

## Why

If you track time in Clockify against tasks in Linear, you probably forget to start the timer about half the time. tymeline watches your assigned Linear issues; when one moves to In Progress, the corresponding Clockify timer starts. When it moves to Done, the timer stops. That's it.

- No central server, no telemetry
- API keys live only in macOS Keychain
- Multi-workspace support (work + personal, multiple clients, etc.)

## Install

```bash
brew tap darioristic/tymeline https://github.com/darioristic/tymeline
brew install --cask darioristic/tymeline/tymeline
```

The clock icon appears in your menubar. Open it and pick **Settings** to add
a workspace.

The cask installs an ad-hoc signed build (no paid Apple Developer ID), so
the postflight step automatically strips the `com.apple.quarantine`
attribute. No right-click-Open dance needed.

### Other ways to install

<details>
<summary>Download the .app directly from GitHub Releases</summary>

1. Grab the latest `tymeline-vX.Y.Z-macos.zip` from
   [Releases](https://github.com/darioristic/tymeline/releases).
2. Unzip and drag `tymeline.app` into `/Applications`.
3. First launch: right-click the app → **Open** to clear Gatekeeper.
   Alternatively: `xattr -dr com.apple.quarantine /Applications/tymeline.app`.
</details>

<details>
<summary>Build from source with the install script</summary>

For developers who want to run the very latest `main`:

```bash
git clone https://github.com/darioristic/tymeline.git
cd tymeline
./scripts/install.sh
```

The script generates the Xcode project with
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (installs it via Homebrew
if missing), builds the Release configuration with ad-hoc signing, installs
into `/Applications`, strips the quarantine attribute, and launches the
app. Requires macOS 14+ and Xcode 16+.
</details>

### Uninstall

```bash
brew uninstall --cask tymeline
```

Or remove `/Applications/tymeline.app` by hand. Either way, your API keys
remain in macOS Keychain until you remove the workspace from Settings before
uninstalling — `brew uninstall ... --zap` clears the app's Application
Support and Preferences but not the Keychain entries (by design — Keychain
items can be shared across reinstalls).

## Develop

Requires macOS 14+, Xcode 16+, Swift 6.

```bash
git clone https://github.com/darioristic/tymeline.git
cd tymeline
brew install xcodegen   # one-time
xcodegen generate
open tymeline.xcodeproj
```

The Xcode project is generated from [project.yml](project.yml) — if you add
or remove source files, re-run `xcodegen generate`.

## License

MIT - see [LICENSE](LICENSE).
