# Windows Platform Boundary

This folder is the only allowed implementation boundary for the Windows native
adapter.

## Mandatory Path

```text
Win32 / Dear ImGui
-> commands only
-> Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> WindowsD3DRenderFrameExecutor
-> FinalFrameSurface
```

Then the same `FinalFrameSurface` must feed:

```text
Preview
Live Scope
Export
```

## Red Lines

```text
Do not touch apps/imgui/src/platform/macos.
Do not copy or fork apps/imgui/src/ui.
Do not create a Windows-only UI.
Do not use OS media-player preview, embedded browser preview, GDI preview, or CPU preview fallback.
Do not decode video directly into the preview.
Do not reinterpret project JSON inside UI code.
Do not reinterpret FX, animation, transition, or timeline semantics.
Do not return an accepted FinalFrameSurface unless a real D3D final frame exists.
```

Unsupported work must fail closed with a diagnostic. A black or diagnostic
preview is acceptable during adapter construction; synthetic preview pixels are not.

## Implementation Order

1. Keep `WinApp.cpp` as a thin Win32 / Dear ImGui shell.
2. Connect Open Folder through `WindowsProjectDialog`, then accepted project
   loading through the same Gates and authoring/project services used by macOS.
3. Make Media Foundation produce source GPU textures only.
4. Make `WindowsD3DRenderFrameExecutor` execute FrameDescriptor, RenderGraph,
   and FXPassGraph into an `ID3D11Texture2D` FinalFrameSurface.
5. Display only that FinalFrameSurface in the ImGui preview viewport.
6. Drive playback and live scrub from the scheduler, not from UI time.
7. Export from the same FinalFrameSurface stream with Media Foundation encoding
   and accepted AudioGraph muxing.

## Files

```text
WinApp.cpp
  Windows entry point and command bridge. UI commands only.

WindowsD3DRenderFrameExecutor.*
  Direct3D FinalFrameSurface executor boundary. Must consume
  render/PlatformRenderContracts.hpp.

WindowsMediaFoundationTextureSource.*
  Media Foundation source texture boundary. Never a preview player.

WindowsProjectDialog.*
  Native Open Folder / file picker boundary.

WindowsProjectWatcher.*
  Native project-change watcher boundary.

WindowsExportExecutor.*
  ExportMode boundary. Must consume FinalFrameSurface.
```

## Shared Contracts To Use

```text
model/WorkspaceModel.hpp
  Accepted workspace, assets, tracks, clips, animation, and FX fields.

render/PlatformRenderContracts.hpp
  FinalFrameSurface request/status/generation contract.
```

Do not define duplicate Windows-only versions of these contracts.
