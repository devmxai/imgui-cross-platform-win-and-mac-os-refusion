# macOS Adapter Contract

The macOS adapter executes Core-generated render contracts with native technologies.

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
export frame handoff
```

## Critical Rules

```text
Do not reinterpret timeline.json independently.
Do not invent FX behavior in Swift.
Do not use platform-only sample planners unless they are generated from or checked against Core.
Do not add Swift FXRegistry names, aliases, or parameters unless they already exist in src/core/hyperframe/fx/fxRegistry.manifest.json.
Do not open Metal compute encoders while render encoders are active.
Do not alter destination bounds for source-sampling effects such as motionTile.
```

## Required Gates

```text
npm run architecture:verify
npm run macos:structure:verify
cd macos-native && swift build
cd macos-native && ./Scripts/build-app.sh
```
