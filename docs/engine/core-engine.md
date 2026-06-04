# Core Engine Contract

HyperFrame Core owns meaning. Every platform must execute the contracts produced by Core instead of inventing separate behavior.

## Core Owns

```text
Open Folder project contract
timeline and layer semantics
asset identity contract
animation/keyframe evaluation
FX names, aliases, schemas, defaults, and normalization
Core FX manifest: src/core/hyperframe/fx/fxRegistry.manifest.json
FrameDescriptor
RenderGraph
FXPassGraph
sample planning
capability-independent diagnostics
golden-frame expectations
render/export contracts
```

## Core Must Not Import

```text
DOM or browser APIs
Canvas/WebGL/WebGPU/WebCodecs APIs
Metal/AVFoundation/AppKit/UIKit
Android SDK or MediaCodec
BMF WASM runtime internals
app UI components
platform adapter files
legacy project type files
```

## Change Rule

If the behavior changes what an FX, animation, timeline field, render pass, frame, or export means, it starts in Core.

If the behavior only changes how one platform executes an already-defined contract, it belongs in that platform adapter.

## Current Legacy Location

Most current Core candidates still live under:

```text
src/engine/hyperframe
```

They must move gradually to:

```text
src/core/hyperframe
```

Only move files after `npm run architecture:verify` exists and passes.

`src/engine/export`, `src/engine/assets`, `src/engine/rendering`, and `src/engine/remake` are not Core. They are legacy Web compatibility facades after the finalization slice.

## Current Hardening Baseline

```text
src/core/hyperframe/contracts/projectTypes.ts
src/core/hyperframe/fx/fxRegistry.manifest.json
scripts/architecture/verify-fx-semantics-parity.mjs
```

Core must not import `src/project/types`. App/project objects may be structurally compatible with Core contracts, but Core owns its own contract types.

Any platform mirror of FX names, aliases, schema parameters, or support lists must be checked against `fxRegistry.manifest.json`.
