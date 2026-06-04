import type {
  HyperFrameEffectInstance,
  HyperFrameEffectKind,
  HyperFrameFrameDescriptor,
  HyperFrameFrameDescriptorLayer,
} from "../contracts/types";
import type { FrameQualityPolicy } from "../render-plan/qualityPolicy";
import { createMotionBlurSamplePlan, type MotionBlurSamplePlan } from "./motionBlurQualityPlanner";

export type HyperFrameFxPassKind =
  | "sourceResolve"
  | "cropFitMask"
  | "motionTileSampler"
  | "transform"
  | "transformMotionBlur"
  | "motionTrail"
  | "gaussianBlur"
  | "radialBlur"
  | "zoomBlur"
  | "spiralEchoBlur"
  | "glowStreak"
  | "chromaticSplit"
  | "shaderTransition"
  | "composite";

export type HyperFrameFxPassExecutionClass =
  | "source"
  | "mask"
  | "raster"
  | "transform"
  | "temporal"
  | "shader"
  | "composite"
  | "blocked";

export type HyperFrameFxPass = {
  id: string;
  kind: HyperFrameFxPassKind;
  layerId: string;
  clipId: string;
  effectId?: string;
  sourceEffectKind?: HyperFrameEffectKind;
  executionClass: HyperFrameFxPassExecutionClass;
  params: Record<string, unknown>;
  sampleBudget: number;
  motionBlurSamplePlan?: MotionBlurSamplePlan;
  diagnostics: string[];
  textureScale: number;
  order: number;
};

export type HyperFrameFxPassGraph = {
  version: 1;
  frameIndex: number;
  timeSeconds: number;
  profile: FrameQualityPolicy["profile"];
  passCount: number;
  layerIds: string[];
  passes: HyperFrameFxPass[];
  blockedPasses: HyperFrameFxPass[];
};

const shaderEffectKinds = new Set<HyperFrameEffectKind>([
  "transformMotionBlur",
  "radialBlur",
  "zoomBlur",
  "spiralEchoBlur",
  "glowStreak",
  "chromaticSplit",
  "shaderTransition",
]);

const sampleBudgetKeyByEffectKind: Record<HyperFrameEffectKind, string> = {
  gaussianBlur: "gaussianBlur",
  transformMotionBlur: "motionBlur",
  motionTrail: "motionTrail",
  motionTile: "motionTile",
  radialBlur: "radialBlur",
  zoomBlur: "zoomBlur",
  spiralEchoBlur: "spiralEchoBlur",
  glowStreak: "glowStreak",
  chromaticSplit: "chromaticSplit",
  shaderTransition: "shaderTransition",
};

const passKindByEffectKind: Record<HyperFrameEffectKind, HyperFrameFxPassKind> = {
  gaussianBlur: "gaussianBlur",
  transformMotionBlur: "transformMotionBlur",
  motionTrail: "motionTrail",
  motionTile: "motionTileSampler",
  radialBlur: "radialBlur",
  zoomBlur: "zoomBlur",
  spiralEchoBlur: "spiralEchoBlur",
  glowStreak: "glowStreak",
  chromaticSplit: "chromaticSplit",
  shaderTransition: "shaderTransition",
};

const createPassSamplePlan = (
  effect: HyperFrameEffectInstance,
  layer: HyperFrameFrameDescriptorLayer,
  descriptor: HyperFrameFrameDescriptor,
  policy: FrameQualityPolicy,
): MotionBlurSamplePlan | undefined => {
  if (effect.kind === "transformMotionBlur") {
    return createMotionBlurSamplePlan({
      effect,
      layer,
      frameTime: descriptor.time,
      fps: descriptor.fps,
      policy,
    });
  }
  return undefined;
};

const toPositiveSampleBudget = (
  effect: HyperFrameEffectInstance,
  policy: FrameQualityPolicy,
  motionBlurSamplePlan?: MotionBlurSamplePlan,
) => {
  if (motionBlurSamplePlan) return motionBlurSamplePlan.selectedSampleCount;
  const key = sampleBudgetKeyByEffectKind[effect.kind];
  const max = Math.max(1, Math.round(policy.maxSamples[key] ?? 1));
  const fallback = Math.max(1, Math.round(policy.defaultSamples[key] ?? max));
  const requested = effect.params.samples;
  if (requested === "auto" || requested === undefined || requested === null) return Math.min(max, fallback);
  const numeric = Number(requested);
  return Math.max(1, Math.min(max, Number.isFinite(numeric) ? Math.round(numeric) : fallback));
};

