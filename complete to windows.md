# Complete To Windows

This document is the mandatory handoff for completing the current IMGUI Professional native editor on Windows.

The goal is not to rebuild the editor, not to introduce a second UI, and not to reinterpret project files. The goal is to keep the current C++ Dear ImGui shell and shared HyperFrame truth, then replace only the macOS platform backend with a Windows-native GPU and encoder backend.

## Current Proven State

The macOS implementation currently proves the target architecture:

```text
Dear ImGui UI
-> commands only
-> Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> PlatformRenderFrameExecutor
-> FinalFrameSurface
```

The macOS platform backend is:

```text
MacMetalRenderFrameExecutor
-> Metal texture FinalFrameSurface
-> Preview / Live Scope / Export
-> VideoToolbox hardware encoder
-> AVAssetWriter MP4
-> accepted AudioGraph mux
```

Windows must reach the same architecture with:

```text
WindowsD3DRenderFrameExecutor
-> Direct3D texture FinalFrameSurface
-> Preview / Live Scope / Export
-> Media Foundation hardware encoder
-> MP4
-> accepted AudioGraph mux
```

## Non-Negotiable Rules

1. The UI is display and command only.
2. The UI must not own timeline truth, frame truth, clock truth, layer truth, FX truth, render truth, preview truth, or export truth.
3. No WebView, MediaPlayer, Canvas, GDI, CPU compositor, or fake preview fallback is allowed.
4. Preview, Live Scope, and Export must consume the same accepted `FinalFrameSurface`.
5. Export must not parse layers, FX, animation, keyframes, or project scene files.
6. Windows must not invent different FX behavior from macOS.
7. If a feature is not yet implemented in the Windows executor, fail closed with diagnostics. Do not silently approximate.
8. The shared HyperFrame path is the source of truth:

```text
Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> FinalFrameSurface
```

## What Changes On Windows

Only the platform layer changes.

Keep:

```text
apps/imgui/src/ui/*
apps/imgui/src/authoring/*
apps/imgui/src/timeline/*
apps/imgui/src/query/*
src/core/hyperframe/*
project ingestion / Gates semantics
FrameDescriptor semantics
RenderGraph semantics
FXPassGraph semantics
FinalFrameSurface contract
ExportMode scheduler contract
```

Replace or add:

```text
apps/imgui/src/platform/windows/WinApp.cpp
apps/imgui/src/platform/windows/WindowsD3DRenderFrameExecutor.*
apps/imgui/src/platform/windows/WindowsMediaFoundationExporter.*
apps/imgui/src/platform/windows/WindowsAudioGraph.*
apps/imgui/src/platform/windows/WindowsFileDialog.*
apps/imgui/src/platform/windows/WindowsProjectWatcher.*
```

macOS-specific implementation:

```text
MacApp.mm
MacMetalRenderFrameExecutor
Metal pipelines
AVFoundation / VideoToolbox
FSEventStream
NSOpenPanel / NSSavePanel
CVMetalTextureCache
```

Windows equivalent:

```text
Win32 window + Dear ImGui DirectX backend
Direct3D 11 or Direct3D 12 GPU device
WindowsD3DRenderFrameExecutor
Media Foundation decoding as source texture provider only
Media Foundation hardware encoder for export
ReadDirectoryChangesW or equivalent project watcher
IFileOpenDialog / IFileSaveDialog
DXGI / DirectComposition presentation as needed
```

## Windows Target Architecture

```text
Win32 / Dear ImGui shell
-> command bridge
-> accepted workspace state
-> Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> WindowsD3DRenderFrameExecutor
-> FinalFrameSurface (ID3D11Texture2D or D3D12 resource)
```

Then:

```text
FinalFrameSurface
-> Preview viewport
FinalFrameSurface
-> Live Scope readback / compute histogram
FinalFrameSurface
-> ExportMode
-> Media Foundation hardware encoder
-> MP4
-> AudioGraph mux
```

The same frame index, same `FrameDescriptor`, same `RenderGraph`, same `FXPassGraph`, and same accepted `FinalFrameSurface` must drive all three consumers.

## Recommended Windows Backend Choice

Start with Direct3D 11 unless the project already has a strong D3D12 requirement.

Reason:

```text
Dear ImGui has mature DX11 backend.
Media Foundation texture interop is simpler.
ID3D11Texture2D is enough for the current FinalFrameSurface contract.
The goal is parity and correctness first, not a premature low-level renderer rewrite.
```

The architecture should not prevent a later D3D12 executor. The shared interface should be platform-neutral:

```cpp
class PlatformRenderFrameExecutor {
 public:
  virtual FinalFrameSurfaceResult render(
      const WorkspaceViewState& workspace,
      int64_t frameIndex,
      uint64_t requestGeneration,
      bool allowPreserve,
      bool waitForCompletion) = 0;
};
```

