# IMGUI Cross Platform Win and Mac OS refusion

Independent native C++ / Dear ImGui desktop editor repository.

The `main` branch is the latest complete portable source state. Cloning `main`
restores the current Dear ImGui application, the authoritative HyperFrame Core
contracts, the macOS native execution reference, Windows continuation
contracts, and the governing architecture documents.

Current validated platform:

```text
macOS Apple Silicon
Dear ImGui UI
C++ / Objective-C++
Metal
AVFoundation / VideoToolbox texture sources
```

Planned second platform:

```text
Windows
Dear ImGui UI
C++
Direct3D
Media Foundation texture sources
```

Windows now has an isolated platform skeleton under:

```text
apps/imgui/src/platform/windows/
```

It is intentionally fail-closed until the Direct3D executor produces a real
`FinalFrameSurface`; it must not be converted into a MediaPlayer or fake preview
path.

## Non-Negotiable Architecture

```text
ImGui UI
  -> commands and display only

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

Preview, Live Scope, and Export must consume the same `FinalFrameSurface` truth.

Forbidden:

```text
UI-owned rendering
fake preview
MediaPlayer fallback
WebView fallback
Canvas fallback
alternate preview or export truth
```

## Current macOS Status

The current checkpoint builds and runs on macOS Apple Silicon.

Validated functionality includes:

```text
native ImGui editor shell
Open Folder project loading
native Metal FinalFrameSurface preview
video, image, text, shape, and background visual nodes
timeline playback and live scrub commands
motionTile Metal execution
gaussianBlur Metal execution
transformMotionBlur temporal accumulation
adaptive high-quality rotation blur
event-driven idle rendering
bounded video texture cache
Objective-C++ ARC memory management
```

See [Current macOS Status](docs/CURRENT_MACOS_STATUS.md) for validation details and remaining work.

## Portable Complete Source

The repository preserves the current accepted source path:

```text
Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> platform render executor
-> FinalFrameSurface
-> Dear ImGui display
```

The active ImGui application and the portable engine contracts are verified
together. A missing required file, broken Core-relative import, invalid FX
manifest, or excluded legacy UI path fails `npm run verify`.

Shared development ownership is fixed by
[Shared Professional Development Structure](docs/shared-professional-development-structure.md).
General features must enter the shared Core/UI/Timeline/Authoring layers first;
platform folders execute those contracts on native hardware.

Current shared app contracts are:

```text
apps/imgui/src/model/WorkspaceModel.hpp
apps/imgui/src/render/PlatformRenderContracts.hpp
apps/imgui/src/timeline/TimelineTruth.hpp
apps/imgui/src/authoring/ProjectAuthoringService.hpp
apps/imgui/src/query/FrameQueryService.hpp
apps/imgui/src/ui/EditorShell.hpp
```

See [Portable Source Manifest](docs/PORTABLE_SOURCE_MANIFEST.md) for the exact
included and excluded boundaries.

## Build

Requirements:

```text
macOS
Apple Clang
CMake 3.24+
Git
```

Build:

```bash
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
```

Run:

```bash
open -n apps/imgui/build/makelab-imgui-professional.app
```

Run with a workspace:

```bash
open -n apps/imgui/build/makelab-imgui-professional.app --args --open-workspace /absolute/path/to/project
```

## Verify Architecture

```bash
npm run verify
```

## Important Documents

- [IMGUI Professional Architecture Plan](docs/architecture/imgui-professional-plan.md)
- [Shared Professional Development Structure](docs/shared-professional-development-structure.md)
- [Professional HyperFrame FX Development Standard](docs/Professional%20HyperFrame%20FX%20Development%20Standard.md)
- [Current macOS Status](docs/CURRENT_MACOS_STATUS.md)
- [Portable Source Manifest](docs/PORTABLE_SOURCE_MANIFEST.md)
- [Windows Platform Roadmap](docs/windows-platform-roadmap.md)

## Repository Boundary

This repository is independent. It contains the native ImGui desktop
application, the complete current HyperFrame source path required by that
application, platform execution references/contracts, and governing
documentation. It does not inherit the Git history, remotes, web UI, Qt UI,
Flutter UI, or legacy SwiftUI shell from any previous repository.

Generated builds, `node_modules`, media projects, and user assets are not
committed. Windows contracts are present for continuing the same architecture,
but a complete Windows Direct3D executable remains future work.
