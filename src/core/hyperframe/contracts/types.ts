import type {
  NativeSceneFiles,
  VisualLayerStyle,
  WorkspaceAsset,
  WorkspaceComposition,
  WorkspaceTimeline,
  WorkspaceTimelineClip,
  WorkspaceTimelineTrack,
} from "./projectTypes";

export type HyperFrameTransactionSource = "manual-ui" | "agent-command" | "open-folder" | "live-reload" | "preview-compose";

export type HyperFrameTransactionIntent = "preview" | "export" | "edit" | "inspect";

export type HyperFrameTransactionInput = {
  source: HyperFrameTransactionSource;
  intent: HyperFrameTransactionIntent;
  composition: WorkspaceComposition;
  assets: WorkspaceAsset[];
  timeline: WorkspaceTimeline;
  scene: NativeSceneFiles;
};

export type HyperFrameGateIssueSeverity = "warning" | "error";

export type HyperFrameGateIssue = {
  severity: HyperFrameGateIssueSeverity;
  code: string;
  message: string;
  clipId?: string;
  trackId?: string;
  assetId?: string;
};

export type HyperFrameTransactionGateResult = {
  accepted: boolean;
  revision: string;
  source: HyperFrameTransactionSource;
  intent: HyperFrameTransactionIntent;
  issues: HyperFrameGateIssue[];
};

export type HyperFrameAuthoringClip = {
  id: string;
  name: string;
  type: WorkspaceTimelineClip["type"];
  trackId: string;
  trackKind: WorkspaceTimelineTrack["kind"];
  start: number;
  duration: number;
  trimIn: number;
  assetId?: string;
  renderCompositor?: WorkspaceTimelineClip["render"] extends infer Render ? Render extends { compositor?: infer Compositor } ? Compositor : never : never;
  style: VisualLayerStyle;
  text: WorkspaceTimelineClip["text"];
  shape: WorkspaceTimelineClip["shape"];
  hidden: boolean;
  muted: boolean;
};

export type HyperFrameAuthoringModel = {
  version: 1;
  revision: string;
  composition: WorkspaceComposition;
  assets: WorkspaceAsset[];
  scene: NativeSceneFiles;
  clips: HyperFrameAuthoringClip[];
  issues: HyperFrameGateIssue[];
};

export type HyperFrameIRLayerKind = "background" | "video" | "image" | "shape" | "text" | "audio" | "native-scene";

export type HyperFrameIRLayer = {
  id: string;
  clipId: string;
  trackId: string;
  kind: HyperFrameIRLayerKind;
  zIndex: number;
  timing: {
    start: number;
    duration: number;
    end: number;
    trimIn: number;
  };
  asset?: {
    id: string;
    type: WorkspaceAsset["type"];
    path: string;
    runtimeUrl?: string;
    width?: number;
    height?: number;
    duration?: number;
    fps?: number;
  };
  style: VisualLayerStyle;
  text: WorkspaceTimelineClip["text"];
  shape: WorkspaceTimelineClip["shape"];
  muted: boolean;
};

export type HyperFramePixelGeometryContract = {
  version: 1;
  coordinateSpace: "composition-pixels";
  origin: "top-left";
  units: "px";
  rounding: "float-until-raster-boundary";
  anchorPolicy: "resolved-by-hyperframe-renderer";
  boundsPolicy: "render-before-encode";
  alpha: "premultiplied";
  colorSpace: "srgb";
  unsupportedGeometry: Array<"rounded-bounds" | "border" | "shadow" | "glow" | "non-axis-aligned-rasterization">;
};

export type HyperFrameFrameTimingContract = {
  version: 1;
  timeBase: "integer-frame-index";
  fps: number;
  frameDurationSeconds: number;
  clipRangePolicy: "half-open-start-inclusive-end-exclusive";
  seekPolicy: "frame-indexed-deterministic";
};

export type HyperFramePixelFrameContract = {
  version: 1;
  pixelGeometry: HyperFramePixelGeometryContract;
  frameTiming: HyperFrameFrameTimingContract;
};

export type HyperFrameIR = {
  version: 1;
  revision: string;
  composition: WorkspaceComposition;
  durationSeconds: number;
  fps: number;
  contracts: HyperFramePixelFrameContract;
  layers: HyperFrameIRLayer[];
  issues: HyperFrameGateIssue[];
};

