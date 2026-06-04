# To be known how to build for other platform

This document is the handoff reference for building MakeLab on any platform without losing the core architecture. It is intentionally strict: do not invent a new project truth, do not train each platform to understand timelines differently, and do not implement visual behavior as UI tricks.

## Non-Negotiable Architecture

Every platform must follow the same authority chain:

```text
UI / Agent / Command / Import / Script
-> UnitedGate
-> Project Contract Validator
-> HyperFrame IR
-> FrameDescriptor(frameIndex)
-> RenderGraph
-> FX PassGraph
-> Platform Renderer
-> Preview / Scrub / Play / Render / Export
```

The shared brain is everything up to and including `RenderGraph` plus the platform-neutral `FX PassGraph` contract. Platform teams do not reinterpret `timeline.json`, `assets/assets.json`, or `composition.json` directly inside their renderer.

## Core-First FX Rule

For every platform, FX development starts before the platform boundary. Motion Blur, Motion Trail, Motion Tile, Radial/Spin/Zoom, transitions, glow, and future FX must be defined by HyperFrame Core:

```text
timeline/style.effects
-> UnitedGate
-> HyperFrame IR
-> FrameDescriptor/sub-frame descriptor
-> FX Registry / Normalizer / Compiler
-> FXPassGraph
-> Platform Renderer Adapter
```

A platform backend may only execute the compiled `FXPassGraph`, declare capabilities, and emit diagnostics. It may not invent effect semantics, private sample plans, platform-only UI parameters, or silent approximations.

## Open Folder Contract

Open Folder is not a plain folder. It is a runtime contract. A valid project folder must contain:

```text
project.json
composition.json
timeline.json
assets/assets.json
assets/originals/
native-scenes/main/
```

The source of truth is:

```text
composition.json
timeline.json
assets/assets.json
```

`native-scenes/main/*` is a web compatibility surface. It is not the source of truth for native platforms.

Any agent or tool adding media must:

```text
1. Copy the original file into assets/originals/.
2. Register it in assets/assets.json.
3. Reference it by assetId from timeline.json.
4. Put all timing, geometry, motion, text, shapes, and FX in timeline.json.
```

No platform is allowed to infer visual truth from DOM, canvas side effects, scene JavaScript, duplicated layers, or generated preview-only code.

## What Is Shared Across Platforms

These layers must be platform-neutral and shared conceptually across macOS, Windows, Web, Android, and iOS:

```text
Project Contract
UnitedGate
Project Contract Validator
HyperFrame IR
Timeline Evaluator
Animation Evaluator
FrameDescriptor
RenderGraph
FX Registry
FX Compiler
FX PassGraph contract
Golden-frame tests
```

If a bug changes the meaning of a clip, keyframe, easing curve, effect parameter, coordinate, trim, duration, or asset identity, fix it before the platform renderer. Do not duplicate the fix in each platform.

## Where A New Platform Starts

A new platform starts after `RenderGraph` and the `FX PassGraph` contract:

```text
RenderGraph + FX PassGraph
-> Platform source providers
-> Platform renderer backend
-> Platform preview/play/scrub shell
-> Platform export writer
```

Examples:

```text
macOS    -> Metal + AVFoundation/VideoToolbox + CVPixelBuffer
Windows  -> DirectX/Vulkan/WebGPU + Media Foundation
Web      -> WebGL/WebGPU + browser media APIs
iOS      -> Metal + AVFoundation/VideoToolbox
Android  -> Vulkan/OpenGL/AGSL + MediaCodec
```

Do not rebuild the brain for Windows, Android, iOS, or Web. Build a platform backend that consumes the same `RenderGraph` and `FX PassGraph`.

## Coordinate And Timing Rules

All platforms must honor:

```text
Coordinate space: composition pixels
Origin: top-left
Units: px
Timebase: integer frame index
Clip start: absolute timeline seconds
Clip keyframes: clip-local seconds
Frame evaluation: deterministic by frameIndex
```

For any frame:

```text
timelineTime = frameIndex / fps
localTime = timelineTime - clip.start
mediaTime = clip.trimIn + localTime
```

Preview, scrub, play, render, and export must request the same evaluated frame authority:

```text
frameIndex
-> FrameDescriptor
-> RenderGraph
-> FX PassGraph
-> Platform Renderer
```

## Why FX Are Different From Text, Shapes, And Motion

Text, shapes, and transforms are direct render operations:

```text
text       -> text node draw
shape      -> geometry draw
rotation   -> transform matrix
scale      -> transform matrix
opacity    -> blend state
```

FX are pixel or texture processing operations. They require explicit passes:

```text
source texture
-> FX pass/shader
-> intermediate texture
-> transform pass
-> composite pass
```

Examples:

```text
motionTile    -> wrap/mirror sampling pass
motionBlur    -> temporal accumulation or velocity-aware blur pass
gaussianBlur  -> separable horizontal/vertical blur passes
glow          -> threshold + blur + additive/screen blend
colorCorrect  -> color matrix / LUT / curve pass
chromaKey     -> key mask + despill + composite pass
```

If an FX exists in `timeline.json` but does not appear visually, the issue is not Open Folder if it reaches `RenderGraph`. The issue is that the platform renderer does not yet implement the required `FX Pass`.

## Correct FX Architecture

FX must be implemented through one formal system:

```text
style.effects
-> FX Registry
-> FX Schema Validator
-> FX Compiler
-> FX PassGraph
-> Platform FX Runtime
```

