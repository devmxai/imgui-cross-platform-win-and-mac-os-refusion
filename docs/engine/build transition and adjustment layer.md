# Build Transition And Adjustment Layer

Status: planning only
Scope: Core engine, Open Folder contract, agent authoring, macOS SwiftUI wiring, Web parity
Implementation state: not started

## 1. Purpose

Build first-class `adjustment` and `transition` timeline layers that both manual UI and external agents can author through the same Open Folder workspace contract.

The goal is not to add a UI-only transition effect. The goal is to make adjustment and transition layers part of the shared Core render model:

```text
Manual UI / Agent folder edit
-> Open Folder workspace files
-> UnitedGate validation
-> HyperFrame IR
-> FrameDescriptor
-> RenderGraph
-> FXPassGraph
-> platform adapter
-> FinalFrameSurface / FinalFrameStream
```

The agent must be able to read a transition layer from `timeline.json`, understand its exact time range, target scope, and intended role, then write professional animation and FX intent onto that layer without guessing where the transition belongs.

## 2. Non-Negotiable Rules

1. `composition.json`, `timeline.json`, and `assets/assets.json` remain the source of truth.
2. `native-scenes/main/*` is a compatibility surface and must not define native visual truth.
3. Manual UI edits and agent edits must converge through the same project contract.
4. New layer meaning belongs in Core, not in SwiftUI, Web iframe code, BMF, or platform adapters.
5. Agents may write creative intent, animation, and FX onto transition/adjustment layers, but Core must validate and execute the meaning.
6. Transition layers must not destructively modify source clips.
7. Invalid transition placement must produce precise diagnostics instead of rendering an ambiguous result.
8. Preview and export must use the same evaluated FrameDescriptor/RenderGraph/FXPassGraph semantics.

## 3. Current Open Folder Workspace

A project folder may contain:

```text
project.json
composition.json
timeline.json
assets/assets.json
assets/originals/
assets/brand-library.json
ASSET_RESOLVER.md
AGENT_INSTRUCTIONS.md
font-catalog.json
native-scenes/main/index.html
native-scenes/main/scene.css
native-scenes/main/scene.js
renders/
proofs/
```

The current agent-reliable source files are:

```text
composition.json
timeline.json
assets/assets.json
assets/originals/
```

Agents discover media through `assets/assets.json`.

Each asset has stable identity and metadata:

```json
{
  "id": "asset_x",
  "type": "video",
  "name": "clip.mp4",
  "fileName": "asset_x_clip.mp4",
  "path": "assets/originals/asset_x_clip.mp4",
  "width": 1920,
  "height": 1080,
  "duration": 5.0,
  "fps": 30
}
```

Agents discover editable layers through `timeline.json`.

Each layer is currently represented as a clip:

```json
{
  "id": "clip_x",
  "name": "Video 1",
  "type": "video",
  "assetId": "asset_x",
  "trackId": "track_clip_x",
  "start": 0,
  "duration": 3,
  "trimIn": 0,
  "style": {}
}
```

Timing rules:

```text
clip.start = absolute timeline seconds
clip.duration = seconds
clip end = clip.start + clip.duration
motion/style keyframes = clip-local seconds
localTime = timelineTime - clip.start
mediaTime = clip.trimIn + localTime
```

## 4. Current Gaps

The current model is directionally correct, but not complete enough for professional transition/adjustment authoring.

Known gaps:

1. `clip.type` does not include `adjustment` or `transition`.
2. `track.kind` does not include `adjustment` or `transition`.
3. HyperFrame IR layer kinds do not include `adjustment` or `transition`.
4. Effects currently normalize as `scope: "node"` even though the type system hints at adjustment and transition scopes.
5. `shaderTransition` is currently a per-layer effect intent, not a first-class A/B transition layer.
6. Web and macOS workspace defaults are not fully identical.
7. Web live reload signatures do not observe all project file changes as strongly as macOS `UnitedGate.fullSignature`.
8. macOS timeline UI displays clip timing in seconds, but is not yet a full professional track-lane editor.
9. Track hidden/mute and z-order semantics need tightening before layer-scoped adjustment behavior can be trusted.
10. OpenTimelineIO is currently a vendor/reference model, not the active timeline interchange path.

