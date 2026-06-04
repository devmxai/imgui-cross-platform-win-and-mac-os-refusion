# IMGUI Professional

Status: authoritative native desktop UI and platform execution plan.

Decision date: 2026-06-04.

This plan replaces the cancelled Qt native UI direction and supersedes older Browser/React/Windows UI plans for native desktop editor work. The active native desktop target is a single C++ application architecture using Dear ImGui for the editor shell, Metal on macOS, and Direct3D on Windows.

The first implementation target is macOS on Apple Silicon M1. Windows must follow the same contracts and architecture, but Windows work starts only after the macOS path proves a real `FinalFrameSurface` on screen.

## 1. Professional Architecture Rule

This is the only accepted native desktop frame path:

```text
ImGui UI
  -> commands only

Engine
  -> Gates
  -> HyperFrame IR
  -> FrameDescriptor
  -> RenderGraph
  -> FXPassGraph
  -> FinalFrameSurface

GPU backend
  -> displays FinalFrameSurface
```

Expanded execution path:

```text
User action
-> ImGui command
-> Command dispatcher
-> Gates
-> HyperFrame IR
-> FrameDescriptor(frameIndex)
-> RenderGraph
-> FXPassGraph
-> PlatformRenderFrameExecutor
-> FinalFrameSurface
-> Preview / Live Scope / Export
```

## 2. Absolute Red Lines

These rules are mandatory. Any implementation that violates them is rejected.

```text
100% Native path
100% single frame truth
100% no fake preview
100% no MediaPlayer fallback
100% no WebView fallback
100% no Canvas fallback
100% Preview / Live Scope / Export from FinalFrameSurface
100% UI commands only
```

The UI must never become the engine.

```text
UI does not render video.
UI does not decode media.
UI does not compose layers.
UI does not interpret timeline semantics.
UI does not interpret FX.
UI does not apply transitions.
UI does not own playback truth.
UI does not own live scope truth.
UI does not own export truth.
UI does not create alternate preview pixels.
UI does not decide frame acceptance.
UI does not modify HyperFrame Core, FX semantics, or RenderGraph rules.
```

If a feature cannot be represented through the engine path, the app must show a diagnostic. It must not add a shortcut path.

## 3. Platform Targets

### macOS First

The first real implementation target is:

```text
macOS Apple Silicon M1
C++ application core
Dear ImGui editor shell
Native Cocoa/AppKit window bootstrap where required
Metal GPU backend
VideoToolbox/AVFoundation as texture source only
MacMetalRenderFrameExecutor
CAMetalLayer or equivalent native Metal surface
```

The macOS milestone is accepted only when the app displays a real frame produced by:

```text
Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph -> FinalFrameSurface
```

### Windows Second

Windows must follow the same contract:

```text
Windows
C++ application core
Dear ImGui editor shell
Win32 or thin native Windows bootstrap
Direct3D 11/12 GPU backend
Media Foundation as texture source only
WindowsD3DRenderFrameExecutor
DXGI swap chain / native D3D surface
```

Windows is not allowed to use a different frame truth from macOS.

## 4. One App, Platform Backends

The product is one C++ native editor architecture:

```text
apps/imgui/
  main.cpp
  ui/
    EditorShell.cpp
    TimelinePanel.cpp
    AssetsPanel.cpp
    InspectorPanel.cpp
    TransportBar.cpp
    DiagnosticsPanel.cpp

  platform/
    macos/
      MacApp.mm
      MacMetalSurface.mm
      MacMetalRenderFrameExecutor.mm

    windows/
      WinApp.cpp
      WinD3DSurface.cpp
      WindowsD3DRenderFrameExecutor.cpp

engine/
  commands/
  gates/
  hyperframe-ir/
  frame-descriptor/
  render-graph/
  fx-pass-graph/
  final-frame-surface/
  scheduler/
  diagnostics/
```

The UI code may be shared. Platform bootstrap and GPU surface code must be platform-specific.

## 5. UI Law

Dear ImGui is selected because it is fast, C++ native, immediate, cross-platform, and suitable for professional editor tools. It is not selected to become a renderer.

Allowed UI responsibilities:

```text
draw panels
draw buttons
draw timeline controls
draw asset browser
draw inspectors
draw diagnostics
draw frame stats
send commands
display accepted state
display FinalFrameSurface texture in the preview viewport
```

Forbidden UI responsibilities:

```text
decode video
seek video directly
run its own frame clock as render truth
draw timeline layers as render truth
draw preview pixels
apply effects
simulate transitions
sample media
own export frames
```

## 5.1 Reference UI Parity

The native ImGui editor shell must match the approved visual reference, not merely be inspired by it.

Locked reference:

```text
Screenshot: /var/folders/zx/f3vhfs6s57g9ks5nlw85c2v00000gn/T/TemporaryItems/NSIRD_screencaptureui_bGOXWt/Screenshot 2026-06-04 at 04.04.54.png
Reference size: 3360x1824
```

The image content inside the preview is a visual reference only. In production, preview pixels must always come from `FinalFrameSurface`.

Required shell regions:

```text
TopToolbar
LeftToolRail
AssetLibrary
StageCanvas
PreviewViewport
TransportStrip
TimelineToolStrip
TimelineTrackList
TimelineRuler
TimelineLanes
StatusDiagnostics
```

Required layout proportions at the reference size:

```text
TopToolbar: approximately 3.5% to 4% of window height
LeftToolRail: approximately 3% of window width
AssetLibrary: approximately 18% of window width
Timeline area: approximately 25% of window height
StageCanvas: remaining central workspace
PreviewViewport: centered portrait 9:16 surface, no decorative card wrapper
TransportStrip: directly above the timeline ruler and aligned to the preview center
TimelineTrackList: fixed-width left column aligned with timeline lanes
TimelineLanes: stable row heights with no layout shift during playback
```

