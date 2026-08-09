# BLE Micro Pro native Codex firmware

This firmware makes a BLE Micro Pro identify as the same BLE HID device used by
the reference Vibe Watch implementation: VID `303A`, PID `8360`, vendor report
ID `6`, and 63-byte `v.oai.hid` JSON-RPC reports.

## Build

```sh
cd Firmware/BLEMicroPro
pio run
```

The distributable file is `VibeWatch-BLE-Micro-Pro.uf2`.

## Install

1. Hold the BLE Micro Pro reset switch while connecting USB.
2. Confirm the mounted drive contains `INFO_UF2.TXT`.
3. Copy `VibeWatch-BLE-Micro-Pro.uf2` to that drive and wait for it to reboot.
4. In macOS Bluetooth settings, forget an older `Vibe Watch #1` bond, then pair
   `Vibe Watch #1` again.
5. Keep VibeWatchBridge open. It discovers the private relay service and sends
   browser controls through the real BLE HID path; Accessibility is not used.

The app firmware starts at `0x26000`, matching the BLE Micro Pro and Adafruit
nRF52840 S140/UF2 bootloader layout. Do not replace the board's bootloader.