## 5. Authoring Personas

### Manual UI

The user creates or edits layers through the app UI:

```text
Add Adjustment Layer
Add Transition Layer
Move layer
Resize layer
Set target scope
Pick transition style
Edit FX parameters
```

Manual UI must write the same `timeline.json` contract that an agent writes.

### External Agent

The agent edits the Open Folder workspace directly:

```text
Read composition.json
Read assets/assets.json
Read timeline.json
Find transition/adjustment layers
Write animation and FX intent onto the correct layer
Preserve source clips unless explicitly instructed
```

The agent must not guess transition placement when a transition layer exists. It must use the transition layer's `start`, `duration`, and scope.

### Core Engine

Core validates, normalizes, and resolves the layer into renderable contracts:

```text
timeline clip
-> IR layer
-> frame descriptor layer/pass
-> render graph node/pass
-> FX pass graph
```

### Platform Adapters

Platform adapters execute only the compiled plan. They must not invent layer meaning, transition semantics, effect names, parameter defaults, or fallback behavior.

## 6. Canonical Schema Proposal

Add first-class layer types:

```ts
WorkspaceTimelineTrack.kind += "adjustment" | "transition"
WorkspaceTimelineClip.type += "adjustment" | "transition"
```

Keep authoring in seconds. Core derives exact frame ranges.

Add derived timing in IR/FrameDescriptor:

```ts
timing: {
  start: number;
  duration: number;
  end: number;
  trimIn: number;
  frameRange: {
    startFrame: number;
    endFrame: number;
    durationFrames: number;
  };
}
```

Frame range policy:

```text
range is half-open: [startFrame, endFrame)
startFrame = floor(start * fps)
endFrame = max(startFrame + 1, floor((start + duration) * fps))
```

The exact rounding policy must be centralized and reused by Core, macOS UI, Web UI, preview, scrub, and export.

## 7. Adjustment Layer Semantics

An adjustment layer is a timeline layer that applies effects over a time range to a resolved target scope.

Example:

```json
{
  "id": "adjust_001",
  "name": "Warm grade",
  "type": "adjustment",
  "trackId": "track_adjust_001",
  "start": 2.5,
  "duration": 2.0,
  "trimIn": 0,
  "adjustment": {
    "targetScope": {
      "mode": "below"
    },
    "effects": {
      "colorCorrection": {
        "enabled": true,
        "temperature": 0.15,
        "contrast": 1.08
      }
    }
  },
  "style": {
    "x": 0,
    "y": 0,
    "width": 1080,
    "height": 1920,
    "anchorX": 0.5,
    "anchorY": 0.5,
    "opacity": 1,
    "rotation": 0,
    "scaleX": 1,
    "scaleY": 1,
    "effects": {}
  }
}
```

Allowed target scopes:

```text
below
composition
tracks
clips
```

Semantics:

1. Active only over `[start, start + duration)`.
2. Does not represent source media.
3. Does not draw as a normal visual layer.
4. Resolves target layer IDs in Core.
5. Emits `scope: "adjustment"` effects.
6. Runs after target source layers are resolved/composited according to the selected scope.
7. Unsupported adjustment effects produce diagnostics.

Initial supported adjustment target:

```text
mode: "below"
```

Initial supported adjustment effect:

```text
colorCorrection
```

Later effects:

```text
gaussianBlur
glow
chromaticSplit
LUT
curves
vignette
```

## 8. Transition Layer Semantics

A transition layer is a timeline layer placed by the designer over a precise transition range, usually around the meeting point between outgoing clip A and incoming clip B.

Example:

