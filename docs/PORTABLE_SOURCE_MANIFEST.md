# Portable Source Manifest

This repository is the portable source-of-truth checkpoint for the current native Dear ImGui editor and its engine path.

Cloning `main` must restore the current source state without requiring the previous repository.

## Required Path

```text
Project files / commands
-> Transaction Gate / UnitedGate contracts
-> HyperFrame IR
-> FrameDescriptor / sub-frame descriptor
-> Render plan / RenderGraph contracts
-> FX Registry / Normalizer / FXPassGraph
-> Platform render executor
-> FinalFrameSurface / FinalFrameStream contracts
-> Dear ImGui preview display
```

## Repository Contents

```text
apps/imgui/
  Current Dear ImGui native application.
  Contains the latest macOS Metal execution and UI state reached in development.
  Uses a shared source layout: model, ui, timeline, authoring, query, and render
  contracts are shared across platforms; platform folders own native hardware
  and OS integration.
  Pins Dear ImGui to the exact dependency commit used by the validated build.
  Vendors the exact Font Awesome Free 7.2.0 Solid icon font and license used by
  the shared native editor shell.
  Contains the shared C++ ProjectAuthoringService, its focused tests, candidate
  project validation, and atomic accepted-project writes used by native adapters.
  Contains the shared C++ WorkspaceModel contract for accepted assets, tracks,
  clips, animation, visual fields, and FX fields consumed by UI, query, and
  platform render executors.
  Contains the shared C++ FrameQueryService for evaluated queryFrame,
  queryLayerAtPixel, deterministic FrameTruthFingerprint parity checks, and
  pixel-true viewport/composition transforms used by agent-visible truth.
  Contains the shared C++ PlatformRenderContracts header for
  FinalFrameSurface request/status/generation diagnostics consumed by native
  platform executors.
  The macOS adapter includes a native FSEventStream workspace watcher and
  accepted-state refresh command. Windows must provide the equivalent watcher
  behind the same project refresh boundary.
  The macOS Open Folder picker is presented asynchronously; selecting a folder
  triggers project ingestion after the native picker returns.
  The macOS app displays native performance telemetry from the platform bridge:
  render submit time, Live Scope readback time, frame budget, FinalFrameSurface
  memory size, requested frame, accepted frame, and request generation.
  It also exposes headless pixel parity and performance smoke modes so CI/local
  verification can prove preview/export pixel identity and native render timing
  without giving the UI any render, clock, or media authority.
  Portable pixel-parity and heavy-FX fixtures are included under
  apps/imgui/tests/fixtures so the current render path can be validated after a
  fresh clone without depending on user media projects.

src/core/hyperframe/
  Shared engine contracts and algorithms:
  project types, transaction gate, IR, FrameDescriptor, FX registry,
  effect normalizer, FXPassGraph, quality policy, render planning,
  FinalFrameSurface request contract, and timeline operation contracts.
  SVG assets are source textures only: pinned LunaSVG rasterizes SVG into a native GPU texture before RenderGraph/FXPassGraph, with no UI or preview fallback ownership.

engine/platform/macos-reference/
  Reference native macOS engine execution sources:
  UnitedGate, CanonicalHyperFrameBridge, RenderGraph, FXPassGraph,
  Metal FX runtime, native render engine, FinalFrameSurface,
  motion blur quality planner, and native timeline exporter.

engine/platform/windows/
  Cross-platform Windows adapter contract and implementation map.
  This is the required boundary for a future Direct3D / Media Foundation executor.

apps/imgui/src/platform/windows/
  Native Windows adapter skeleton:
  Win32 / Direct3D Dear ImGui shell, WindowsD3DRenderFrameExecutor fail-closed
  boundary, Media Foundation source texture boundary, native dialog boundary,
  project watcher boundary, and export boundary. It is intentionally not a fake
  preview; it exists so Windows work can proceed in the correct platform folder
  without touching macOS or forking the shared UI.

docs/
  Governing architecture, shared development ownership, FX standard, portable
  status, and platform plans.

scripts/
  Verifiers that fail when a required part of this portable source path is missing.
```

## Deliberately Excluded

```text
Qt UI
Web UI
Web V2 UI
Flutter UI
SwiftUI ContentView / legacy macOS UI
generated build directories
node_modules
media projects and user assets
```

The macOS reference Swift files are included only because they document and execute engine/platform behavior. The active desktop UI in this repository is Dear ImGui.

## Restore

```bash
git clone https://github.com/devmxai/imgui-cross-platform-win-and-mac-os-refusion.git
cd imgui-cross-platform-win-and-mac-os-refusion
npm run verify
```

Build the current macOS ImGui app:

```bash
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
```

The `main` branch always contains the latest accepted portable source state. Tags are additional immutable recovery points.

## Recovery Guarantee

After cloning `main`, all committed source and governing documents needed to
continue from the current ImGui/HyperFrame state are restored. Run:

```bash
npm install
npm run verify
cmake -S apps/imgui -B apps/imgui/build
cmake --build apps/imgui/build
```

This guarantee covers source and documents. It deliberately does not include
generated build output, dependency caches, user media, or project workspaces.
The current macOS implementation is buildable. Windows receives the same Core
contracts and a dedicated platform skeleton, while its full Direct3D /
Media Foundation FinalFrameSurface executor still needs to be completed.
