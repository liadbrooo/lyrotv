# Lyro Motion 1.0.0

Native macOS video player, separate from the existing LyroTV Tizen launcher.

## Features
- AVFoundation/AVKit playback: MP4, MOV, M4V, supported audio and HTTP(S) HLS/direct media. Codec and HDR support depend on macOS and hardware.
- SwiftUI dark cinema interface, animated sidebar, hover states, auto-hiding transport and reduced-motion accessibility.
- Drag & drop, multiple file opening, queue, shuffle, loop, local recent history and resume positions.
- Scrubbing, 10-second seeking, frame stepping, playback rates, volume, fullscreen, fit/fill.
- Embedded audio/subtitle tracks and local SRT/WebVTT captions, PNG frame export for local files.
- No account, telemetry, external service or mandatory network access. Local history can be cleared in Settings.

## Distribution
Open the Actions run for the lyro-motion-macos branch and download the LyroMotion-macOS artifact. It contains a universal DMG and ZIP, plus SHA256 checksums. Drag the app to Applications. Minimum macOS 13, Apple Silicon and Intel. The build is ad-hoc signed, not Developer ID signed or notarized; Gatekeeper may require explicit approval in System Settings > Privacy & Security after attempting to open.

## Build locally
Requires macOS with Xcode or Command Line Tools. Run `bash macos/build.sh` from the repository root. Outputs are placed in macos/dist.

## Limits
No DRM, YouTube page extraction, proprietary external codecs, MKV/AVI guarantees, motion interpolation or network server. AVFoundation uses native decoding and display timing. Manual playback, subtitle and UI tests on real Macs are still required.
