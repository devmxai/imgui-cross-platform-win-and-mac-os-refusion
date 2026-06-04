# Current macOS Status

Status date: 2026-06-04.

Portable source branch:

```text
main
```

Initial checkpoint tag:

```text
macos-working-v0.1.0
```

## Validated

```text
Native macOS application builds successfully.
Dear ImGui remains command/display only.
Metal displays FinalFrameSurface.
Open Folder loads accepted project state.
Playback and scrub are driven by the native scheduler.
Video, image, text, shape, and background nodes reach the native render path.
motionTile executes as a pre-transform Metal pass.
gaussianBlur executes as a native Metal pass.
transformMotionBlur uses adaptive temporal transform samples.
Large rotation blur uses up to 64 paused-preview samples and 24 playback samples.
Transform motion blur reuses the accepted source texture across temporal samples.
The corrected smooth spiral transform-motion-blur result is included.
Objective-C++ ARC is enabled.
Video texture cache is bounded.
Idle rendering is event-driven and measured at approximately 0% CPU.
The complete current source path from Gates through FinalFrameSurface and ImGui is preserved on main.
```

## Verification

The checkpoint was validated with:

```bash
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
npm run verify
```

`npm run verify` checks the ImGui architecture, portable source manifest,
HyperFrame Core-relative imports, and FX registry manifest.

## Remaining Work

```text
Windows Direct3D / Media Foundation platform adapter
Live Scope consumer from FinalFrameSurface
Export consumer from FinalFrameSurface
golden-frame preview/export parity coverage
additional Core-declared FX adapter execution
frame-time and GPU-memory telemetry inside the diagnostics panel
```

This status does not claim that all future editor features are complete. It records that the current native macOS checkpoint builds, runs, previews accepted projects, and preserves the required architecture boundaries.