macOS implementation:

```text
MacMetalRenderFrameExecutor
```

Windows implementation:

```text
WindowsD3DRenderFrameExecutor
```

## Step 1 - Build The Windows Shell Without Rendering Authority

Create the Windows entrypoint and window loop:

```text
WinApp.cpp
Win32 window
Dear ImGui context
ImGui_ImplWin32
ImGui_ImplDX11
same DrawEditorShell(config)
same EditorShellResult command bridge
```

The shell must compile and show the same UI. At this stage the preview may show a diagnostic only:

```text
Preview blocked: WindowsD3DRenderFrameExecutor is not connected.
```

Do not add a video player. Do not add fake preview pixels.

## Step 2 - Port Project Binding And Authoring Commands

Use Windows-native dialogs:

```text
Open Folder -> IFileOpenDialog with folder picker
Export -> IFileSaveDialog
Import media/audio -> IFileOpenDialog
```

Keep the same command names and payload meanings currently emitted by ImGui:

```text
OpenProject
RequestRender
RequestExport
SelectLibrarySection
ImportMedia
ImportAudio
AddAssetClip
AddTextLayer
AddBackgroundLayer
AddShapeLayer
ScrubTimeline
BeginPlayback
```

The command bridge must call the same accepted workspace reload and `ProjectAuthoringService` behavior. The UI must not write project JSON directly.

## Step 3 - Create WindowsD3DRenderFrameExecutor

The Windows executor must consume the same accepted `WorkspaceViewState` and the same compiled frame truth as macOS.

Required executor outputs:

```text
FinalFrameSurfaceResult.status = Accepted | Preserved | Rejected
FinalFrameSurfaceResult.frameIndex
FinalFrameSurfaceResult.generation
FinalFrameSurfaceResult.diagnostic
FinalFrameSurfaceResult.texture = ID3D11Texture2D-backed surface
```

Fail closed if:

```text
project is not accepted
frame index is invalid
source texture is missing
FX pass is unsupported
D3D device is unavailable
GPU command fails
surface cannot be produced
```

Do not return accepted if the actual final frame was not rendered.

## Step 4 - Source Textures On Windows

Video and image assets are sources only. They are not preview engines.

Windows video source:

```text
Media Foundation
-> decode accepted asset frame
-> GPU-compatible texture
-> consumed by WindowsD3DRenderFrameExecutor
```

Windows image source:

```text
WIC or equivalent native decoder
-> GPU texture
-> consumed by WindowsD3DRenderFrameExecutor
```

SVG source:

```text
same pinned LunaSVG path
-> raster source surface
-> GPU texture
-> consumed by RenderGraph/FXPassGraph execution
```

No media source may bypass `RenderGraph` or `FXPassGraph`.

## Step 5 - Port RenderGraph And FXPassGraph Execution

The Windows executor must implement the same visual semantics currently proven on macOS:

```text
video
image
text
shape
audio as AudioGraph only
background
rounded corners
border
drop shadow
opacity
position / scale / rotation
Gaussian blur
motionTile mirror/repeat/clamp behavior
transform motion blur
SVG assets
```

Shader implementation may differ by language:

```text
macOS -> Metal Shading Language
Windows -> HLSL
```

But the behavior must match. Do not change effect meaning.

Every unsupported FX must emit a diagnostic like:

```text
FXPassGraph rejected: WindowsD3DRenderFrameExecutor does not implement <effectName> for clip <clipId>.
```

## Step 6 - Preview From FinalFrameSurface

Dear ImGui should draw only the accepted D3D texture:

```text
FinalFrameSurface D3D texture
-> ImGui preview viewport texture id
```

The preview must not decode media directly.

The preview must not draw layers itself.

The preview must not use any fallback renderer.

## Step 7 - Live Scope From FinalFrameSurface

Live Scope must read the accepted `FinalFrameSurface`.

Preferred Windows path:

```text
FinalFrameSurface D3D texture
-> GPU compute histogram / luma reduction
-> small readback buffer
-> display-only ImGui scope
```

Acceptable first native step:

```text
FinalFrameSurface D3D texture
-> staging readback of reduced data only
-> display-only ImGui scope
```

Do not run Live Scope from source video frames. Do not sample timeline layers separately.

## Step 8 - Playback And Scrub Scheduler

Reuse the current scheduler contract:

```text
one frame truth
one requested frame index
one accepted frame index
one generation
one ExportMode
```

Playback:

```text
NativeRealtimeResourceScheduler
-> requested frame index
-> WindowsD3DRenderFrameExecutor.render(...)
-> accepted FinalFrameSurface
-> preview and scope consume accepted surface
```