```json
{
  "id": "transition_001",
  "name": "Camera zoom whip",
  "type": "transition",
  "trackId": "track_transition_001",
  "start": 2.5,
  "duration": 2.0,
  "trimIn": 0,
  "transition": {
    "kind": "cameraZoom",
    "targetScope": {
      "mode": "tracks",
      "trackIds": ["track_video_main"]
    },
    "params": {
      "scale": 1.2,
      "shake": 0.25,
      "rotation": 4,
      "motionBlur": true,
      "motionTile": true
    }
  },
  "style": {
    "x": 0,
    "y": 0,
    "width": 1080,
    "height": 1920,
    "anchorX": 0.5,
    "anchorY": 0.5,
    "opacity": 1,
    "rotation": 0,
    "scaleX": 1,
    "scaleY": 1,
    "effects": {
      "motionBlur": {
        "enabled": true,
        "samples": "auto",
        "shutterAngle": 180
      },
      "motionTile": {
        "enabled": true,
        "mode": "mirror",
        "expansion": 1.15
      }
    }
  }
}
```

Resolution model:

```text
transition layer time range
-> resolve target scope
-> find outgoing clip A
-> find incoming clip B
-> compute progress = localTime / duration
-> sample outgoing and incoming surfaces
-> apply transition animation and FX
-> output transition-composited frame
```

Rules:

1. The transition layer does not guess from visual overlap alone.
2. It resolves A/B candidates from timeline timing and target scope.
3. It can optionally store explicit `fromClipId` and `toClipId`.
4. If explicit IDs are absent, Core may infer A/B only when exactly one valid pair exists.
5. If no valid pair exists, Core blocks with a diagnostic.
6. If multiple valid pairs exist and the scope is ambiguous, Core blocks with a diagnostic.
7. Transition duration is the layer duration.
8. Transition progress is deterministic and frame-indexed.
9. Transition must not destructively edit clip A or clip B.
10. Transition is movable/resizable like a timeline layer.

Initial transition kinds:

```text
crossfade
cameraZoom
zoomBlur
push
wipe
motionTileZoom
whipPan
```

Initial implementation should start with:

```text
crossfade
```

Then add:

```text
cameraZoom
motionTileZoom
whipPan
zoomBlur
```

## 9. Agent Skill Contract

The generated agent instructions and local skills must explain transition/adjustment authoring.

### Adjustment Skill Rules

When an agent sees `clip.type: "adjustment"`:

1. Treat it as a time-ranged effect layer.
2. Preserve `id`, `trackId`, `start`, `duration`, and `targetScope` unless the user asks to retime or retarget it.
3. Write color, blur, glow, LUT, or other adjustment effects onto `adjustment.effects` or the canonical Core-approved path.
4. Do not add duplicated media to fake adjustment results.
5. Do not hard-code adjustment visuals in `scene.js`.

### Transition Skill Rules

When an agent sees `clip.type: "transition"`:

1. Treat it as the official transition work area.
2. Use the layer's `start` and `duration`.
3. Do not invent another transition time range.
4. Resolve or respect `targetScope`, `fromClipId`, and `toClipId`.
5. Write professional animation and FX intent onto the transition layer.
6. Do not destructively alter source video clips unless the user explicitly asks.
7. Prefer transform animation and semantic FX over duplicated stacked media.
8. Keep keyframes clip-local.

Allowed transition animation intent:

```text
scale
rotation
position
anchor
skew
opacity
camera zoom in/out
camera shake
push
whip pan
```

Allowed transition FX intent:

```text
motionBlur
motionTile
gaussianBlur
radialBlur
zoomBlur
spiralEchoBlur
glow
colorCorrection
chromaticSplit
```

Example agent behavior:

```text
User: Make this transition a professional zoom-out with shake and motion blur.

Agent:
1. Reads timeline.json.
2. Finds selected/nearest transition layer.
3. Preserves start/duration.
4. Writes transition.kind and params.
5. Adds style keyframes/effects to the transition layer only.
6. Leaves source clips unchanged.
```

## 10. UnitedGate Validation

UnitedGate must validate both manual UI edits and external agent edits.

Required validation:

