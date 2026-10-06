# DockStat

[![CI](https://github.com/sonht1109/DockStat/actions/workflows/ci.yml/badge.svg)](https://github.com/sonht1109/DockStat/actions/workflows/ci.yml)

Live CPU / memory / disk in the macOS menu bar **and** on the Dock icon.
Native SwiftUI + AppKit, no Xcode project, no subprocesses.

```
make run          # build dist/DockStat.app and launch it
make install      # copy to /Applications (better for launch-at-login)
make verify       # self-test + 3s sampler probe + icon PNG
make perf ARGS=60 # 60s CPU / footprint budget check on the running app
make bench        # per-operation timings of the polling path
make clean
```

Or without make: `./build.sh` then `./run.sh`.

### Install from a release

Grab `DockStat.dmg` from [Releases](https://github.com/sonht1109/DockStat/releases),
drag **DockStat** into Applications, and launch it.

> First launch of an unsigned build: right-click → **Open** → **Open**.

## Build

SwiftPM package, one executable target, `platforms: [.macOS(.v14)]`, Swift 6
strict concurrency. `Scripts/package-app.sh` (shared by the `Makefile`,
`build.sh` and CI) builds the binary and assembles the bundle:

`swift build -c release` → `dist/DockStat.app/Contents/{MacOS/dockstat,
Resources/, Info.plist}` → `codesign -s -` (ad-hoc, `make sign`) → `open`.

It asks for a universal `--arch arm64 --arch x86_64` build first and falls back
to the native architecture when only Command Line Tools are installed.

`xcodebuild` is not used: on a Command Line Tools-only machine it is
unavailable, and none of this needs it.

## Metrics

| Metric | Source                                | Definition                                                                                            |
| ------ | ------------------------------------- | ----------------------------------------------------------------------------------------------------- |
| CPU %  | `host_statistics(HOST_CPU_LOAD_INFO)` | busy tick delta / total tick delta; the first (since-boot) sample is discarded                        |
| MEM %  | `host_statistics64(HOST_VM_INFO64)`   | `(active + wire + compressor) × page_size / physical_memory` — matches Activity Monitor "Memory Used" |
| DISK   | `statfs(path)`                        | `f_bavail × f_bsize` free, `f_blocks × f_bsize` total; GB / TB auto-scaled                            |

Page size comes from `host_page_size()` (`vm_kernel_page_size` is not
concurrency-safe). All three are fixed-size C structs — no allocation, no
`Foundation` object creation, no subprocess in the hot path.

## Polling

- One `DispatchSourceTimer` on a dedicated `userInitiated` queue with
  `leeway = max(interval × 10 %, 50 ms)`.
- Presets 1 / 2 / 5 / 10 / 30 / 60 s plus a custom stepper (0.5–600 s).
- Adaptive: on battery **or** Low Power Mode the interval is multiplied
  (default ×3). Power state is re-checked every tick, so pulling the charger
  is picked up even without a notification.
- Display sleep suspends the timer; wake resumes with an immediate sample.
- The disk syscall runs every 5th tick only.
- Menu bar title and Dock icon are re-set only when the rendered text or
  colours actually change.

## Menu bar

`NSStatusItem` with an `NSAttributedString` title in a `monospacedDigitSystemFont`
(no width jitter). Configurable metric set, order, style (`27%`, `27%CPU`,
`CPU 27%`), separator and per-metric colours. Left click → minimal popover
(values, interval picker, refresh, Settings…, Quit); right click → context menu.

## Dock icon

Custom-drawn squircle: background fill, border stroke (as a fraction of the
size), up to two text lines with a hairline separator between them, laid out
with cached `CTFont` / `CTLine`.

Two renderers, switchable in Settings:

| Renderer                             | Cost per update                  | Notes                                                                            |
| ------------------------------------ | -------------------------------- | -------------------------------------------------------------------------------- |
| `dockTile.contentView` (**default**) | ~0.25 ms                         | the Dock draws our view directly; a repaint cannot be swallowed by an icon cache |
| `NSApplication.applicationIconImage` | ~2 ms at 256 pt, ~8 ms at 512 pt | classic path, cost scales with pixel count                                       |

Badge via `NSApp.dockTile.badgeLabel` — the system red bubble, no notification
permission required. Right-clicking the Dock icon opens Settings / Quit, so the
app stays reachable when the menu bar item is hidden.

## Thresholds

Per metric warn / critical values with 5 pp hysteresis (default). Escalation is
visual only: menu bar colour + `!` / `⚠` marker, Dock icon text colour, and an
optional Dock bounce once per crossing.

## Settings

`SettingsModel` is `@MainActor @Observable`; a `withObservationTracking` loop
persists the whole model to JSON in `UserDefaults` and pushes changes to the
bar, the Dock icon and the scheduler. Payload decoding is tolerant: missing
keys fall back to defaults, so adding a setting never wipes a configuration.

## Verification

`make verify` runs three headless modes:

- `--self-test` — formatters, hex colour round-trip, threshold hysteresis,
  settings save/reload round-trip (including observation-driven saves and
  partial-payload decoding), icon rendering and cache identity.
- `--probe [n]` — samples the three metrics for `n` seconds and prints the
  derived menu bar title / Dock icon lines.
- `--render <path>` — writes the rendered Dock icon to a PNG for eyeballing.
- `--bench` (`make bench`) — per-operation timings of the polling path.

Cross-check MEM against Activity Monitor, disk against `df -h /`:

```
$ df -h /                     # Avail 39Gi
$ DockStat.app/Contents/MacOS/dockstat --probe 3
  t      cpu%     mem%            free           total
  1  22.7   73.8   41.5 GB        245.1 GB
```

Live checks used during development:

```
# menu bar is really updating
osascript -e 'tell application "System Events" to tell process "dockstat" \
  to get title of every menu bar item of menu bar 2'
27%  73%  41.5 GB
```

Budget, measured with `make perf` (`top` per-second samples, one core = 100 %):

| Poll interval | CPU mean | CPU peak | `phys_footprint`          |
| ------------- | -------- | -------- | ------------------------- |
| 2 s (default) | 0.40 %   | 1.2 %    | 17 MB, no drift over 60 s |
| 1 s           | 0.71 %   | 1.2 %    | 17 MB                     |

So the 2 s default meets the < 0.5 % budget; 1 s pays ~0.7 %. Breakdown per
tick at 1 s: ~0.3 % wakeups and sampling, ~0.4 % for repainting the menu bar
text, ~0.1 % for the Dock tile. `ps` RSS is ~70 MB because it counts shared
framework pages; `footprint`/`phys_footprint` is the honest number.

Not verified on the development machine: screen recording is unavailable there,
so the Dock tile was checked by rendering the icon to PNG (`--render`) and by
asserting the tile is updated, not by screenshot.

## Layout

```
Package.swift                 Makefile                 Resources/Info.plist
Scripts/perf.sh                # CPU / footprint budget check
Scripts/package-app.sh        # release binary + dist/DockStat.app (used by CI)
build.sh  run.sh  release.sh  # local build / run / tag-and-push (release.sh untracked)
Sources/DockStat/
  main.swift                  # --probe / --render / --self-test, then NSApplication
  AppDelegate.swift           # status item lifecycle, main menu, settings window
  Core/
    Sample.swift              # StatKind, Severity, Sample
    CPUSampler.swift          MemorySampler.swift   DiskSampler.swift
    StatsSampler.swift        # fan-out, warm-up, disk cadence
    PollScheduler.swift       # timer, leeway, adaptive interval, power state
    SamplingEngine.swift      # samplers + timer off the main actor
  UI/
    StatsStore.swift          # @MainActor @Observable single source of truth
    MenuBarController.swift   PopoverView.swift
    DockIconRenderer.swift    DockBadgeController.swift
  Settings/
    SettingsModel.swift       SettingsView.swift
    LaunchAtLogin.swift       Theme.swift
  Util/
    Formatters.swift          Thresholds.swift           Probe.swift
```

## CI / releases

`.github/workflows/ci.yml` builds the package, packages the `.app` and runs
`--self-test` + `--probe 3` on every push and pull request to `master` /
`develop`.

`.github/workflows/release.yml` runs on `v*` tags (or manually): it packages
the app, stamps `CFBundleShortVersionString` from the tag, signs it —
Developer ID + notarize when the `APPLE_CERT_BASE64` / `APPLE_ID` /
`APPLE_TEAM_ID` / `APPLE_APP_PASSWORD` secrets exist, ad-hoc otherwise — and
publishes `DockStat.dmg` + `DockStat.zip` on the GitHub release. Tags
containing `-dev` become pre-releases.

`./release.sh dev|stable` (author-only, untracked) bumps the tag: `dev` from
`develop`, `stable` from `master` after merging `develop`.

## Out of scope (v1)

History graphs, per-core bars, top processes, network I/O, temperature/fan
(needs SMC + privileges), Sparkle updates, Mac App Store distribution.
