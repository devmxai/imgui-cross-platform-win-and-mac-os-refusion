import type {
  HyperFrameIR,
  HyperFrameRenderPass,
  HyperFrameRenderPlan,
  HyperFrameRuntimeAdapters,
  HyperFrameTransactionGateResult,
} from "../contracts/types";
import { createBmfExportJob } from "./bmfExport";
import { createHyperFrameFrameDescriptorPlan } from "../frame/frameDescriptor";
import { createMotionFxCapabilityReport } from "../fx/motionFxCapabilities";
import { createPreviewRendererJob } from "./previewRenderer";

export type HyperFrameRenderPlannerOptions = {
  runtimeAdapters: HyperFrameRuntimeAdapters;
  activeExportAdapter?: string;
  browserFrameStreamAdapter?: string;
  browserFrameStreamExecutable?: boolean;
};

export const planHyperFrameRender = (
  ir: HyperFrameIR,
  gate: HyperFrameTransactionGateResult,
  options: HyperFrameRenderPlannerOptions,
): HyperFrameRenderPlan => {
  const previewJob = createPreviewRendererJob(ir);
  const frameDescriptor = createHyperFrameFrameDescriptorPlan(ir);
  const bmfJob = createBmfExportJob(ir);
  const runtimeAdapters = options.runtimeAdapters;
  const motionFx = createMotionFxCapabilityReport(ir);
  const mediaLayerIds = ir.layers
    .filter((layer) => layer.asset && (layer.kind === "video" || layer.kind === "audio" || layer.kind === "image"))
    .map((layer) => layer.id);
  const decodedLayerIds = ir.layers
    .filter((layer) => layer.asset && (layer.kind === "video" || layer.kind === "audio"))
    .map((layer) => layer.id);
  const cacheLayerIds = ir.layers
    .filter((layer) => layer.kind === "shape" || layer.kind === "text")
    .map((layer) => layer.id);
  const effectsLayerIds = motionFx.effectLayerIds;
  const audioLayerIds = ir.layers
    .filter((layer) => layer.kind === "audio" || layer.kind === "video")
    .filter((layer) => !layer.muted)
    .map((layer) => layer.id);

  const passes: HyperFrameRenderPass[] = [
    {
      id: "media-preload",
      kind: "media-preload",
      layerIds: mediaLayerIds,
      reason: "Resolve user assets before preview/export so UI and agent-authored clips share the same media source.",
    },
    {
      id: "decode",
      kind: "decode",
      layerIds: decodedLayerIds,
      reason: "Prepare time-based media independently from canvas composition.",
    },
    {
      id: "raster-cache",
      kind: "raster-cache",
      layerIds: cacheLayerIds,
      reason: "Cache text and vector-like layers before animation/effects to avoid per-frame rebuilds.",
    },
    {
      id: "effects",
      kind: "effects",
      layerIds: effectsLayerIds,
      reason: "Apply effects from declarative layer intent through runtime-owned quality policy.",
    },
    {
      id: "composite",
      kind: "composite",
      layerIds: ir.layers.map((layer) => layer.id),
      reason: "Composite all visible layers into one deterministic full-composition canvas.",
    },
    {
      id: "audio-mix",
      kind: "audio-mix",
      layerIds: audioLayerIds,
      reason: "Mix audible timeline media from the same IR used by preview and export.",
    },
    {
      id: "export",
      kind: "export",
      layerIds: ir.layers.map((layer) => layer.id),
      reason: "Hand final frames plus HyperFrame AudioPCM to the selected encoder/mux executor after rendering is complete.",
    },
  ];

  return {
    version: 1,
    revision: ir.revision,
    source: gate.source,
    intent: gate.intent,
    transactionGate: gate,
    previewRenderer: {
      target: "preview",
      executionContract: "hyperframe-ir-frame-descriptor",
      surfaceContract: "deterministic-final-frame-surface",
      deterministicCanvas: true,
    },
    previewJob,
    frameDescriptor,
    exportPipeline: {
      target: "export",
      activeAdapter: options.activeExportAdapter ?? runtimeAdapters.export.id,
      source: "hyperframe-final-frame-stream",
      singleSourceIr: true,
      browserFrameStreamAdapter: options.browserFrameStreamAdapter ?? "final-frame-stream-browser-encoder",
      browserFrameStreamExecutable: options.browserFrameStreamExecutable ?? true,
    },
    bmfJob,
    runtimeAdapters,
    motionFx,
    ir,
    passes,
    issues: gate.issues,
  };
};
