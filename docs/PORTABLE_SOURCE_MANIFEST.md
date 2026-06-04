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
  Pins Dear ImGui to the exact dependency commit used by the validated build.

src/core/hyperframe/
  Shared engine contracts and algorithms:
  project types, transaction gate, IR, FrameDescriptor, FX registry,
  effect normalizer, FXPassGraph, quality policy, render planning,
  FinalFrameSurface request contract, and timeline operation contracts.

engine/platform/macos-reference/
  Reference native macOS engine execution sources:
  UnitedGate, CanonicalHyperFrameBridge, RenderGraph, FXPassGraph,
  Metal FX runtime, native render engine, FinalFrameSurface,
  motion blur quality planner, and native timeline exporter.

engine/platform/windows/
  Cross-platform Windows adapter contract and implementation map.
  This is the required boundary for a future Direct3D / Media Foundation executor.

docs/
  Governing architecture, FX standard, portable status, and platform plans.

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
contracts and platform boundary, while its Direct3D/Media Foundation executor
still needs to be implemented.
