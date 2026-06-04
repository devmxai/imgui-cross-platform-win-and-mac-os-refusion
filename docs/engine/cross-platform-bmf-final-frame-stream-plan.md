# Cross-Platform BMF Final Frame Stream Plan

## Purpose

This document defines the professional export architecture for ReFUSION across web, Android, iOS, macOS, and Windows.

The first implementation target is the web platform. The final production path must be BMF-based on every platform, with one shared contract and platform-specific executor artifacts.

```text
Timeline / UI / Agent
-> Unified Transaction Gate
-> HyperFrame Authoring Model
-> HyperFrame IR
-> FrameDescriptor
-> Pixel-true HyperFrame Renderer
-> FinalFrameStream + AudioPCM
-> Platform BMF Executor
-> Encode / Mux / Output
```

## Core Decision

BMF is the production encode/mux executor. WebCodecs may exist as the browser hardware encoder when it consumes the same deterministic final-frame-stream contract.

BMF must not interpret timeline layers, design effects, shadows, rounded bounds, borders, keyframes, transitions, DOM layout, CSS, or audio timeline structure. HyperFrame owns all visual rendering and audio planning. BMF receives finished frames plus AudioPCM and performs encode/mux/output.

```text
Correct:
HyperFrame final frames + AudioPCM -> BMF encode/mux

Incorrect:
timeline layers/effects -> BMF compositor
timeline audio sources -> BMF audio mixer
```

### Web Hardware Encoder Constraint

The browser BMF WASM artifact is a verified final-frame-stream software encoder. It cannot access platform hardware encoders such as VideoToolbox, MediaCodec, or GPU video encode from inside the browser sandbox.

For high-resolution web exports, the professional web executor may therefore use WebCodecs as the hardware encode backend while preserving the same source-of-truth contract:

```text
HyperFrame final frames + AudioPCM
-> WebCodecs hardware encode/mux
-> MP4
```

BMF WASM remains the verified web software fallback and contract gate. BMF native remains the target production executor for Android, iOS, macOS, Windows, and any future desktop/server helper where BMF can access native encode resources.

## Core-First FX Rule

This export plan does not move FX into any encoder or one platform. Motion Blur, Motion Trail, Motion Tile, Glow, Transitions, and Radial/Spin/Zoom are defined and planned in HyperFrame Core, then executed by platform renderer adapters before final frames reach BMF or WebCodecs.

Correct FX/export ownership:

```text
HyperFrame Core FX plan
-> platform renderer adapter executes pixels
-> FinalFrameStream + AudioPCM
-> BMF/WebCodecs/native encoder
```

Incorrect ownership:

```text
BMF decides FX
WebCodecs decides FX
Web/macOS-only renderer patch decides FX
```

## Non-Negotiable Rules

1. Frame index is the only export time authority.
2. Composition pixels are the only export geometry authority.
3. HyperFrame IR and FrameDescriptor are the source of truth.
4. GPU implementations are execution details, not sources of truth.
5. BMF only consumes final frames and audio, then encodes and muxes.
6. No BMF artifact can be enabled without smoke and verification.
7. No platform may silently fall back to a lower-fidelity production path.
8. MediaRecorder, DOM raster, screenshots, and playback-clock exports are not production paths. WebCodecs may be the production web hardware encoder only when fed by the same deterministic HyperFrame FinalFrameStream contract.
9. Open Folder, timeline identity, asset identity, and agent workspace writing contracts must not be changed by export work.
10. Live Scrub and protected preview handoff paths must not be touched by this plan.
11. BMF must never be used for Play, Scrub, Live Preview, or preview rendering.
12. Motion Blur, Motion Tile, Glow, and Transitions belong to HyperFrame Core FX planning and platform renderer adapter execution, not BMF.

## Shared Cross-Platform Contracts

Every platform must implement the same contracts.

### HyperFrame IR Contract

The IR must describe the scene in platform-neutral terms:

```text
composition
layers
assets
timing
geometry
style intent
audio intent
render issues
```

The IR may contain design intent, but production export does not hand this intent to BMF for interpretation. The HyperFrame renderer resolves it into final pixels first.

### Renderer Authority Contract

The single source of truth is:

```text
HyperFrame IR
-> FrameDescriptor(frameIndex)
-> Platform Renderer
-> FinalFrameStream
```

BMF is downstream of this chain. It is not allowed to become the visual truth, an interactive loop participant, or a fallback compositor.

### Frame Timing Contract

Every exported frame is addressed by integer frame index:

```text
frameIndex: 0..frameCount-1
timeSeconds = frameIndex / fps
timestampUs = round(frameIndex * 1_000_000 / fps)
durationUs = round(1_000_000 / fps)
```

Rules:

- No requestAnimationFrame authority.
- No HTMLMediaElement playback clock authority.
- No wall-clock export time authority.
- No approximate duration loops.
- Clip ranges use half-open intervals: `[startFrame, endFrame)`.

### Pixel Geometry Contract

Every exported pixel is rendered in composition-space pixels:

```text
x
y
width
height
anchor
scale
rotation
crop
fit
border
radius
shadow
glow
text metrics
```

Rules:

- Geometry is never inferred from viewport size.
- Geometry is never inferred from CSS layout.
- Zoom level does not affect export pixels.
- Device pixel ratio does not affect composition coordinates.
- Subpixel math may exist internally, but raster boundary policy must be deterministic.

### FinalFrameStream Contract

The final frame stream is the visual input to BMF:

```ts
type FinalFrameStream = {
  width: number;
  height: number;
  fps: number;
  frameCount: number;
  durationSeconds: number;
  pixelFormat: "rgba" | "bgra" | "yuv420p";
  alpha: "premultiplied" | "opaque";
  colorSpace: "srgb" | "display-p3";
  seekFrame(frameIndex: number): Promise<{
    frameIndex: number;
    timeSeconds: number;
    timestampUs: number;
    durationUs: number;
    bytes: Uint8Array;
  }>;
};
```

Initial web implementation should use RGBA from HyperFrame and allow the BMF executor to convert to encoder-native YUV when needed. Later platform-native renderers may provide YUV directly if it is proven bit-exact against the contract.

### AudioPCM Contract

Audio must be explicit and verified. Do not hard-code a sample rate without a documented policy.

```ts
type AudioPcmPlan = {
  sampleRate: 44100 | 48000 | number;
  channels: 1 | 2;
  channelLayout: "mono" | "stereo";
  sampleFormat: "f32-planar" | "s16-interleaved";
  durationSeconds: number;
  frameCount: number;
  timestampUs: number;
  data: Float32Array[] | Int16Array;
};
```

Audio rules:

- Preserve the source sample rate only when the full path can encode/mux it safely.
- Normalize to 48000 Hz only through a verified high-quality resampler.
- Never use 4800 Hz for production audio.
- No `audioPcm` capability may be enabled until noise, silence, sync, and sample-rate smoke tests pass.
- Mono-to-stereo conversion must be explicit.
- Clipping must be detected and limited or blocked.
- Silence must remain digital silence.
- Sine wave tests must prove no noise is introduced.

### ExportProfile Contract

```ts
type ExportProfile = {
  container: "mp4";
  videoCodec: "h264";
  audioCodec: "aac";
  width: number;
  height: number;
  fps: number;
  bitrate: number;
  keyframeIntervalFrames: number;
  colorSpace: "srgb";
  pixelFormat: "yuv420p";
  audioSampleRatePolicy: "preserve-when-safe" | "resample-48000";
};
```

The first production target is MP4/H264/AAC. Other containers/codecs can be added only through explicit profile and smoke coverage.

## Platform Architecture

The shared contracts are identical across platforms. The executor artifact is platform-specific.

```text
Web     -> BMF WASM final-frame-stream executor
Android -> BMF native/NDK executor
iOS     -> BMF native framework executor
macOS   -> BMF desktop/native executor
Windows -> BMF desktop/native executor
```

Each platform can use its own GPU stack to render HyperFrame frames:

```text
Web     -> Canvas/WebGL/WebGPU
Android -> GLES/Vulkan
iOS     -> Metal
macOS   -> Metal
Windows -> DirectX/Vulkan
```

The GPU backend must produce the same final frame for the same `frameIndex` and `FrameDescriptor`.