Scrub:

```text
mouse drag
-> frame index command only
-> scheduler request
-> WindowsD3DRenderFrameExecutor
-> FinalFrameSurface
```

No UI-owned time seconds. No UI-owned clock.

## Step 9 - Windows Export

Export must match the macOS contract:

```text
RequestExport
-> IFileSaveDialog
-> ExportMode exclusive
-> stop playback/scrub background work
-> for frameIndex in [0, durationFrames)
   -> WindowsD3DRenderFrameExecutor.render(..., waitForCompletion=true)
   -> require Accepted FinalFrameSurface
   -> submit FinalFrameSurface to Media Foundation hardware encoder
-> mux accepted AudioGraph
-> MP4
-> verify output file exists and size > 0
```

Media Foundation must be an encoder/mux backend only. It must not become render truth.

Required diagnostics:

```text
encoder backend
hardware acceleration proof
frame size
frame rate
pixel format
audio track count
output file path
output bytes
fallbacks rejected
```

If hardware encoding is unavailable:

```text
Export rejected: Media Foundation hardware encoder unavailable.
```

Do not silently use software encoding unless the project owner explicitly changes the red-line rule.

## Step 10 - Audio On Windows

Preview audio and export audio must come from the accepted AudioGraph concept.

Windows preview audio:

```text
accepted audio/video source clips
-> Media Foundation / WASAPI decode path
-> scheduled against accepted timeline frame clock
```

Windows export audio:

```text
accepted AudioGraph
-> Media Foundation mux with encoded FinalFrameSurface video
```

Audio must not give the UI or encoder any visual render authority.

## Step 11 - Project Watcher

macOS currently uses `FSEventStream`.

Windows should use:

```text
ReadDirectoryChangesW
```

Watch only canonical project paths:

```text
project.json
composition.json
timeline.json
assets/assets.json
assets/originals
native-scenes/main
```

Debounce reloads. Invalid or partially written files must preserve the previous accepted state.

## Step 12 - Required Tests Before Windows Is Accepted

Windows must have headless smoke commands equivalent to macOS:

```text
--pixel-parity-smoke <workspace>
--performance-smoke <workspace> --frames <n>
--scrub-performance-smoke <workspace> --frames <n>
--export-smoke <workspace> --output <path>
```

Minimum acceptance:

```text
preview/export FinalFrameSurface pixels match for the same frame
performance average and max are reported
scrub forward and reverse are reported
exported MP4 exists and size > 0
exported MP4 contains accepted audio when the workspace has audio
unsupported FX fail closed with diagnostics
```

## Step 13 - CMake Layout

Keep one app target with platform-specific source selection:

```text
apps/imgui/CMakeLists.txt
```

Expected shape:

```cmake
if(APPLE)
  target_sources(makelab-imgui-professional PRIVATE
    src/platform/macos/MacApp.mm
  )
endif()

if(WIN32)
  target_sources(makelab-imgui-professional PRIVATE
    src/platform/windows/WinApp.cpp
    src/platform/windows/WindowsD3DRenderFrameExecutor.cpp
    src/platform/windows/WindowsMediaFoundationExporter.cpp
  )
endif()
```

Shared files must not be duplicated for Windows.

## Step 14 - What The Windows Agent Must Not Do

Do not:

```text
create a new UI framework
replace ImGui
create a Qt/QML path
create a WebView preview
create a MediaPlayer preview
parse timeline JSON inside export
parse FX inside export
draw layers in UI
use GDI as compositor
use CPU as normal compositor
invent Windows-only FX semantics
accept preserved/rejected frames in export
silently downgrade hardware encoding
```

## Step 15 - First Windows Milestone

The first milestone is not a complete editor.

The first milestone is:

```text
Open the same project folder on Windows
-> UnitedGate accepts it
-> request frame 0
-> WindowsD3DRenderFrameExecutor produces an Accepted FinalFrameSurface
-> ImGui preview displays that D3D texture
```

After that:

```text
playback
live scrub
live scope
export
performance parity
FX parity
```

## Final Definition Of Done

Windows is complete only when:

```text
same UI
same commands
same accepted project files
same Timeline Truth
same FrameDescriptor semantics
same RenderGraph semantics
same FXPassGraph semantics
same FinalFrameSurface concept
Preview consumes FinalFrameSurface
Live Scope consumes FinalFrameSurface
Export consumes FinalFrameSurface
Media Foundation encodes only after FinalFrameSurface
AudioGraph is muxed into MP4
headless parity/performance/export smokes pass
no fallback renderer exists
```

The Windows implementation is a platform backend completion, not a new product.

