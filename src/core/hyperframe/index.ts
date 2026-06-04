export type {
  NativeSceneFiles,
  VisualLayerEffects,
  VisualLayerStyle,
  WorkspaceAsset,
  WorkspaceComposition,
  WorkspaceTimeline,
  WorkspaceTimelineClip,
  WorkspaceTimelineTrack,
} from "./contracts/projectTypes";

export type {
  HyperFrameAuthoringModel,
  HyperFrameAdapterResolution,
  HyperFrameBmfExportJob,
  HyperFrameBmfExportNode,
  HyperFrameEffectInstance,
  HyperFrameEffectKind,
  HyperFrameFrameDescriptor,
  HyperFrameFrameDescriptorLayer,
  HyperFrameFrameDescriptorPlan,
  HyperFrameFrameTimingContract,
  HyperFrameGateIssue,
  HyperFrameIR,
  HyperFrameIRLayer,
  HyperFrameMotionFxExecutionRequirement,
  HyperFramePixelFrameContract,
  HyperFramePixelGeometryContract,
  HyperFramePreviewRendererJob,
  HyperFrameRenderPass,
  HyperFrameRenderPlan,
  HyperFrameRenderPlanSummary,
  HyperFrameRuntimeAdapter,
  HyperFrameRuntimeAdapters,
  HyperFrameRuntimeAdapterRole,
  HyperFrameRuntimeAdapterStatus,
  HyperFrameTransactionGateResult,
  HyperFrameTransactionInput,
  HyperFrameTransactionIntent,
  HyperFrameTransactionSource,
} from "./contracts/types";

export {
  createHyperFrameAuthoringModel,
} from "./project/authoringModel";

export {
  compileHyperFrameIR,
} from "./project/ir";

export {
  createHyperFrameRevision,
  validateHyperFrameTransaction,
} from "./project/transactionGate";

export {
  createHyperFrameFrameTimingContract,
  createHyperFramePixelFrameContract,
  createHyperFramePixelGeometryContract,
  hyperFrameIndexToSeconds,
  isLayerActiveOnFrame,
  secondsToHyperFrameIndex,
  toHyperFrameRange,
} from "./frame/pixelFrameContract";

export {
  applyHyperFrameEasing,
  compileHyperFrameAnimationTracks,
  createHyperFrameFrameDescriptorPlan,
  evaluateHyperFrameFrameDescriptor,
  evaluateHyperFrameLayerAnimation,
  evaluateHyperFrameSubframeDescriptor,
  normalizeHyperFrameAnimatedProperty,
} from "./frame/frameDescriptor";

export {
  canonicalEffectNames,
  duplicateProneEffectNames,
  getHyperFrameEffectEntries,
  getHyperFrameEffectParamIssues,
  getHyperFrameEnabledEffectNames,
  isHyperFrameEffectEnabled,
  legacyEffectParamAliases,
  normalizeHyperFrameEffects,
  normalizeHyperFrameEffectValue,
} from "./fx/effectNormalizer";

export { default as hyperFrameFxRegistryManifest } from "./fx/fxRegistry.manifest.json";

export {
  getActiveEffectIntentNames,
  getActiveFilterNames,
  layerHasActiveEffectIntent,
  layerHasActiveEffects,
  layerHasActiveFilter,
} from "./fx/effects";

export type {
  HyperFrameFxPass,
  HyperFrameFxPassExecutionClass,
  HyperFrameFxPassGraph,
  HyperFrameFxPassKind,
} from "./fx/fxPassGraph";

export {
  createHyperFrameFxPassGraph,
} from "./fx/fxPassGraph";

export type {
  MotionBlurQualityTier,
  MotionBlurSamplePlan,
} from "./fx/motionBlurQualityPlanner";

export {
  createMotionBlurSamplePlan,
} from "./fx/motionBlurQualityPlanner";

export {
  createMotionFxCapabilityReport,
  validateMotionFxCapabilities,
} from "./fx/motionFxCapabilities";

export type {
  TimelineAgentContext,
  TimelineAgentContextLayer,
} from "./timeline/timelineAgentContext";

export {
  createTimelineAgentContext,
} from "./timeline/timelineAgentContext";

export {
  clampTimelineTime,
  clipFrameRange,
  frameDurationSeconds,
  frameToTime,
  snapTimeToFrame,
  timeToFrame,
} from "./timeline/timelineFrameMath";

export type {
  TimelineCompositionInfo,
  TimelineOperation,
  TimelineOperationDiagnostic,
  TimelineOperationResult,
} from "./timeline/timelineOperationTypes";

export {
  applyTimelineOperation,
} from "./timeline/timelineOperations";

export type {
  CanonicalFrameDiagnostics,
  CanonicalFrameIssue,
  CanonicalFrameIssueSeverity,
  CanonicalFrameProfile,
  CanonicalFrameRenderer,
  CanonicalFrameRequest,
  FinalFrameSurface,
  FrameQualityPolicy,
  RenderDiagnosticsSink,
  SourceSurface,
  SourceSurfaceProvider,
  SourceSurfaceSample,
  TemporalSampleRequest,
} from "./render-plan/canonicalFrameRequest";

export {
  createCanonicalFrameDiagnostics,
  createCanonicalFrameRequest,
  createDiagnosticsSink,
} from "./render-plan/canonicalFrameRequest";

export {
  createFrameQualityPolicy,
} from "./render-plan/qualityPolicy";

export {
  createExactSeekSourceSurfaceProvider,
  createSourceSurfaceProviderForProfile,
  createStaticSourceSurfaceProvider,
  createStreamingPlaybackSourceSurfaceProvider,
} from "./render-plan/sourceSurfaceProvider";

export type {
  SourceSurfaceProviderMode,
} from "./render-plan/sourceSurfaceProvider";

export {
  createPreviewRendererJob,
} from "./render-plan/previewRenderer";

export {
  createBmfExportJob,
} from "./render-plan/bmfExport";

export type {
  HyperFrameBmfJobValidation,
  HyperFrameBmfSchemaIssue,
  HyperFrameBmfSchemaIssueSeverity,
} from "./render-plan/bmfSchema";

export {
  formatBmfValidationMessages,
  validateBmfExportJob,
} from "./render-plan/bmfSchema";

export type {
  HyperFrameRenderPlannerOptions,
} from "./render-plan/renderPlanner";

export {
  planHyperFrameRender,
} from "./render-plan/renderPlanner";