export type HyperFrameRenderPassKind = "media-preload" | "decode" | "raster-cache" | "effects" | "composite" | "audio-mix" | "export";

export type HyperFrameEffectKind =
  | "gaussianBlur"
  | "transformMotionBlur"
  | "motionTrail"
  | "motionTile"
  | "radialBlur"
  | "zoomBlur"
  | "spiralEchoBlur"
  | "glowStreak"
  | "chromaticSplit"
  | "shaderTransition";

export type HyperFrameEffectInstance = {
  id: string;
  source: string;
  kind: HyperFrameEffectKind;
  enabled: boolean;
  params: Record<string, unknown>;
  quality: "auto" | "interactive" | "preview" | "export";
  scope: "node" | "group" | "adjustment" | "transition" | "composition";
};

export type HyperFrameRenderPass = {
  id: string;
  kind: HyperFrameRenderPassKind;
  layerIds: string[];
  reason: string;
};

export type HyperFramePreviewRendererJob = {
  version: 1;
  target: "preview";
  executionContract: "hyperframe-ir-frame-descriptor";
  surfaceContract: "deterministic-final-frame-surface";
  revision: string;
  composition: WorkspaceComposition;
  layerOrder: string[];
  mediaLayerIds: string[];
  cacheLayerIds: string[];
  effectLayerIds: string[];
  deterministicCanvas: true;
};

export type HyperFrameFrameDescriptorLayer = {
  id: string;
  clipId: string;
  trackId: string;
  kind: HyperFrameIRLayerKind;
  zIndex: number;
  localTime: number;
  mediaTime: number;
  timing: HyperFrameIRLayer["timing"];
  asset?: HyperFrameIRLayer["asset"];
  text: HyperFrameIRLayer["text"];
  shape: HyperFrameIRLayer["shape"];
  transform: {
    x: number;
    y: number;
    width: number;
    height: number;
    centerX: number;
    centerY: number;
    originX: number;
    originY: number;
    anchorX: number;
    anchorY: number;
    scaleX: number;
    scaleY: number;
    rotationDegrees: number;
    rotationRadians: number;
    skewXDegrees: number;
    skewYDegrees: number;
    skewXRadians: number;
    skewYRadians: number;
  };
  opacity: number;
  cornerRadius: {
    topLeft: number;
    topRight: number;
    bottomRight: number;
    bottomLeft: number;
  };
  crop: VisualLayerStyle["crop"];
  blendMode: VisualLayerStyle["blendMode"];
  filters: VisualLayerStyle["filters"];
  effects: VisualLayerStyle["effects"];
  normalizedEffects: HyperFrameEffectInstance[];
  motion: {
    velocityX: number;
    velocityY: number;
    speed: number;
    angularVelocityDegrees: number;
    scaleVelocityX: number;
    scaleVelocityY: number;
    skewVelocityX: number;
    skewVelocityY: number;
    opacityVelocity: number;
  };
  muted: boolean;
};

export type HyperFrameFrameDescriptor = {
  version: 1;
  revision: string;
  time: number;
  frameIndex: number;
  frameTime: number;
  frameDurationSeconds: number;
  fps: number;
  contracts: HyperFramePixelFrameContract;
  composition: WorkspaceComposition;
  activeLayerIds: string[];
  layers: HyperFrameFrameDescriptorLayer[];
};

export type HyperFrameFrameDescriptorPlan = {
  version: 1;
  evaluator: "hyperframe-ir-frame-descriptor";
  revision: string;
  deterministic: true;
  layerCount: number;
  contracts: HyperFramePixelFrameContract;
};

export type HyperFrameBmfExportNode = {
  id: string;
  module: "frame_stream" | "audio_pcm" | "encode";
  inputs: string[];
  layerIds: string[];
  options: Record<string, unknown>;
};

export type HyperFrameBmfLayerDescriptor = {
  id: string;
  clipId: string;
  trackId: string;
  kind: HyperFrameIRLayerKind;
  zIndex: number;
  timing: HyperFrameIRLayer["timing"];
  frameRange: {
    startFrame: number;
    endFrame: number;
    durationFrames: number;
  };
  asset?: HyperFrameIRLayer["asset"];
  style: VisualLayerStyle;
  muted: boolean;
};

