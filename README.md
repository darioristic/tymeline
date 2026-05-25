# tymeline

macOS menubar app that watches Linear issue status changes and automatically starts/stops Clockify timers, so time tracking happens with zero manual steps.

**Status:** Pre-release, v1 in active development. See [DESIGN.md](DESIGN.md) for the full spec, scope, and roadmap.

## Why

If you track time in Clockify against tasks in Linear, you probably forget to start the timer about half the time. tymeline watches your assigned Linear issues; when one moves to In Progress, the corresponding Clockify timer starts. When it moves to Done, the timer stops. That's it.

- No central server, no telemetry
- API keys live only in macOS Keychain
- Multi-workspace support (work + personal, multiple clients, etc.)

## Install

Not yet released. v1.0 will be available via Homebrew:

```bash
brew tap darioristic/tap
brew install --cask tymeline
```

## Build from source

Requires macOS 14+, Xcode 16+, Swift 6.

```bash
git clone https://github.com/darioristic/tymeline.git
cd tymeline
open tymeline.xcodeproj
```

The Xcode project is generated from [project.yml](project.yml) using [XcodeGen](https://github.com/yonaskolb/XcodeGen). If you change project structure (add files, modify build settings), regenerate with:

```bash
brew install xcodegen   # one-time
xcodegen generate
```

## License

MIT - see [LICENSE](LICENSE).
