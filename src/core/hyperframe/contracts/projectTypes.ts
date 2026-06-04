export type HyperFrameCompositionPresetId = "youtube" | "story" | "square";

export type NativeSceneFiles = {
  indexHtml: string;
  css: string;
  js: string;
};

export type WorkspaceComposition = {
  preset: HyperFrameCompositionPresetId;
  width: number;
  height: number;
  fps: number;
  durationSeconds: number;
};

export type WorkspaceAssetType = "image" | "video" | "audio" | "unknown";

export type WorkspaceAsset = {
  id: string;
  type: WorkspaceAssetType;
  name: string;
  fileName: string;
  path: string;
  previewUrl?: string;
  size: number;
  width?: number;
  height?: number;
  duration?: number;
  fps?: number;
  metadata?: unknown;
  createdAt: string;
};

export type VisualLayerEffectQuality = "auto" | "preview" | "export";

export type VisualLayerMotionBlurEffect = {
  enabled?: boolean;
  algorithm?: "temporalTransform";
  strength?: number;
  samples?: number | "auto";
  shutter?: number;
  shutterAngle?: number;
  shutterPhase?: number;
  sampleCurve?: "linear" | "centerWeighted" | "filmic";
  blur?: number;
  opacity?: number;
  edgeMode?: "transparent" | "mirror";
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerMotionTileEffect = {
  enabled?: boolean;
  mode?: "mirror" | "repeat" | "clamp" | "linear";
  expansion?: number;
  outputWidth?: number;
  outputHeight?: number;
  mirrorEdges?: boolean;
  strength?: number;
  samples?: number | "auto";
  spacing?: number;
  opacity?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerGaussianBlurEffect = {
  enabled?: boolean;
  radius?: number;
  blur?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerRadialBlurEffect = {
  enabled?: boolean;
  center?: "layer" | "composition" | { x: number; y: number };
  angleSpread?: number;
  samples?: number | "auto";
  decay?: number;
  opacity?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerZoomBlurEffect = {
  enabled?: boolean;
  center?: "layer" | "composition" | { x: number; y: number };
  zoomSpread?: number;
  samples?: number | "auto";
  decay?: number;
  opacity?: number;
  chromaticFringe?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerSpiralEchoBlurEffect = {
  enabled?: boolean;
  center?: "layer" | "composition" | { x: number; y: number };
  angleSpread?: number;
  zoomSpread?: number;
  radialSpread?: number;
  samples?: number | "auto";
  decay?: number;
  shutter?: number;
  opacity?: number;
  blendMode?: "source-over" | "screen" | "lighter";
  chromaticFringe?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerGlowStreakEffect = {
  enabled?: boolean;
  angle?: number;
  distance?: number;
  samples?: number | "auto";
  decay?: number;
  opacity?: number;
  threshold?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerChromaticSplitEffect = {
  enabled?: boolean;
  amount?: number;
  angle?: number;
  opacity?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerShaderTransitionEffect = {
  enabled?: boolean;
  shader?: "swirlVortex" | "cinematicZoom" | "rippleWaves" | "gravitationalLens" | "crossWarpMorph" | "glitch";
  progress?: number;
  duration?: number;
  opacity?: number;
  chromaticFringe?: number;
  quality?: VisualLayerEffectQuality;
};

export type VisualLayerEffects = {
  motionBlur?: boolean | VisualLayerMotionBlurEffect;
  motionTrail?: boolean | VisualLayerMotionBlurEffect;
  motionTile?: boolean | VisualLayerMotionTileEffect;
  gaussianBlur?: boolean | VisualLayerGaussianBlurEffect;
  radialBlur?: boolean | VisualLayerRadialBlurEffect;
  zoomBlur?: boolean | VisualLayerZoomBlurEffect;
  spiralEchoBlur?: boolean | VisualLayerSpiralEchoBlurEffect;
  glowStreak?: boolean | VisualLayerGlowStreakEffect;
  chromaticSplit?: boolean | VisualLayerChromaticSplitEffect;
  shaderTransition?: boolean | VisualLayerShaderTransitionEffect;
};

export type VisualLayerStyle = {
  x: number;
  y: number;
  width: number;
  height: number;
  anchorX: number;
  anchorY: number;
  opacity: number;
  rotation: number;
  scaleX: number;
  scaleY: number;
  skewX: number;
  skewY: number;
  cornerRadius: number;
  cornerRadiusTopLeft: number;
  cornerRadiusTopRight: number;
  cornerRadiusBottomRight: number;
  cornerRadiusBottomLeft: number;
  fit: "cover" | "contain" | "fill";
  crop: {
    left: number;
    top: number;
    right: number;
    bottom: number;
  };
  fill: {
    enabled: boolean;
    color: string;
    opacity: number;
  };
  border: {
    enabled: boolean;
    width: number;
    color: string;
    opacity: number;
    position: "inside" | "center" | "outside";
  };
  shadow: {
    enabled: boolean;
    x: number;
    y: number;
    blur: number;
    color: string;
    opacity: number;
  };
  glow: {
    enabled: boolean;
    color: string;
    blur: number;
    opacity: number;
    spread: number;
  };
  blendMode: string;
  filters: {
    brightness: number;
    contrast: number;
    saturation: number;
    exposure: number;
    hue: number;
    blur: number;
    grayscale: number;
    sepia: number;
    invert: number;
  };
  effects: VisualLayerEffects;
  motion: {
    preset: string;
    inDuration: number;
    outDuration: number;
    easing: string;
    keyframes?: Array<Record<string, number | string>>;
  };
  keyframes?: Record<string, Array<{ time: number; value: number; easing?: string }>>;
  animations?: Array<{
    property?: string;
    easing?: string;
    keyframes: Array<Record<string, number | string>>;
  }>;
};

export type TextLayerContent = {
  content: string;
  fontFamily: string;
  fontAssetId?: string;
  fontSize: number;
  fontWeight: number | string;
  fontStyle: "normal" | "italic" | "oblique";
  lineHeight: number;
  letterSpacing: number;
  textTransform: "none" | "uppercase" | "lowercase" | "capitalize";
  align: string;
  baseline: string;
  color: string;
  stroke: {
    enabled: boolean;
    color: string;
    width: number;
    opacity: number;
  };
  background: {
    enabled: boolean;
    color: string;
    opacity: number;
    radius: number;
    paddingX: number;
    paddingY: number;
  };
  shadow: {
    enabled: boolean;
    color: string;
    x: number;
    y: number;
    blur: number;
    opacity: number;
  };
  wrap: boolean;
};

export type WorkspaceTimelineClip = {
  id: string;
  name: string;
  type: "native-scene" | WorkspaceAssetType | "background" | "text" | "shape";
  assetId?: string;
  trackId: string;
  start: number;
  duration: number;
  trimIn: number;
  render?: {
    compositor?: "auto" | "timeline" | "scene";
  };
  style: VisualLayerStyle;
  text?: TextLayerContent;
  shape?: {
    kind: "rectangle" | "circle" | "line" | "arrow";
  };
};

export type WorkspaceTimelineTrack = {
  id: string;
  name: string;
  kind: "background" | "video" | "image" | "shape" | "text" | "audio" | "native-scene";
  isHidden?: boolean;
  isMuted?: boolean;
  clips: WorkspaceTimelineClip[];
};

export type WorkspaceTimeline = {
  version: number;
  fps: number;
  durationSeconds: number;
  timebase?: unknown;
  agentContract?: unknown;
  tracks: WorkspaceTimelineTrack[];
  updatedAt: string;
};
