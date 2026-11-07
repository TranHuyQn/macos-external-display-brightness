# macOS External Display Brightness Control (DDC/CI) with F1/F2 Keys

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)
![Platform: macOS on Apple Silicon](https://img.shields.io/badge/platform-macOS%20Apple%20Silicon-lightgrey)
![Swift](https://img.shields.io/badge/Swift-native%20AppKit-orange)

**DisplayControl** is a tiny, native menu bar app that lets you change the **real hardware brightness of an external monitor** on a Mac using the same **F1 / F2 brightness keys** that control your MacBook screen. It talks to the monitor over **DDC/CI** (VCP code `0x10`), so the monitor's own backlight changes, not a software overlay or gamma dimming.

The brightness keys follow your mouse: put the pointer on the external monitor and F1/F2 adjust that monitor; put it on the MacBook display and macOS handles the keys as usual.

> Built and tested on a MacBook Pro M1 Pro (macOS 26.5.2) with an ASUS PA248QV connected **directly to the Mac's HDMI port**. See [Compatibility](#compatibility) before you try it.

**Keywords:** macOS external monitor brightness, DDC/CI brightness control Mac, Apple Silicon DDC, M1 external display brightness keyboard, control monitor brightness with F1 F2 on Mac, HDMI monitor brightness macOS, native Swift menu bar app.

---

## Features

- **Hardware brightness via DDC/CI** (VCP `0x10`): changes the monitor's real backlight level.
- **Uses your keyboard brightness keys (F1 / F2)** with a native on-screen brightness indicator (OSD).
- **Pointer-aware:** the display under the mouse is the one that changes. On the MacBook screen the keys are left untouched.
- **Very light:** pure Swift + AppKit, no SwiftUI, no Electron, no third-party packages. About 450 KB app, about 12 MB physical memory, 0.0% CPU when idle (no timers, no polling).
- **Hold-key friendly:** a "latest value wins" writer with a 40 ms minimum gap, because the tested monitor ignores DDC writes sent back to back without a pause.
- **Menu bar icon is optional:** hide it and reopen the app any time to show the settings window. Optional launch at login.
- **One job only:** no color, contrast, volume or input switching.

## Compatibility

| | |
|---|---|
| Mac | Apple Silicon (verified on M1 Pro) |
| macOS | 14 or later required by the app bundle; **verified only on macOS 26.5.2** |
| Display | One external monitor that supports DDC/CI (enable DDC/CI in the monitor's on-screen menu if it has the option) |
| Connection | **Plug the monitor directly into the Mac's HDMI port.** |

> **Important: avoid hubs and docks.** In testing, the same monitor behind a USB-C hub returned an I2C error (`0xE0114102`) on every DDC write. Connected directly to the built-in HDMI port it worked. The built-in HDMI port of the tested MacBook Pro uses a Megachips MCDP29XX bridge, which is addressed at I2C chip address `0xB7` (other connections use `0x37`).

Other monitors, ports and Macs are untested. Please open an issue with your results.

## Install (build from source)

You need the Swift toolchain (Xcode Command Line Tools are enough, full Xcode is not required).

```bash
git clone https://github.com/TranHuyQn/macos-external-display-brightness.git
cd macos-external-display-brightness
./scripts/build-app.sh      # builds, strips and signs build/DisplayControl.app
open build/DisplayControl.app
```

The app is signed ad-hoc (or with a `DisplayControl Dev` certificate if you have one in your keychain). There is no notarized download, so building it yourself is the supported route.

### Grant the Accessibility permission (once)

The app has to see the brightness keys, so macOS requires the **Accessibility** permission:

1. Open **System Settings > Privacy & Security > Accessibility**.
2. Turn on **DisplayControl**.

Rebuilding with a different signature can make macOS ask again.

### Use it

- Move the mouse to the external monitor and press **F1** (darker) or **F2** (brighter).
- Hide the menu bar icon from the menu or settings window. To get the settings window back, open **DisplayControl** again from Spotlight or Finder.

## How it works

1. A `CGEventTap` listens for the system brightness key events (`NX_SYSDEFINED`, key codes 2 and 3).
2. The display under the mouse pointer decides the target. Built-in display: the key passes through to macOS. External display: the key is consumed.
3. The new level is computed on a 16-step scale mapped to the monitor's `0...max` DDC range.
4. The OSD is shown immediately; the DDC write goes to a serial background queue and never blocks the key handler.
5. DDC/CI "Set VCP Feature" is sent over I2C through the private `IOAVService` interface used for external displays on Apple Silicon.

Source layout: `Sources/DisplayCore` holds the pure, unit-tested logic (brightness scale, latest-wins writer, display target resolution, settings). `Sources/DisplayControl` holds the system integration (DDC, key tap, OSD, menu bar, settings window). `spike/FINDINGS.md` records the DDC experiments and measurements (Vietnamese).

## Performance

Measured on the test machine with the app idle: 0.0% CPU, 12 MB physical footprint (`footprint -p`), 452 KB `.app`. A single DDC write takes about 3.7 ms; the on-screen indicator appears in under 25 ms.

## Limitations

- Uses the **private, undocumented `IOAVService` API**. A future macOS update may break it.
- One external monitor is supported by design.
- Not notarized; build from source.
- Verified on a single Mac and monitor combination.

## Development

```bash
./scripts/test.sh          # unit tests (Swift Testing, via Command Line Tools)
./scripts/measure.sh       # idle CPU / memory / size measurement
swift build -c release
```

The design notes are in [`docs/superpowers/specs/2026-11-07-display-control-design.md`](docs/superpowers/specs/2026-11-07-display-control-design.md) (Vietnamese).

## FAQ

**How do I control an external monitor's brightness from the keyboard on a Mac?**
Macs only map F1/F2 to the built-in display. DisplayControl intercepts those keys when the mouse is on an external monitor and sends a DDC/CI brightness command to it.

**Does it work on Apple Silicon (M1, M2, M3, M4) Macs?**
It targets Apple Silicon and was verified on an M1 Pro over HDMI. Other chips and ports are untested.

**Why does DDC fail when my monitor is behind a dock or hub?**
Many hubs and adapters do not forward the I2C/DDC channel. Connect the monitor straight to the Mac's HDMI port.

**Is this a software overlay or gamma dimming?**
No. It changes the monitor's own brightness setting over DDC/CI, the same setting as the monitor's physical buttons.

**Other tools?**
If you need several monitors, color or input control, take a look at [MonitorControl](https://github.com/MonitorControl/MonitorControl), [Lunar](https://lunar.fyi) or [BetterDisplay](https://github.com/waydabber/BetterDisplay). DisplayControl is intentionally the minimal option.

## License

[MIT](LICENSE) © 2026 TranHuyQn

Tiếng Việt: xem [README.vi.md](README.vi.md).