const executionClassForEffect = (
  effect: HyperFrameEffectInstance,
  layer: HyperFrameFrameDescriptorLayer,
): HyperFrameFxPassExecutionClass => {
  if (effect.kind === "transformMotionBlur" || effect.kind === "motionTrail") return "temporal";
  if (shaderEffectKinds.has(effect.kind)) return "shader";
  if (effect.kind === "motionTile" && layer.kind === "video") return "shader";
  return "raster";
};

const executionClassForBasePass = (kind: HyperFrameFxPassKind): HyperFrameFxPassExecutionClass => {
  if (kind === "sourceResolve") return "source";
  if (kind === "cropFitMask") return "mask";
  if (kind === "transform") return "transform";
  if (kind === "composite") return "composite";
  return "raster";
};

const createBasePass = (
  layer: HyperFrameFrameDescriptorLayer,
  kind: HyperFrameFxPassKind,
  order: number,
  policy: FrameQualityPolicy,
): HyperFrameFxPass => ({
  id: `${layer.id}:${kind}`,
  kind,
  layerId: layer.id,
  clipId: layer.clipId,
  executionClass: executionClassForBasePass(kind),
  params: {},
  sampleBudget: 1,
  diagnostics: [],
  textureScale: policy.textureScale,
  order,
});

const createEffectPass = (
  layer: HyperFrameFrameDescriptorLayer,
  effect: HyperFrameEffectInstance,
  descriptor: HyperFrameFrameDescriptor,
  order: number,
  policy: FrameQualityPolicy,
): HyperFrameFxPass => {
  const motionBlurSamplePlan = createPassSamplePlan(effect, layer, descriptor, policy);
  return {
    id: `${layer.id}:${effect.kind}:${effect.id}`,
    kind: passKindByEffectKind[effect.kind],
    layerId: layer.id,
    clipId: layer.clipId,
    effectId: effect.id,
    sourceEffectKind: effect.kind,
    executionClass: executionClassForEffect(effect, layer),
    params: motionBlurSamplePlan
      ? { ...effect.params, motionBlurSamplePlan }
      : effect.params,
    sampleBudget: toPositiveSampleBudget(effect, policy, motionBlurSamplePlan),
    motionBlurSamplePlan,
    diagnostics: motionBlurSamplePlan?.diagnostics ?? [],
    textureScale: policy.textureScale,
    order,
  };
};

export const createHyperFrameFxPassGraph = (
  descriptor: HyperFrameFrameDescriptor,
  policy: FrameQualityPolicy,
): HyperFrameFxPassGraph => {
  const passes: HyperFrameFxPass[] = [];
  let order = 0;

  for (const layer of descriptor.layers) {
    passes.push(createBasePass(layer, "sourceResolve", order += 1, policy));
    passes.push(createBasePass(layer, "cropFitMask", order += 1, policy));

    const motionTile = layer.normalizedEffects.find((effect) => effect.enabled && effect.kind === "motionTile");
    if (motionTile) passes.push(createEffectPass(layer, motionTile, descriptor, order += 1, policy));

    passes.push(createBasePass(layer, "transform", order += 1, policy));

    for (const effect of layer.normalizedEffects) {
      if (!effect.enabled || effect.kind === "motionTile") continue;
      passes.push(createEffectPass(layer, effect, descriptor, order += 1, policy));
    }

    passes.push(createBasePass(layer, "composite", order += 1, policy));
  }

  const blockedPasses = passes.filter((pass) => pass.executionClass === "blocked");
  return {
    version: 1,
    frameIndex: descriptor.frameIndex,
    timeSeconds: descriptor.time,
    profile: policy.profile,
    passCount: passes.length,
    layerIds: descriptor.layers.map((layer) => layer.id),
    passes,
    blockedPasses,
  };
};
