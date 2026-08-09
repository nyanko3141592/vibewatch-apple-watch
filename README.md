# Vibe Watch for iPhone and Apple Watch

Control the ChatGPT/Codex desktop app from **Safari on your iPhone**. Install only the Mac bridge, scan its QR code, and the Vibe Watch-style controller opens on the same local Wi-Fi—no iPhone app, TestFlight, or BLE hardware required.

**[Download Vibe Watch Bridge for Mac](https://github.com/nyanko3141592/vibewatch-apple-watch/releases/latest/download/VibeWatchBridge-0.2.3.dmg)** · [Project site](https://nyanko3141592.github.io/vibewatch-apple-watch/)

The control design and event protocol are based on [GOROman/vibewatch](https://github.com/GOROman/vibewatch). The original Vibe Watch design and firmware are Copyright (c) 2026 GOROman and used under the MIT License; attribution is preserved in [LICENSE](LICENSE).

## Default setup: Safari + Mac bridge

```text
iPhone Safari
    │ local Wi-Fi + six-digit pairing code
    ▼
Vibe Watch Bridge on Mac
    │ standard macOS Accessibility permission
    ▼
ChatGPT desktop app / Codex
```

The Mac bridge serves the private controller itself at `http://<your-mac-ip>:8360`. The public GitHub Pages site is the project homepage, not a relay: control traffic remains on your local network.

The repository also contains a native iPhone client and an optional Apple Watch companion. They use the same protocol, but are no longer required for the normal setup.

## Controls

- Six most recently updated Codex tasks, opened through documented `codex://threads/<id>` deep links
- FAST mode
- Approve and reject
- PLAN mode
- Submit the current prompt
- Start/stop microphone control

The browser sends the same semantic key events as the original firmware:

| Action | Event |
| --- | --- |
| Agents | `AG00...AG05` |
| FAST | `ACT06` |
| Approve | `ACT07` |
| Reject | `ACT08` |
| PLAN | `ACT09` |
| Microphone | `ACT10` + `ACT11` |
| Submit / Codex | `ACT12` |

## Install and run

Requirements:

- macOS 15 or later
- iPhone and Mac on the same local network
- iOS 18 / watchOS 11 only when building the optional native clients

1. Download the notarized [VibeWatchBridge DMG](https://github.com/nyanko3141592/vibewatch-apple-watch/releases/latest/download/VibeWatchBridge-0.2.3.dmg).
2. Drag **Vibe Watch Bridge** to Applications and open it.
3. Complete the three status rows in the app: Mac bridge, Accessibility access, and Codex.
4. Scan the QR code with the iPhone Camera app.
5. Safari opens the controller and independently confirms all three requirements.

Tap Agent and Action controls normally. Only the microphone is a press-and-hold control. The controller suppresses Safari's text-selection and context-menu gestures while you operate it.

Keep target Codex tasks visible in the sidebar when using Agent 1–6. Accessibility labels can change between Codex desktop versions; failures are shown beside the control you used and in the Mac bridge.

### Build from source

Install Xcode and XcodeGen, then generate and open the project:

```sh
xcodegen generate
open VibeWatchAppleWatch.xcodeproj
```

Select the `VibeWatchBridge` scheme and run it on the Mac.

### Optional native clients

Build `VibeWatchRelay` for a native iPhone experience. `VibeWatchWatchApp` forwards the same Agent and Action controls through the paired iPhone using WatchConnectivity.

## Why the controller is not hosted on GitHub Pages

GitHub Pages is HTTPS, while the Mac bridge is a private HTTP service on the LAN. Modern browsers block an HTTPS page from sending active requests to an HTTP endpoint. Serving the controller from the Mac keeps it same-origin, avoids a cloud relay, and keeps commands local. Pages remains useful as the public, shareable introduction and install guide.

## Experimental Codex Micro compatibility

The Mac bridge also contains an experimental virtual-HID backend matching Codex Micro's `VID 0x303A`, `PID 0x8360`, usage page `0xFF00`, report ID `6`, and `v.oai.hid` RPC framing.

This is not the default. It requires Apple's restricted [`com.apple.developer.hid.virtual.device`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device) entitlement and an authorized provisioning profile. The example entitlement is kept in `MacApp/VibeWatchBridge.entitlements` but is deliberately not attached to the target.

## Verification

```text
browser controller runtime: passed (page, status, paired event)
watchOS Simulator build:    passed
iOS Simulator build:        passed
macOS build:                 passed
protocol tests:              5 passed
```

Physical-device verification is still required for local-network permission prompts, optional WatchConnectivity, and the exact Accessibility labels exposed by the installed ChatGPT desktop version.

References:

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [OpenAI Codex Micro](https://learn.chatgpt.com/docs/features/codex-micro)