```text
valid-adjustment-layer-type
valid-transition-layer-type
valid-layer-time-range
valid-target-scope
valid-transition-duration
valid-transition-a-b-resolution
unsupported-adjustment-effect
unsupported-transition-kind
unsupported-transition-effect
ambiguous-transition-targets
missing-transition-from-clip
missing-transition-to-clip
```

Severity policy:

```text
blocked:
  invalid time range
  missing target scope
  missing required A/B pair
  unsupported transition kind requested for export
  unknown first-class layer payload shape

warning:
  unsupported preview-only quality mode
  inferred A/B pair instead of explicit IDs
  effect preserved but not rendered by current adapter

info:
  transition resolved successfully
  adjustment target count
```

## 11. Core Changes

Required Core updates:

1. Project schema:
   - Add `adjustment` and `transition` clip/track kinds.
   - Add role-specific payloads.
   - Add schema versioning or feature gates.

2. Transaction gate:
   - Validate timing, scope, and supported payload shape.
   - Reject ambiguous transition placement.

3. Authoring model:
   - Expose adjustment and transition clips to agents and UI.
   - Preserve stable IDs.

4. HyperFrame IR:
   - Add layer kinds.
   - Add derived frame ranges.
   - Add adjustment target resolution.
   - Add transition A/B resolution.

5. FrameDescriptor:
   - Include active adjustment and transition descriptors per frame.
   - Include transition progress.
   - Include resolved from/to layer IDs or surfaces.

6. RenderGraph:
   - Represent adjustment as a scoped pass, not a normal media node.
   - Represent transition as a multi-input pass.

7. FXPassGraph:
   - Support `scope: "adjustment"`.
   - Support `scope: "transition"`.
   - Support grouped and multi-input passes.
   - Order passes according to the FX standard:

```text
sourceResolve
-> edge-sampler FX
-> pre-transform spatial FX
-> temporal-transform FX
-> post-transform spatial FX
-> composite / mask / border / shadow
-> adjustment / group / transition FX
-> final composite
```

8. Capability diagnostics:
   - Platform adapters declare which adjustment and transition passes they execute.
   - Unsupported passes are reported and blocked when required.

## 12. macOS SwiftUI Requirements

SwiftUI must not define new semantics. It should expose and edit the Core contract.

Required UI:

```text
Add Adjustment Layer
Add Transition Layer
Add Transition At Cut
Move layer
Resize layer
Set target scope
Show diagnostics
Inspector for adjustment params
Inspector for transition params
```

Timeline fixes needed before professional editing:

1. Use real track lanes, not one row per clip.
2. Show multi-clip tracks correctly.
3. Show empty tracks.
4. Show hidden/mute/lock states.
5. Show adjustment and transition tracks with distinct visual styling.
6. Show exact start/end/duration.
7. Snap transition layers to cut points.
8. Use the same frame rounding policy as Core.
9. Ensure `timeline.fps` and `composition.fps` cannot diverge silently.
10. Respect track ordering and z-order consistently with Core.

Canvas requirements:

1. Keep `NativeRenderEngine` as render truth.
2. Add zoom/pan.
3. Add selection outlines.
4. Add transform handles.
5. Add guides/safe area.
6. Add diagnostics overlay.
7. Do not use SwiftUI overlays as render truth.

## 13. Web Requirements

Web must align with the same contract.

Required Web fixes:

1. Add schema support for adjustment and transition layers.
2. Update generated `AGENT_INSTRUCTIONS.md`.
3. Update `timeline.agentContract`.
4. Expand live reload signature to include all source-of-truth files and relevant asset changes.
5. Avoid platform-local transition interpretation inside the iframe compositor.
6. Treat raw timeline compositor as transitional until it consumes Core FrameDescriptor semantics.
7. Add diagnostics when agent-written layers are preserved but not rendered.

## 14. Open Folder Contract Updates

The plan must update generated workspace documents:

```text
README.md
AGENT_INSTRUCTIONS.md
ASSET_RESOLVER.md
timeline.agentContract
```

Add explicit agent instructions:

