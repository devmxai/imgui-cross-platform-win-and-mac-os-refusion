# Shared Professional Development Structure

This document defines where every future feature must be built so macOS,
Windows, and future platforms stay on one professional source path.

## Master Rule

Build truth once in the correct shared layer. Platform adapters only execute
that truth on native hardware.

```text
Shared Core
-> Shared Workspace Model
-> Shared Render Contract
-> Shared Timeline / Authoring / Query
-> Shared Dear ImGui UI
-> Platform Adapter
-> FinalFrameSurface
```

The accepted frame path remains:

```text
Gates
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> PlatformRenderFrameExecutor
-> FinalFrameSurface
```

## Ownership Matrix

| Change type | Primary folder | Platform work required |
| --- | --- | --- |
| UI layout, buttons, panels, timeline visuals | `apps/imgui/src/ui/` | No, unless a platform backend cannot display ImGui correctly |
| workspace, asset, track, clip state | `apps/imgui/src/model/` | No |
| edit commands, trim, split, move, add layer | `apps/imgui/src/authoring/` and `src/core/hyperframe/project/` | No, platform reloads accepted state |
| frame/time math, snap, ranges | `apps/imgui/src/timeline/` and `src/core/hyperframe/timeline/` | No |
| agent-visible frame/layer queries | `apps/imgui/src/query/` and `src/core/hyperframe/frame/` | No |
| FinalFrameSurface request/status contract | `apps/imgui/src/render/` and `src/core/hyperframe/render-plan/` | No, unless native handles are needed |
| FX name, schema, defaults, semantics | `src/core/hyperframe/fx/` | Yes, if native GPU execution is needed |
| RenderGraph or FXPassGraph meaning | `src/core/hyperframe/render-plan/` and `src/core/hyperframe/fx/` | Yes, adapters execute the new contract |
| decode, GPU resources, native preview surface | `apps/imgui/src/platform/<platform>/` | Yes, platform-specific |
| Open Folder, file import, project watcher | `apps/imgui/src/platform/<platform>/` | Yes, platform-specific |
| export encoder and mux | `apps/imgui/src/platform/<platform>/` plus shared export contract | Yes, platform-specific |

## Shared Core Rules

Core owns meaning:

```text
project contracts
workspace model
timeline semantics
animation evaluation
FX schemas and normalization
FrameDescriptor
RenderGraph
FXPassGraph
FinalFrameSurface contract
export contract
diagnostics
```

Core must not import UI or platform adapters. If a behavior changes what a
frame, layer, FX, animation, timeline value, or export means, it starts in Core.

## Shared UI Rules

The Dear ImGui UI is shared. It may:

```text
draw controls
draw timeline panels
draw asset and layer lists
draw diagnostics
show accepted FinalFrameSurface texture
send commands
```

It must not:

```text
decode media
compose layers
interpret FX
own playback time
own export frames
write project files directly
create alternate preview pixels
```

## Timeline / Authoring Rules

Editing features are shared. A trim/split/move feature must follow:

```text
UI gesture
-> shared command
-> ProjectAuthoringService / Core operation
-> Gate validation
-> accepted workspace state
-> platform render request
```

Platforms must not implement their own meaning for edit commands.

## Platform Adapter Rules

Platform folders own native execution only:

```text
apps/imgui/src/platform/macos/
apps/imgui/src/platform/windows/
```

Allowed platform responsibilities:

```text
native window bootstrap
native file dialogs
project file watcher
native decode as source textures
native GPU passes
FinalFrameSurface allocation
preview texture presentation
live scope readback or compute
native encoder and audio mux
capability diagnostics
```

Forbidden platform responsibilities:

```text
changing FX meaning
changing timeline meaning
forking shared UI
inventing alternate preview or export truth
silently approximating unsupported effects
```

Unsupported platform features must fail closed with diagnostics.

## Feature Development Flows

### UI Feature

```text
apps/imgui/src/ui/
-> emits command or displays accepted state
-> shared tests if behavior changed
```

No platform code should be needed.

### Timeline Editing Feature

```text
Core timeline operation
-> ProjectAuthoringService command
-> UI command wiring
-> query/parity tests
-> platform displays accepted result
```

### FX Feature

```text
Core FX registry / schema
-> normalizer / planner
-> FrameDescriptor / FXPassGraph contract
-> macOS Metal pass
-> Windows D3D/HLSL pass
-> parity diagnostics/tests
```

The UI may add controls only after the shared contract exists.

### Export Feature

```text
Shared export meaning
-> platform ExportMode executor
-> frame-by-frame FinalFrameSurface
-> native encoder
-> accepted audio mux
```

Export must never parse layers or FX through a second path.

## Branching Rule

Platform-specific implementation can live on platform branches:

```text
platform/windows-d3d
platform/macos-metal
```

Shared features should be merged through `main` only after shared tests pass.
Platform branches pull `main` to receive shared UI/Core updates.

## Contract Extraction Rule

If macOS proves a behavior first, do not ask Windows to copy the behavior from
`platform/macos`. Extract the shared meaning into:

```text
apps/imgui/src/model/
apps/imgui/src/render/
apps/imgui/src/timeline/
apps/imgui/src/query/
src/core/hyperframe/
```

Then each platform implements only the native execution needed to satisfy the
same contract.

## Long-Term Expansion Rule

Future platforms must be siblings, not forks:

```text
apps/imgui/src/platform/ios/
apps/imgui/src/platform/android/
```

They must consume the same Core, UI, Timeline, Authoring, Query, RenderGraph,
FXPassGraph, and FinalFrameSurface contracts.