Authoritative plan:

```text
docs/Professional HyperFrame FX Development Standard.md
```

The FX Registry, FX Schema, FX Normalizer, FX Compiler, and FX PassGraph are shared HyperFrame Engine responsibilities. They are not macOS-only work and must not be re-created per platform.

When building a new platform, keep:

```text
FX semantic meaning
FX parameter units
FX defaults
FX validation
FX pass ordering
FX temporal sampling contracts
FX golden-frame expectations
```

and replace only:

```text
Platform GPU backend
Texture allocator
Shader language
Pass executor
Display/output surface
Encoder integration
```

No platform may mark an FX as supported until that platform has an executable backend pass and passes the shared golden-frame contract.

An FX is valid only when it has:

```text
1. A schema in the FX Registry.
2. Normalization rules in the FX Compiler.
3. A deterministic pass in the FX PassGraph.
4. A platform implementation in the renderer backend.
5. Golden-frame coverage proving preview/export parity.
```

No FX may be implemented by:

```text
SwiftUI view tricks
DOM tricks
duplicated fake layers
opacity echo copies
preview-only code
export-only code
scene.js-only behavior
platform-specific timeline interpretation
```

## Motion Tile Example

Correct order:

```text
Video source texture
-> MotionTilePass(wrap/mirror sampling, expansion)
-> expanded intermediate texture
-> TransformPass(rotation/scale/position)
-> CompositePass
```

Incorrect order:

```text
SwiftUI view expansion
-> repeated Image views
-> outer rotation
```

The incorrect order can make the tile orientation drift from the actual rotation. It is not allowed.

## Motion Blur Example

Correct implementation:

```text
FrameDescriptor(frameIndex)
-> motion vectors or temporal sample plan
-> sample previous/current/next transforms deterministically
-> accumulate in shader/pass
-> composite final texture
```

Not allowed:

```text
duplicated layers
opacity echo fake copies
random time sampling
preview-only blur
export-only blur
```

## Preview And Export Parity

Preview and export must not contain separate visual logic.

Correct:

```text
Preview:
FrameDescriptor -> RenderGraph -> FX PassGraph -> Platform Renderer -> display

Export:
FrameDescriptor -> RenderGraph -> FX PassGraph -> Platform Renderer -> FinalFrameStream
FinalFrameStream + AudioPCM -> BMF encode/mux/output
```

BMF is only an encoder/mux executor. It is not a preview renderer, compositor, timeline interpreter, or FX engine.

## Platform Responsibilities

Each platform backend must provide:

```text
Media source provider
Texture/image resolver
Font/text renderer
Shape renderer
FX pass runtime
Compositor
Audio source provider
Preview/play/scrub scheduler
Export frame stream writer
Diagnostics/reporting
```

Platform-specific examples:

```text
macOS:
AVFoundation/VideoToolbox -> CVPixelBuffer -> CVMetalTextureCache -> Metal

Windows:
Media Foundation -> GPU texture -> DirectX/Vulkan/WebGPU

Web:
HTMLVideoElement/WebCodecs -> WebGL/WebGPU texture

Android:
MediaCodec -> SurfaceTexture/HardwareBuffer -> Vulkan/OpenGL/AGSL

iOS:
AVFoundation/VideoToolbox -> CVPixelBuffer -> Metal
```

## Diagnostics Rule

No unsupported FX may fail silently.

If an effect reaches `RenderGraph` but has no platform pass, the app must report:

```text
unsupported-fx-pass
clipId
effectName
requested params
platform backend
preview/export impact
```

The user and agent must know whether the project contains:

```text
understood + rendered
understood + not rendered
unknown + preserved
blocked
```

## Golden-Frame Requirements

Every platform must support golden-frame comparisons for:

```text
geometry
timing
opacity
rotation
scale
text
shape
media frame selection
border/shadow/mask
each FX pass
preview/export parity
```

The same project and same frame index must produce the same visual meaning across platforms, within a documented pixel tolerance.

## Migration Order For A New Platform

Use this order. Do not skip ahead.

```text
1. Read Open Folder contract.
2. Link UnitedGate.
3. Validate composition/timeline/assets.
4. Build/load HyperFrame IR.
5. Evaluate FrameDescriptor(frameIndex).
6. Compile RenderGraph.
7. Compile FX PassGraph.
8. Implement platform source providers.
9. Implement platform renderer backend.
10. Implement preview/scrub/play from the same frame path.
11. Implement export from the same frame path.
12. Add BMF only after FinalFrameStream + AudioPCM exist.
13. Add golden-frame tests.
14. Add diagnostics for every unsupported feature.
```

## Current macOS Reality Check

Current macOS work has reached:

```text
Open Folder
UnitedGate
HyperFrame IR bridge
FrameDescriptor
RenderGraph
basic preview/export rendering
```

The missing professional layer is:

```text
FX Registry
FX Compiler
FX PassGraph
Metal FX Runtime
preview/export parity through the same FX passes
```

Until that is built, FX such as `motionTile`, `motionBlur`, `gaussianBlur`, and advanced `glow` may be preserved and visible in descriptors but should not be considered rendered.

## Absolute Rule

When in doubt, do not patch the platform. Move the meaning up into the shared brain and make the platform renderer consume the formal pass graph.

```text
One gate.
One project truth.
One HyperFrame IR.
One FrameDescriptor.
One RenderGraph.
One FX PassGraph.
Platform-specific renderers only after that.
```
