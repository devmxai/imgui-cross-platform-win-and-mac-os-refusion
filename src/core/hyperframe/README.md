# HyperFrame Core

This folder owns engine semantics.

## Allowed

```text
project contracts
timeline contracts
animation evaluation
FX registry, aliases, schemas, normalization, and planners
FrameDescriptor
RenderGraph
FXPassGraph
diagnostics
render/export contracts
golden-frame expectations
```

## Forbidden

```text
DOM
window/document
Canvas/WebGL/WebGPU/WebCodecs
Metal/AVFoundation/AppKit/UIKit
Android SDK/MediaCodec
BMF WASM internals
app UI
platform adapter imports
```

## Subfolders

```text
contracts: shared public contracts
project: Open Folder project model
timeline: timeline and layer semantics
animation: keyframes and animation evaluation
fx: FX registry, normalization, planning, and pass graph
render-plan: RenderGraph and render planning
frame: FrameDescriptor and frame contracts
diagnostics: Core-generated diagnostics
```
