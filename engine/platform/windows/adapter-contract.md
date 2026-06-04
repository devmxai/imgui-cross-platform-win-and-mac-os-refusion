# Windows Adapter Contract

The Windows adapter executes Core-generated render contracts with native Windows technologies.

## Input

```text
FrameDescriptor
RenderGraph
FXPassGraph
platform capability request
source surfaces
```

## Output

```text
FinalFrameSurface
diagnostics
preview surface handoff
export frame handoff
```

## Critical Rules

```text
Do not reinterpret timeline.json independently.
Do not invent FX behavior in WinUI, Direct2D, Direct3D, Media Foundation, or encoder code.
Do not use platform-only sample planners unless they are generated from or checked against Core.
Do not add Windows FX names, aliases, or parameters unless they already exist in src/core/hyperframe/fx/fxRegistry.manifest.json.
Do not make XAML overlays the source of visual truth.
```

WinUI owns the shell. Windows renderer code owns pixels. Core owns meaning.
