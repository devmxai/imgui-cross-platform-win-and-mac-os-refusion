import type { HyperFrameFrameDescriptor, HyperFrameRenderPlan } from "../contracts/types";
import { evaluateHyperFrameFrameDescriptor } from "../frame/frameDescriptor";
import { createHyperFrameFxPassGraph, type HyperFrameFxPassGraph } from "../fx/fxPassGraph";
import { hyperFrameIndexToSeconds, secondsToHyperFrameIndex } from "../frame/pixelFrameContract";
import { createSourceSurfaceProviderForProfile } from "./sourceSurfaceProvider";
import {
  createFrameQualityPolicy,
  type CanonicalFrameProfile,
  type FrameQualityPolicy,
} from "./qualityPolicy";

export {
  createFrameQualityPolicy,
  type CanonicalFrameProfile,
  type FrameQualityPolicy,
} from "./qualityPolicy";

export type CanonicalFrameIssueSeverity = "info" | "warning" | "error";

export type CanonicalFrameIssue = {
  severity: CanonicalFrameIssueSeverity;
  code: string;
  message: string;
  layerId?: string;
  clipId?: string;
  assetId?: string;
};

export type CanonicalFrameDiagnostics = {
  version: 1;
  frameIndex: number;
  timeSeconds: number;
  profile: CanonicalFrameProfile;
  issues: CanonicalFrameIssue[];
};

export type RenderDiagnosticsSink = {
  push: (issue: CanonicalFrameIssue) => void;
};

export type SourceSurface = {
  id: string;
  layerId: string;
  frameIndex: number;
  timeSeconds: number;
  requestedTimeSeconds?: number;
  frameTimeSeconds?: number;
  approximatedTime?: boolean;
  width: number;
  height: number;
  surface: unknown;
  alpha: "premultiplied" | "opaque";
  colorSpace: "srgb";
};

export type TemporalSampleRequest = {
  layerId: string;
  clipId: string;
  frameIndex: number;
  timeSeconds: number;
  shutterSeconds: number;
  sampleCount: number;
};

export type SourceSurfaceSample = {
  frameIndex: number;
  timeSeconds: number;
  requestedTimeSeconds: number;
  frameTimeSeconds: number;
  approximatedTime: boolean;
  weight: number;
  surface: SourceSurface;
};

export type SourceSurfaceProvider = {
  id: string;
  mode: "exact-seek" | "streaming-playback" | "static";
  getSurface: (layerId: string, frameIndex: number) => Promise<SourceSurface>;
  getTemporalSamples: (request: TemporalSampleRequest) => Promise<SourceSurfaceSample[]>;
};

export type FinalFrameSurface = {
  frameIndex: number;
  timeSeconds: number;
  width: number;
  height: number;
  surface?: unknown;
  bytes?: Uint8Array;
  alpha: "premultiplied" | "opaque";
  colorSpace: "srgb";
  diagnostics: CanonicalFrameDiagnostics;
};

export type CanonicalFrameRequest = {
  frameIndex: number;
  timeSeconds: number;
  profile: CanonicalFrameProfile;
  descriptor: HyperFrameFrameDescriptor;
  fxPassGraph: HyperFrameFxPassGraph;
  sourceProvider?: SourceSurfaceProvider;
  quality: FrameQualityPolicy;
  diagnosticsReport: CanonicalFrameDiagnostics;
  diagnostics: RenderDiagnosticsSink;
};

export type CanonicalFrameRenderer = {
  id: string;
  renderFrame: (request: CanonicalFrameRequest) => Promise<FinalFrameSurface>;
};

export const createCanonicalFrameDiagnostics = (
  frameIndex: number,
  timeSeconds: number,
  profile: CanonicalFrameProfile,
): CanonicalFrameDiagnostics => ({
  version: 1,
  frameIndex,
  timeSeconds,
  profile,
  issues: [],
});

export const createDiagnosticsSink = (diagnostics: CanonicalFrameDiagnostics): RenderDiagnosticsSink => ({
  push: (issue) => {
    if (diagnostics.issues.some((existing) => (
      existing.code === issue.code
      && existing.layerId === issue.layerId
      && existing.clipId === issue.clipId
      && existing.assetId === issue.assetId
      && existing.message === issue.message
    ))) return;
    diagnostics.issues.push(issue);
  },
});

export const createCanonicalFrameRequest = (
  plan: HyperFrameRenderPlan,
  input: {
    frameIndex?: number;
    timeSeconds?: number;
    profile: CanonicalFrameProfile;
    sourceProvider?: SourceSurfaceProvider;
  },
): CanonicalFrameRequest => {
  const frameIndex = input.frameIndex !== undefined
    ? Math.max(0, Math.round(input.frameIndex))
    : secondsToHyperFrameIndex(input.timeSeconds ?? 0, plan.ir.fps);
  const timeSeconds = hyperFrameIndexToSeconds(frameIndex, plan.ir.fps);
  const descriptor = evaluateHyperFrameFrameDescriptor(plan.ir, timeSeconds);
  const diagnostics = createCanonicalFrameDiagnostics(frameIndex, timeSeconds, input.profile);
  const quality = createFrameQualityPolicy(input.profile);
  return {
    frameIndex,
    timeSeconds,
    profile: input.profile,
    descriptor,
    fxPassGraph: createHyperFrameFxPassGraph(descriptor, quality),
    sourceProvider: input.sourceProvider ?? createSourceSurfaceProviderForProfile(input.profile, plan.ir.fps),
    quality,
    diagnosticsReport: diagnostics,
    diagnostics: createDiagnosticsSink(diagnostics),
  };
};
