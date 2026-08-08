# Vibe Watch for iPhone and Apple Watch

An iPhone-first controller for the ChatGPT/Codex desktop app, with an optional Apple Watch companion. The control design and protocol are based on [GOROman/vibewatch](https://github.com/GOROman/vibewatch).

The original Vibe Watch design and firmware are Copyright (c) 2026 GOROman and used under the MIT License. This port preserves that attribution in [LICENSE](LICENSE).

## Practical default setup

```text
iPhone control surface
    │ local network (Bonjour + paired TCP)
    ▼
Vibe Watch Bridge on Mac
    │ standard macOS Accessibility permission
    ▼
ChatGPT desktop app / Codex

Apple Watch ──WatchConnectivity──▶ iPhone control surface
```

The default route does not emulate Bluetooth or USB hardware and does not require a restricted Apple entitlement. The Mac bridge uses the normal macOS Accessibility permission to operate the visible Codex interface.

## What the iPhone can control

- Six visible Codex tasks/agents
- FAST mode
- Approve
- Reject
- PLAN mode
- Submit the current prompt
- Start/stop microphone control

The iPhone sends the same semantic key events as the original firmware:

| Action | Event |
| --- | --- |
| Agents | `AG00...AG05` |
| FAST | `ACT06` |
| Approve | `ACT07` |
| Reject | `ACT08` |
| PLAN | `ACT09` |
| Microphone | `ACT10` + `ACT11` |
| Submit / Codex | `ACT12` |

The Apple Watch companion presents the same Agent and Action controls and forwards them through the paired iPhone.

## Run it

Requirements:

- macOS 15 or later
- iOS 18 or later
- watchOS 11 or later for the optional Watch app
- XcodeGen

Generate and open the project:

```sh
xcodegen generate
open VibeWatchAppleWatch.xcodeproj
```

Then:

1. Select your development team for `VibeWatchBridge`, `VibeWatchRelay`, and optionally `VibeWatchWatchApp`.
2. Run `VibeWatchBridge` on the Mac.
3. Press **Grant Accessibility Access** and enable Vibe Watch Bridge under **System Settings → Privacy & Security → Accessibility**.
4. Open the ChatGPT/Codex desktop app and press **Refresh** in the bridge. Its status should become **Ready**.
5. Run `VibeWatchRelay` on the iPhone connected to the same local network.
6. Enter the six-digit pairing code shown by the Mac bridge.
7. Use the iPhone Controls tab. The Apple Watch app can be installed afterward if desired.

Keep target Codex tasks visible in the sidebar when using Agent 1–6. Accessibility labels can change between ChatGPT desktop versions; the Mac bridge reports a clear error when it cannot find a requested control.

## Experimental Codex Micro compatibility

The Mac bridge also contains an experimental virtual-HID backend matching Codex Micro's `VID 0x303A`, `PID 0x8360`, usage page `0xFF00`, report ID `6`, and `v.oai.hid` RPC framing.

This is not the default. It requires Apple's restricted [`com.apple.developer.hid.virtual.device`](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.hid.virtual.device) entitlement and an authorized provisioning profile. The example entitlement is kept in `MacApp/VibeWatchBridge.entitlements` but is deliberately not attached to the target.

## Verification

```text
watchOS Simulator build: passed
iOS Simulator build:     passed
macOS build:              passed
protocol tests:           5 passed
```

Physical-device verification is still required for WatchConnectivity, local-network permission prompts, and the exact Accessibility labels exposed by the installed ChatGPT desktop version.

References:

- [Apple Accessibility API](https://developer.apple.com/documentation/applicationservices/axuielement)
- [Apple WatchConnectivity](https://developer.apple.com/documentation/watchconnectivity)
- [OpenAI Codex Micro](https://learn.chatgpt.com/docs/features/codex-micro)
