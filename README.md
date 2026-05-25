# tymeline

macOS menubar app that watches Linear issue status changes and automatically starts/stops Clockify timers, so time tracking happens with zero manual steps.

**Status:** Pre-release, v1 in active development. See [DESIGN.md](DESIGN.md) for the full spec, scope, and roadmap.

## Why

If you track time in Clockify against tasks in Linear, you probably forget to start the timer about half the time. tymeline watches your assigned Linear issues; when one moves to In Progress, the corresponding Clockify timer starts. When it moves to Done, the timer stops. That's it.

- No central server, no telemetry
- API keys live only in macOS Keychain
- Multi-workspace support (work + personal, multiple clients, etc.)

## Install

Pick whichever is easiest for you. All three install the same `tymeline.app`
into `/Applications`. Builds are ad-hoc signed (no paid Apple Developer ID),
which means Gatekeeper will ask for confirmation on first launch — see the
note at the bottom of this section.

### 1. Download from GitHub Releases (recommended)

1. Grab the latest `tymeline-vX.Y.Z-macos.zip` from
   [Releases](https://github.com/darioristic/tymeline/releases).
2. Unzip and drag `tymeline.app` into `/Applications`.
3. First launch: right-click the app → **Open** (one-time Gatekeeper
   confirmation). The clock icon appears in your menubar.

### 2. Build from source via install script

For colleagues who already have Xcode and prefer to build locally:

```bash
git clone https://github.com/darioristic/tymeline.git
cd tymeline
./scripts/install.sh
```

The script generates the Xcode project, builds the Release configuration with
ad-hoc signing, installs into `/Applications`, strips the quarantine
attribute, and launches the app. Requires macOS 14+, Xcode 16+, and
[XcodeGen](https://github.com/yonaskolb/XcodeGen) (installed automatically
via Homebrew if missing).

### 3. Homebrew cask

> _Coming with v1.0._ A `darioristic/tap` Homebrew cask will let you install
> with `brew install --cask tymeline` — tracking issue:
> [#tap-setup](https://github.com/darioristic/tymeline/issues).

### Gatekeeper note

Because tymeline is ad-hoc signed rather than notarized through Apple's paid
Developer ID program, macOS will block the first launch with an
"unidentified developer" warning. Two ways past it:

- **GUI**: right-click the app in `/Applications` → **Open** → **Open** in the
  confirmation dialog. Only needed the very first time.
- **Terminal**: `xattr -dr com.apple.quarantine /Applications/tymeline.app`

After that the app launches normally. The install script handles this for
you automatically.

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