## Phase 1 - Web BMF WASM

Web is the first platform to implement the production final-frame-stream path. BMF WASM is the verified software executor; WebCodecs may be selected for high-resolution browser exports when hardware encode speed is required.

### Target Web Path

```text
HyperFrame Renderer
-> FinalFrameStream RGBA/YUV
-> AudioPCM
-> BMF WASM Executor or WebCodecs hardware encoder
-> H264/AAC
-> MP4 mux
-> streamed output
```

### Web Executor API

The WASM artifact must expose a streaming encoder API, not a file-input transcode API.

```ts
type BmfWebExecutor = {
  verify(manifest: BmfManifest): VerifyResult;
  createEncoder(profile: ExportProfile): EncoderHandle;
  pushVideoFrame(handle: EncoderHandle, frame: FinalFrame): void;
  pushAudioPcm(handle: EncoderHandle, audio: AudioPcmChunk): void;
  finalize(handle: EncoderHandle): Uint8Array | ReadableStream<Uint8Array>;
  destroy(handle: EncoderHandle): void;
};
```

The old bridge shape is prohibited:

```text
job/input video path -> decoder -> filter -> encoder
```

### Web Implementation Steps

1. Replace the current `vendor/bmf/refusion_bmf_executor.cpp` bridge with a final-frame-stream encoder bridge.
2. Build WASM exports for create/push/finalize/destroy.
3. Update `public/bmf/refusion-bmf-loader.js` to call the new WASM API.
4. Update `scripts/smoke-bmf-wasm-artifacts.mjs` to push deterministic frames and AudioPCM.
5. Update `scripts/verify-bmf-wasm-artifacts.mjs` to require `finalFrameStream=true` and `audioPcm=true`.
6. Update `scripts/enable-bmf-wasm-artifacts.mjs` so manifest enablement is impossible without passing smoke.
7. Switch web production executor selection to `bmf-wasm-export` when manifest is verified.
8. Keep WebCodecs diagnostic-only until it can be removed or hidden from production UI.

### Web Smoke Tests

Required before enabling the BMF web manifest:

```text
video-only deterministic frames
audio-only AAC mux
video + audio mux
exact width
exact height
exact frame count
exact fps
exact duration
H264 codec
AAC codec
MP4 container
non-empty output
repeatability across two runs
```

### Web Audio Smoke Tests

```text
digital silence remains silent
440Hz sine wave has no added noise
44100 Hz source policy works
48000 Hz source policy works
mono to stereo is explicit
no clipping above 0 dBFS
audio duration matches video duration
audio/video sync is within tolerance
```

### Web Definition Of Done

Web is complete only when:

```text
BMF WASM final-frame-stream artifact builds.
BMF smoke passes.
BMF verify passes.
BMF manifest is enabled.
Export UI shows Executor: bmf-wasm-export.
Export UI shows BMF artifact: ready.
Export path is hyperframe-bmf-wasm-mp4.
WebCodecs is not the production executor.
MP4 output passes ffprobe.
Frame count is exact.
FPS is exact.
Resolution is exact.
Audio is clean.
Audio/video sync is verified.
Large exports stream output.
```

## Phase 2 - Android

Android must reuse the same contracts and implement a native BMF executor.

```text
HyperFrame IR
-> Android renderer frame stream
-> AudioPCM
-> BMF native/NDK executor
-> MediaCodec/BMF encode
-> MP4 mux
```

Android may use GLES, Vulkan, Surface, ImageReader, HardwareBuffer, MediaCodec, or native BMF internals, but the contract does not change.

Android is complete only when it passes the same frame, pixel, audio, and mux verification suite as web.

## Phase 3 - iOS

iOS must reuse the same contracts and implement a native framework executor.

```text
HyperFrame IR
-> Metal/CoreVideo final frame stream
-> AudioPCM
-> BMF iOS framework executor
-> H264/AAC encode
-> MP4 mux
```

iOS may use Metal, CoreVideo, AVFoundation, or BMF native internals, but the contract does not change.

## Phase 4 - macOS

macOS must reuse the same contracts and implement a Metal renderer plus desktop/native BMF encode/mux executor.