```text
Adjustment layers:
  Read by clip.type === "adjustment".
  Preserve timing unless requested.
  Write supported effects onto adjustment payload.

Transition layers:
  Read by clip.type === "transition".
  Treat the layer as the official transition range.
  Use start/duration as the only transition timing.
  Resolve A/B via provided IDs or target scope.
  Write transform animation and FX intent onto the transition layer.
  Do not edit source clips destructively.
```

## 15. Rendering And Export Boundaries

BMF, WebCodecs, and native encoders must not interpret timeline layers directly.

Correct boundary:

```text
timeline layer/effect semantics
-> Core
-> final frame stream
-> encoder
```

Incorrect boundary:

```text
encoder reads transition layer
encoder decides FX
platform UI decides layer meaning
scene.js decides native transition semantics
```

## 16. Initial Implementation Slices

### Slice 0 - Planning And Contract

Deliverables:

```text
plan document
agent skill text
schema examples
diagnostic list
acceptance fixtures list
```

No runtime changes.

### Slice 1 - Core Schema And Validation

Deliverables:

```text
project types updated
UnitedGate / transaction gate validation
agentContract updated
fixtures for valid/invalid layers
```

No renderer execution yet.

### Slice 2 - IR And FrameDescriptor

Deliverables:

```text
adjustment layer appears in IR
transition layer appears in IR
frameRange derived
transition progress derived
target scope resolved
A/B resolution diagnostics
```

### Slice 3 - RenderGraph And FXPassGraph

Deliverables:

```text
adjustment pass model
transition pass model
multi-input pass support
capability diagnostics
```

### Slice 4 - Minimal Adapter Execution

Deliverables:

```text
adjustment colorCorrection
transition crossfade
preview/export parity fixtures
```

### Slice 5 - Professional Transition Set

Deliverables:

```text
cameraZoom
motionTileZoom
whipPan
zoomBlur
shake
motionBlur
```

### Slice 6 - macOS UI

Deliverables:

```text
timeline lane support
add adjustment layer
add transition layer
transition-at-cut command
inspector
diagnostics
canvas tooling
```

### Slice 7 - Web Parity

Deliverables:

```text
web contract support
agent docs regenerated
live reload fixed
preview diagnostics
```

## 17. Acceptance Gates

The feature is not complete until:

```text
agent can identify adjustment layer by type
agent can identify transition layer by type
manual UI and agent edits produce the same timeline contract
invalid adjustment scope blocks
invalid transition placement blocks
transition layer resolves clip A and clip B
transition layer can be moved/resized without altering source clips
crossfade renders exact midpoint blend
adjustment color correction affects only target scope
preview and export use the same FrameDescriptor semantics
macOS and Web preserve the same project contract
golden frames pass
architecture verification passes
```

## 18. Open Questions Before Implementation

1. Should transition layers always store explicit `fromClipId` and `toClipId`, or may Core infer when unambiguous?
2. Should transition target scope default to `below`, `tracks`, or `selected pair`?
3. Should adjustment effects live under `clip.adjustment.effects`, `clip.style.effects`, or both with a canonical migration rule?
4. Should transition animation live under `clip.transition.animation`, `clip.style.keyframes`, or both with a canonical migration rule?
5. How should timeline UI display transition layers that overlap multiple tracks?
6. Should Web and macOS workspace creation be unified before or during Slice 1?
7. Which first adapter should execute crossfade: macOS Metal or Web Core preview?

## 19. Final Verdict

The adjustment/transition layer direction is professional and aligned with the Core-first architecture.

However, it must not be implemented as only a skill prompt or a UI convention. The skill is the agent-facing explanation. The Core contract is the guarantee.

Correct path:

```text
document and skill
-> schema and validation
-> IR / FrameDescriptor
-> RenderGraph / FXPassGraph
-> minimal renderer support
-> macOS UI
-> Web parity
-> professional transition catalog
```

Only after these layers exist can an external agent safely write professional transitions into Open Folder with full confidence that macOS, Web, export, and future platforms will understand the same meaning.
