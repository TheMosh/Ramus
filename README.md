# Ramus

A small macOS menu bar app that shows how much memory you have available and which apps are using it.

- **Menu bar**: available memory at a glance (or % used, or just the icon).
- **Breakdown**: the same categories as Activity Monitor (App Memory, Wired, Compressed, Cached Files, Free) plus swap and memory pressure.
- **History**: memory used over the last 3 minutes.
- **Per app**: the top 10 apps by memory, with each app's helpers, XPC services and child processes rolled into it. Hover a bar to see how many processes it covers.

Built with SwiftUI, `MenuBarExtra` and Swift Charts. Requires macOS 14 or later.

## Build

```sh
./scripts/build.sh
open dist/Ramus.app
```

To keep it around, copy `dist/Ramus.app` to `/Applications` and turn on **Launch at Login** from the gear menu.

The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen); `build.sh` regenerates it when XcodeGen is installed. You can also open `Ramus.xcodeproj` directly.

## How the numbers are measured

- System memory comes from `host_statistics64`, using Activity Monitor's formulas: *Memory Used* = App Memory + Wired + Compressed, and *Available* = total − used.
- Per-app memory is each process's physical footprint (`proc_pid_rusage`), which is what Activity Monitor's *Memory* column shows. Processes are attributed to the app macOS holds responsible for them, falling back to the parent process and then the app bundle that contains the executable.
- Per-app sampling walks every process (~8 ms), so it only runs while the panel is open. Ramus refreshes every 2 seconds while the panel is open and every 5 seconds otherwise.

The icon artwork is drawn by `scripts/make-icon.swift`.