Required visual language:

```text
background: #070B0C / #080C0D
panel: #0D1214 / #101618
timeline lane: #0E1817
border: #1B2328 / #20282D
muted text: #8F9AA5 / #9AA4AE
primary text: #D8DEE6
green accent: #7BE7AD
blue clip accent: #66C7FF
purple clip accent: #8B6BF0
deep clip body: #2D214C
```

Dear ImGui style targets:

```text
WindowRounding: 0
ChildRounding: 0 to 6 depending on region
FrameRounding: 6 to 8
GrabRounding: 8
ScrollbarRounding: 6
FrameBorderSize: 1 where the reference shows stroked controls
WindowPadding: dense editor spacing, not landing-page spacing
ItemSpacing: compact and stable
```

Required visible controls:

```text
left toolbar tool icons
top toolbar tool icons
Open Folder
Render
Export
asset card grid with add tile
centered portrait preview viewport
timecode
play button
undo / redo
timeline zoom control
timeline ruler
track rows with visibility and audio controls
video, shape, transition, and future layer clips as visual state only
```

Reference UI red lines:

```text
The screenshot locks the UI shape, not engine authority.
Timeline clips displayed by ImGui are accepted project state only.
Asset cards displayed by ImGui are accepted project state only.
Fixture clips are allowed only in an explicit design-fixture mode.
Production starts empty until OpenProject or ImportAsset returns accepted engine state.
The preview viewport must be blank or diagnostic-blocked until FinalFrameSurface is ready.
No placeholder video, MediaPlayer, WebView, Canvas, or UI-generated preview may occupy the preview viewport.
```

UI acceptance gates:

```text
3360x1824 screenshot comparison against the locked reference
1920x1080 screenshot comparison for responsive desktop behavior
all major regions present and proportionally aligned
no text overflow in buttons, asset cards, track rows, or clips
no card-inside-card layout except real repeated items
timeline row dimensions stable during playback and scrub
preview viewport displays only the native GPU texture from FinalFrameSurface
diagnostics visible when Gates, RenderGraph, FXPassGraph, or FinalFrameSurface blocks playback
```

## 6. Command Boundary

All editor actions must enter as commands:

```text
OpenProject(path)
ImportAsset(path)
AddClip(assetId, trackId, startFrame)
SetPlayhead(frameIndex)
BeginPlayback
StopPlayback
BeginScrub
ScrubTo(frameIndex)
EndScrub
RequestPreviewFrame(frameIndex)
RequestExport(profile)
```

Commands may mutate project files only through the approved project/engine command layer. UI widgets must not write `timeline.json`, `composition.json`, or `assets/assets.json` directly.

## 7. FinalFrameSurface Contract

`FinalFrameSurface` is the only accepted visual output contract:

```text
frameIndex
time
width
height
pixelFormat
colorSpace
gpuTextureHandle
backend
diagnostics
resourceLifetimeToken
```

Preview, Live Scope, and Export must consume this same frame meaning. They may use different output wrappers, but not different scene truth.

## 8. Scheduler Rule

Playback, scrub, preview, live scopes, and export must not create separate clocks.

Required scheduler properties:

```text
one frame scheduler
integer frame index truth
deterministic seek
decode-ahead queue
texture cache
FinalFrameSurface pool
RenderGraph incremental invalidation
frame time metrics
```

Performance budgets:

```text
60fps preview target: 16.6ms frame budget
30fps preview target: 33.3ms frame budget
all missed budgets must produce diagnostics
```

No claim of "no lag" is accepted without measurement.

## 9. macOS Phase Plan

Phase 0: Project Cleanup

```text
remove cancelled Qt path
remove stale native UI plans from active reading order
make IMGUI Professional the active native desktop plan
```

Phase 1: Minimal Native Window

```text
C++ entrypoint
macOS native window
Metal device
Dear ImGui context
empty editor shell
diagnostics panel
frame timing overlay
```

Phase 2: FinalFrameSurface Smoke

```text
open a valid test project
request frame 0
run Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph
produce FinalFrameSurface
display FinalFrameSurface texture in ImGui preview viewport
```

Phase 3: Project Commands

```text
OpenProject
ImportAsset
AddClip
SetPlayhead
RequestPreviewFrame
```

Phase 4: Playback

```text
single scheduler
decode-ahead
texture cache
frame pool
play/pause
scrub
accepted-frame diagnostics
```

Phase 5: Live Scope

```text
consume FinalFrameSurface only
no separate renderer
no separate media path
```

Phase 6: Export

```text
consume the same frame contract
no separate scene interpretation
deterministic frame iteration
native encoder handoff
```

Windows work begins only after macOS Phase 2 is accepted with visual proof.

## 10. Acceptance Gates

No phase is accepted without proof.

Required gates:

```text
build passes
architecture verifier passes
no alternate preview path exists
no MediaPlayer/WebView/Canvas token exists in native desktop app
probe can request frame 0 and returns FinalFrameSurface ready
preview viewport displays the same FinalFrameSurface
diagnostics identify the failing stage when blocked
```

The first visual milestone is not timeline editing. It is one real frame on macOS M1 from `FinalFrameSurface`.

## 11. Active Decision

The active native desktop strategy is:

```text
Dear ImGui UI
C++ shared engine boundary
macOS Metal first
Windows Direct3D second
FinalFrameSurface as the only visual truth
```

Qt, Flutter, WebView, browser canvas preview, media-player preview, and any UI-owned renderer are not part of this native desktop strategy.