export type HyperFrameBmfExportJob = {
  version: 1;
  target: "bmf";
  source: "hyperframe-final-frame-stream";
  executionRole: "encode-mux-only";
  visualAuthority: "hyperframe-ir-frame-descriptor-platform-renderer";
  revision: string;
  composition: WorkspaceComposition;
  durationSeconds: number;
  fps: number;
  contracts: HyperFramePixelFrameContract;
  layers: HyperFrameBmfLayerDescriptor[];
  nodes: HyperFrameBmfExportNode[];
  output: {
    container: "mp4";
    videoCodec: "h264";
    audioCodec: "aac";
    videoSource: "hyperframe-final-frame-stream";
    audioSource: "hyperframe-audio-pcm";
    audioPolicy?: "pcm" | "none";
  };
};

export type HyperFrameRuntimeAdapterStatus = "active" | "planned";

export type HyperFrameRuntimeAdapterRole = "preview" | "export";

export type HyperFrameRuntimeAdapter = {
  id: string;
  role: HyperFrameRuntimeAdapterRole;
  status: HyperFrameRuntimeAdapterStatus;
  consumes: "hyperframe-ir" | "pixel-frame-stream";
  produces: "deterministic-canvas" | "encoded-video";
  target: "preview-surface" | "export-encoding";
  sourcePackage?: string;
  notes: string[];
};

export type HyperFrameRuntimeAdapters = {
  preview: HyperFrameRuntimeAdapter;
  export: HyperFrameRuntimeAdapter;
  planned: HyperFrameRuntimeAdapter[];
};

export type HyperFrameAdapterResolution = {
  role: HyperFrameRuntimeAdapterRole;
  adapter: HyperFrameRuntimeAdapter;
  executable: boolean;
  revision: string;
  reason: string;
  blockingIssueCodes: string[];
};

export type HyperFrameMotionFxExecutionRequirement = "raster" | "shader" | "temporal" | "native-or-shader" | "unsupported";

export type HyperFrameMotionFxStatus = "active" | "planned" | "blocked";

export type HyperFrameMotionFxCapability = {
  kind: string;
  layerIds: string[];
  executionRequirement: HyperFrameMotionFxExecutionRequirement;
  status: HyperFrameMotionFxStatus;
  reason: string;
};

export type HyperFrameMotionFxCapabilityReport = {
  version: 1;
  activeEffectCount: number;
  effectLayerIds: string[];
  gpuRequiredLayerIds: string[];
  blockedLayerIds: string[];
  duplicateHeavyVideoAssetIds: string[];
  capabilities: HyperFrameMotionFxCapability[];
  messages: string[];
};

export type HyperFrameRenderPlanSummary = {
  version: 1;
  revision: string;
  source: HyperFrameTransactionSource;
  intent: HyperFrameTransactionIntent;
  accepted: boolean;
  issueCount: number;
  errorCount: number;
  warningCount: number;
  layerCount: number;
  mediaLayerCount: number;
  motionFxLayerCount: number;
  motionFxBlockedLayerCount: number;
  passCount: number;
  bmfNodeCount: number;
  previewAdapter: {
    id: HyperFrameRuntimeAdapter["id"];
    executable: boolean;
    reason: string;
  };
  exportAdapter: {
    id: HyperFrameRuntimeAdapter["id"];
    executable: boolean;
    reason: string;
  };
};

export type HyperFrameRenderPlan = {
  version: 1;
  revision: string;
  source: HyperFrameTransactionSource;
  intent: HyperFrameTransactionIntent;
  transactionGate: HyperFrameTransactionGateResult;
  previewRenderer: {
    target: "preview";
    executionContract: "hyperframe-ir-frame-descriptor";
    surfaceContract: "deterministic-final-frame-surface";
    deterministicCanvas: true;
  };
  previewJob: HyperFramePreviewRendererJob;
  frameDescriptor: HyperFrameFrameDescriptorPlan;
  exportPipeline: {
    target: "export";
    activeAdapter: string;
    source: "hyperframe-final-frame-stream";
    singleSourceIr: true;
    browserFrameStreamAdapter: string;
    browserFrameStreamExecutable: boolean;
  };
  bmfJob: HyperFrameBmfExportJob;
  runtimeAdapters: HyperFrameRuntimeAdapters;
  motionFx: HyperFrameMotionFxCapabilityReport;
  ir: HyperFrameIR;
  passes: HyperFrameRenderPass[];
  issues: HyperFrameGateIssue[];
};
