# Vibe Watch for Apple Watch

Apple Watch port of [GOROman/vibewatch](https://github.com/GOROman/vibewatch), including a paired-iPhone relay and a macOS bridge for the ChatGPT desktop app's Codex Micro integration.

The original Vibe Watch design and firmware are Copyright (c) 2026 GOROman and used under the MIT License. This port preserves that attribution in [LICENSE](LICENSE).

## Implemented

- Original-style Agent and Action control surfaces on watchOS
- Press/release events for `AG00...AG05`
- Firmware-compatible action events:
  - `ACT06` FAST
  - `ACT07` OK / approve
  - `ACT08` NG / reject
  - `ACT09` PLAN
  - `ACT10` + `ACT11` push to talk
  - `ACT12` AI / Codex
- Byte-compatible 63-byte `v.oai.hid` vendor reports
- Apple Watch → iPhone using WatchConnectivity
- iPhone → Mac automatic discovery using Bonjour and a paired TCP connection
- Six-digit local pairing code
- macOS virtual HID with Codex Micro identity (`VID 0x303A`, `PID 0x8360`, usage page `0xFF00`, report ID `6`)
- Codex control-plane RPC replies for `device.status`, `sys.version`, lighting, and six-agent state
- Mac → iPhone → Watch agent-lighting synchronization

## Architecture

```text
Apple Watch UI
    │ WatchConnectivity
    ▼
iPhone relay
    │ Bonjour + paired TCP
    ▼
Vibe Watch Bridge for macOS
    │ virtual HID / v.oai.hid
    ▼
ChatGPT desktop app / Codex
```

The iPhone relay is intentional. watchOS apps cannot advertise Core Bluetooth peripheral services and ordinary watchOS apps cannot maintain the low-level Bonjour/TCP connection needed here. WatchConnectivity is the supported route to the paired iPhone.

## Important macOS signing requirement

Exact Codex Micro emulation uses `HIDVirtualDevice`, which requires Apple's restricted `com.apple.developer.hid.virtual.device` entitlement. The entitlement file and implementation are included, but the Mac target must be signed with a provisioning profile authorized for that entitlement. Without it, the bridge still builds, but macOS refuses to create the virtual HID and the Watch cannot control Codex through the genuine Codex Micro path.

This environment could compile all three targets but did not have an authorized provisioning profile, so the final physical Watch → signed virtual HID → Codex interaction remains to be verified after entitlement approval/signing.

References:

- [Apple HID virtual device entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device)
- [Apple HIDVirtualDevice](https://developer.apple.com/documentation/corehid/hidvirtualdevice)
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [OpenAI Codex Micro](https://learn.chatgpt.com/docs/features/codex-micro)

## Generate the project

```sh
cd VibeWatchAppleWatch
xcodegen generate
open VibeWatchAppleWatch.xcodeproj
```

## Run on hardware

1. In Xcode, select your development team for `VibeWatchRelay`, `VibeWatchWatchApp`, and `VibeWatchBridge`.
2. Ensure the Mac App ID/profile contains `com.apple.developer.hid.virtual.device`.
3. Run `VibeWatchBridge` on the Mac and leave ChatGPT desktop running.
4. Run `VibeWatchRelay` on the iPhone paired with the Apple Watch.
5. Enter the six-digit code shown on the Mac into the iPhone relay.
6. Run `VibeWatchWatchApp` on the paired Apple Watch.
7. Confirm the Mac bridge shows `Codex Micro HID: ready`, then press a Watch control.

WatchConnectivity behavior and microphone ergonomics must be tested on physical paired devices; Simulator is only suitable for UI and protocol validation.

## Verified here

```text
watchOS Simulator build: passed
iOS Simulator build:     passed
macOS build:              passed (unsigned)
protocol tests:           4 passed
```

The tests cover the original 63-byte frame, firmware action-key mapping, Watch message round trips, and iPhone/Mac bridge envelopes.
