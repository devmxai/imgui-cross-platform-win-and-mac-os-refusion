# Windows Platform Roadmap

This roadmap is the required path for completing the Windows native platform.
It keeps Windows work isolated, mergeable, and aligned with the proven macOS
path.

Read this together with:

```text
docs/shared-professional-development-structure.md
complete to windows.md
apps/imgui/src/platform/windows/README.md
```

## Repository Shape

```text
apps/imgui/src/ui/
  Shared Dear ImGui editor shell.

apps/imgui/src/model/
  Shared accepted workspace model. Windows must consume this, not duplicate it.

apps/imgui/src/authoring/
apps/imgui/src/timeline/
apps/imgui/src/query/
  Shared editor services and truth helpers.

apps/imgui/src/render/
  Shared FinalFrameSurface request/status contract.

apps/imgui/src/platform/macos/
  macOS native adapter. Do not modify for Windows work.

apps/imgui/src/platform/windows/
  Windows native adapter. Windows work starts here.
```

Future platforms may add sibling folders. The current native desktop platforms
are:

```text
platform/macos
platform/windows
```

## Single Truth Contract

Windows must implement the same path as macOS:

```text
Dear ImGui UI
-> commands only
-> Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> WindowsD3DRenderFrameExecutor
-> FinalFrameSurface
```

The same accepted `FinalFrameSurface` must feed:

```text
Preview
Live Scope
Export
```

## Absolute Red Lines

```text
No UI-owned render truth.
No UI-owned timeline clock.
No OS media-player preview.
No GDI preview.
No CPU compositor preview.
No embedded-browser preview.
No synthetic bitmap fallback.
No Windows-only FX interpretation.
No project JSON edits from UI code.
No macOS file edits for Windows work.
```

If a feature is missing, show a diagnostic and fail closed.

## Windows Build Slice Order

### Slice 1 - Shell

```text
WinApp.cpp
Win32 window
Direct3D 11 device
Dear ImGui Win32/DX11 backend
same DrawEditorShell(config)
same EditorShellResult commands
```

Status: skeleton exists. Preview is diagnostic-only until a real
`FinalFrameSurface` exists.

### Slice 2 - Open Folder Through Gates

```text
OpenProject command
-> WindowsProjectDialog::OpenProjectFolder
-> accepted workspace reload through the existing project/Gates boundary
-> WorkspaceViewState update
```

The dialog only selects a folder. It must not parse or reinterpret render truth
inside UI code.

### Slice 3 - Source Textures

```text
Media Foundation
-> decode video frame
-> ID3D11Texture2D source texture
-> RenderGraph source node
```

Images use WIC or equivalent native decoding into source textures. SVG remains
the pinned LunaSVG path before GPU upload.

### Slice 4 - D3D FinalFrameSurface

```text
FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> WindowsD3DRenderFrameExecutor
-> ID3D11Texture2D FinalFrameSurface
```

Do not return accepted unless the final frame was produced by D3D.

Use:

```text
apps/imgui/src/render/PlatformRenderContracts.hpp
```

for request generation, intent, and accepted/rejected status.

### Slice 5 - Playback / Live Scrub

The scheduler owns time and frame acceptance. UI only sends commands.

```text
BeginPlayback
ScrubTimeline(frameIndex)
-> scheduler
-> requested frame
-> accepted FinalFrameSurface
```

### Slice 6 - Export

```text
Export command
-> ExportMode scheduler ownership
-> frame-by-frame FinalFrameSurface
-> Media Foundation encoder
-> accepted AudioGraph mux
-> MP4
```

Export must never parse layers or FX independently.

## Pull / Merge Rule

Windows work should live on a Windows branch until it reaches a working adapter:

```text
platform/windows-d3d
```

Allowed common-file edits:

```text
apps/imgui/CMakeLists.txt
docs/*
```

Only edit shared UI/core/contracts when a missing shared contract is identified
and approved. Platform-specific implementation belongs in:

```text
apps/imgui/src/platform/windows/
```

After Windows is merged, shared UI/core/FX changes should be pulled normally by
both macOS and Windows. Platform-specific GPU passes are implemented only in
their own platform folders.
