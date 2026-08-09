# Vibe Watch native BLE controller for Codex

Use the Vibe Watch control surface from **Safari on iPhone**, while a BLE Micro
Pro presents the real hardware protocol to Codex on Mac. The normal path does
not use macOS Accessibility, UI scripting, keyboard shortcuts, deep links, or a
restricted virtual-HID entitlement.

**[Download Vibe Watch Bridge for Mac](https://github.com/nyanko3141592/vibewatch-apple-watch/releases/latest/download/VibeWatchBridge-0.3.0.dmg)** ·
**[Download BLE Micro Pro firmware](https://github.com/nyanko3141592/vibewatch-apple-watch/releases/latest/download/VibeWatch-BLE-Micro-Pro.uf2)** ·
[Project site](https://nyanko3141592.github.io/vibewatch-apple-watch/)

The UI, device identity, HID report map, and event protocol are based on
[GOROman/vibewatch](https://github.com/GOROman/vibewatch). Attribution is
preserved in [LICENSE](LICENSE).

## Architecture

```text
iPhone Safari
    │ local Wi-Fi + six-digit pairing code
    ▼
Vibe Watch Bridge on Mac
    │ private BLE GATT relay (63-byte frames)
    ▼
BLE Micro Pro
    │ native BLE HID — VID 303A / PID 8360 / report ID 6
    ▼
Codex desktop app
```

Codex therefore receives the same `v.oai.hid` press/release messages as the
reference device. Codex-to-device RPC is also implemented: `v.oai.thstatus`,
`v.oai.rgbcfg`, `device.status`, and `sys.version` travel through the HID output
report, and live agent status is relayed back to the browser.

## Install

Requirements:

- macOS 15 or later
- BLE Micro Pro (nRF52840/BL654)
- iPhone and Mac on the same local network

1. Download `VibeWatch-BLE-Micro-Pro.uf2` from the latest release.
2. Hold the BLE Micro Pro reset switch while connecting USB. Confirm its drive
   contains `INFO_UF2.TXT`, then copy the UF2 to that drive.
3. If an older `Vibe Watch #1` exists in macOS Bluetooth settings, forget it.
   Pair the newly advertised `Vibe Watch #1`.
4. Install and open `VibeWatchBridge-0.3.0.dmg`.
5. Open Codex. The bridge shows the BLE board connection and the first native
   Codex handshake separately.
6. Scan the bridge QR code with iPhone Camera and use the Safari controller.

Tap Agent and Action controls normally. Only the microphone is press-and-hold.
The page disables selection, callouts, drag, context menus, and native gestures
on the entire control surface so a long press cannot select text.

## Protocol compatibility

| Property | Value |
| --- | --- |
| BLE name | `Vibe Watch #1` |
| Manufacturer/model | `VibeWatch` |
| VID / PID / version | `303A` / `8360` / `0001` |
| Vendor usage page | `FF00` |
| Vendor report | ID `6`, input/output/feature, 63 bytes |
| RPC frame | byte 0 channel `2`, byte 1 length, bytes 2–62 JSON |
| Agent keys | `AG00`…`AG05` |
| Actions | `ACT06`…`ACT12` |

Example press report payload:

```json
{"m":"v.oai.hid","p":{"k":"AG00","act":1}}
```

## Build from source

Mac app:

```sh
xcodegen generate
xcodebuild -project VibeWatchAppleWatch.xcodeproj -scheme VibeWatchBridge build
```

BLE Micro Pro firmware:

```sh
cd Firmware/BLEMicroPro
pio run
```

`pio run` creates `Firmware/BLEMicroPro/VibeWatch-BLE-Micro-Pro.uf2`. The image
starts at `0x26000`, matching BLE Micro Pro's S140/UF2 application layout; it
does not replace the bootloader.

The repository still includes optional native iPhone and Apple Watch clients.
They use the same event model, but Safari is the default controller.

## Verification

- BLE firmware compiles for nRF52840 and produces a UF2 beginning at `0x26000`.
- The firmware report map is byte-identical to the reference implementation.
- macOS bridge builds with Swift 6 and CoreBluetooth.
- Protocol framing tests cover exact 63-byte press/release reports.
- Browser events receive an error unless the physical BLE relay is connected;
  the UI no longer reports a false success.

End-to-end radio verification requires a BLE Micro Pro to be physically
connected/flashed and paired. The build machine used for the current release
did not have one attached, so the app deliberately reports that hardware step
as incomplete instead of falling back to Accessibility.

References: [Codex Micro documentation](https://learn.chatgpt.com/docs/features/codex-micro) ·
[BLE Micro Pro](https://github.com/sekigon-gonnoc/BLE-Micro-Pro) ·
[Apple CoreBluetooth](https://developer.apple.com/documentation/corebluetooth)
