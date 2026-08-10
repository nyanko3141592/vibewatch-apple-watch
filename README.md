# Vibe Watch controller for Codex

Control Codex on a Mac from **Safari on iPhone**. Version 0.4 uses Codex's
official local `app-server` interface by default, so it requires **no BLE Micro
Pro, iPhone app, Accessibility permission, UI scripting, or API key**.

**[Download Vibe Watch Bridge for Mac](https://github.com/nyanko3141592/vibewatch-apple-watch/releases/latest/download/VibeWatchBridge-0.4.0.dmg)** ·
[Project site](https://nyanko3141592.github.io/vibewatch-apple-watch/)

The circular UI and control vocabulary are based on
[GOROman/vibewatch](https://github.com/GOROman/vibewatch). Attribution is
preserved in [LICENSE](LICENSE).

## Default architecture

```text
iPhone Safari
    │ local Wi-Fi + six-digit pairing code
    ▼
Vibe Watch Bridge on Mac
    │ Codex app-server JSON-RPC (local stdio)
    ▼
Codex
```

The bridge starts `codex app-server`, creates a persistent Codex task, sends or
steers turns, streams the latest response, and handles command/file approvals.
Codex desktop login is reused; no OpenAI API key is required.

## Install and use

Requirements: macOS 15+, the Codex/ChatGPT desktop app, and an iPhone and Mac on
the same local network.

1. Install and open `VibeWatchBridge-0.4.0.dmg`.
2. Scan the QR code displayed by the Mac app.
3. Enter an instruction in Safari, or hold the microphone button to dictate it.
4. Choose Agent 1–6 and optional FAST/PLAN modes, then tap SEND.
5. When Codex requests permission, tap APPROVE or REJECT from the phone.

Agent buttons select a working role: implementation, review, debugging, tests,
UI/UX, or release/documentation. SEND starts a turn; sending again while Codex
is working steers the active turn. The page shows busy, completion, response,
and approval-waiting states.

Long-press selection, callouts, drag, and context menus remain disabled on the
watch control. The instruction field intentionally behaves like a normal text
field.

## Optional exact HID compatibility

`Firmware/BLEMicroPro` remains available for testing the original hardware
protocol: byte-identical 200-byte report map, VID `303A`, PID `8360`, and vendor
report ID 6 with 63-byte input/output/feature reports. It is not needed for the
normal software mode.

## Build

```sh
xcodegen generate
xcodebuild -project VibeWatchAppleWatch.xcodeproj -scheme VibeWatchBridge build
```

## Verification

- Mac bridge builds with Swift 6.
- Software mode reaches `ready` without a Bluetooth device.
- Browser API selection and FAST mode update immediately.
- A real browser API instruction completed through app-server and returned
  `VIBEWATCH SOFTWARE OK`.
- The touch surface prevents accidental long-press text selection.
- Optional BLE firmware descriptor/framing tests remain available.

Reference: [Codex App Server](https://developers.openai.com/codex/app-server/)