```text
HyperFrame IR
-> FrameDescriptor
-> Metal renderer
-> CVPixelBuffer / IOSurface FinalFrameStream
-> AudioPCM
-> BMF desktop executor
-> H264/AAC encode
-> MP4 mux
```

macOS preview, play, scrub, and live preview use the Metal renderer directly. AVFoundation/VideoToolbox provide decoded media frames for low-latency preview and hardware accelerated encode/decode where appropriate. CoreImage may be used for suitable filter passes, but it is not the compositor. BMF starts only after final frames and AudioPCM exist.

Motion Blur, Motion Tile, Glow, and Transitions are HyperFrame Core FX plans executed by the Metal adapter:

- `motionTile` is sampler/wrap behavior, not duplicated layers.
- `motionBlur` is temporal transform accumulation, not opacity echo copies.
- preview may reduce samples for latency, but the visual meaning must remain the same.

## Phase 5 - Windows

Windows must reuse the same contracts and implement a desktop/native executor.

```text
HyperFrame IR
-> DirectX/Vulkan/native final frame stream
-> AudioPCM
-> BMF desktop executor
-> H264/AAC encode
-> MP4 mux
```

## Cross-Platform Verification Matrix

Every platform must pass the same tests.

### Frame Tests

```text
frame 0 exact
middle frame exact
last frame exact
frame count exact
fps exact
duration exact
repeatability across two exports
```

### Pixel Tests

```text
solid rectangle
1px border
inside border
center border
outside border
rounded rectangle
per-corner radius
shadow offset
shadow blur
opacity
rotation
scale
crop
fit cover
fit contain
text raster
image raster
video frame placement
track order
```

### Audio Tests

```text
silence
440Hz sine
44100 Hz
48000 Hz
mono
stereo
volume
mute
fade in
fade out
no clipping
duration match
sync match
```

### Container Tests

```text
mp4 container
h264 video
aac audio
resolution metadata
fps metadata
duration metadata
seekable output
non-empty output
streaming output when supported
```

## Capability And Manifest Rules

Capabilities are truth claims. They must be proven.

```ts
type BmfCapabilities = {
  finalFrameStream: boolean;
  audioPcm: boolean;
  streamingOutput: boolean;
  mp4: boolean;
  h264: boolean;
  aac: boolean;
  colorSpace: "srgb"[];
  pixelFormats: ("rgba" | "yuv420p")[];
  sampleRates: number[];
};
```

Rules:

- `enabled=true` requires smoke pass.
- `finalFrameStream=true` requires video frame smoke.
- `audioPcm=true` requires audio noise/sync smoke.
- `streamingOutput=true` requires streamed output smoke.
- Claims not covered by smoke must remain false.

## Rollout Policy

Rollout is gated and reversible.

1. Build contract types and docs.
2. Build web BMF bridge behind disabled manifest.
3. Add smoke fixtures.
4. Pass smoke locally.
5. Enable manifest.
6. Switch web production executor to BMF.
7. Keep WebCodecs diagnostic-only.
8. Repeat the same contract for Android, iOS, macOS, and Windows.

Every step must be a focused checkpoint commit.

## Blockers That Must Stop Export

Production export must block if:

```text
FrameStream cannot produce exact frame count.
Export canvas size differs from composition size.
Renderer depends on viewport layout.
Renderer depends on playback clock.
Audio plan cannot prove clean PCM.
BMF manifest is unverified.
BMF executor does not declare finalFrameStream.
BMF executor does not declare audioPcm for audible timelines.
Smoke report is missing or stale.
Output probe fails.
```

## What This Plan Removes

The following paths must not return as production export:

```text
BMF layer/effect compositor
BMF input video transcode bridge
DOM screenshot export
MediaRecorder export
captureStream export
requestAnimationFrame export loops
CSS layout dependent export
silent WebCodecs production fallback
fake ready states
manifest enabled without smoke
```

## Final Target State

When web is complete, the export status should read:

```text
Executor: bmf-wasm-export
Frame stream: ready
BMF artifact: ready
Path: hyperframe-bmf-wasm-mp4
Output strategy: streaming-writer
```

When all platforms are complete, every platform will use the same HyperFrame contracts and its own BMF executor artifact.
