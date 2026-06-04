import type { HyperFrameEffectInstance, HyperFrameFrameDescriptorLayer } from "../contracts/types";
import type { FrameQualityPolicy } from "../render-plan/qualityPolicy";

export type MotionBlurQualityTier = "off" | "draft" | "preview" | "high" | "cinematic" | "clamped";

export type MotionBlurSamplePlan = {
  version: 2;
  shutterStartTime: number;
  shutterEndTime: number;
  sampleTimes: number[];
  weights: number[];
  estimatedMaxPixelDisplacement: number;
  estimatedAngularSweep: number;
  estimatedEdgeVelocity: number;
  requiredSampleCount: number;
  selectedSampleCount: number;
  qualityTier: MotionBlurQualityTier;
  diagnostics: string[];
};

const clamp = (value: number, min: number, max: number) => (
  Math.max(min, Math.min(max, value))
);

const toFiniteNumber = (value: unknown, fallback: number) => {
  const next = Number(value);
  return Number.isFinite(next) ? next : fallback;
};

const requestedSamples = (effect: HyperFrameEffectInstance, fallback: number) => {
  const quality = String(effect.params.quality || effect.quality || "auto");
  if (quality === "draft") return 8;
  if (quality === "preview") return 16;
  if (quality === "high") return 48;
  if (quality === "cinematic" || quality === "best" || quality === "ultra") return 96;
  if (effect.params.samples === "auto" || effect.params.samples === undefined || effect.params.samples === null) {
    return fallback;
  }
  return Math.max(2, Math.round(toFiniteNumber(effect.params.samples, fallback)));
};

const reconstructionWeight = (progress: number, curve: string) => {
  if (curve === "uniform" || curve === "linear") return 1;
  if (curve === "centerWeighted") {
    const distance = Math.abs(progress - 0.5) * 2;
    return Math.max(0.01, 1 - distance * 0.55);
  }
  const a0 = 0.35875;
  const a1 = 0.48829;
  const a2 = 0.14128;
  const a3 = 0.01168;
  const x = 2 * Math.PI * progress;
  return Math.max(0.001, a0 - a1 * Math.cos(x) + a2 * Math.cos(2 * x) - a3 * Math.cos(3 * x));
};

export const createMotionBlurSamplePlan = ({
  effect,
  layer,
  frameTime,
  fps,
  policy,
}: {
  effect: HyperFrameEffectInstance;
  layer: HyperFrameFrameDescriptorLayer;
  frameTime: number;
  fps: number;
  policy: FrameQualityPolicy;
}): MotionBlurSamplePlan => {
  const safeFps = Math.max(1, fps);
  const frameDuration = 1 / safeFps;
  const shutterAngle = clamp(toFiniteNumber(effect.params.shutterAngle, toFiniteNumber(effect.params.shutter, 1) * 180), 0, 1440);
  const shutterPhase = clamp(toFiniteNumber(effect.params.shutterPhase, -shutterAngle / 2), -720, 720);
  const amount = clamp(toFiniteNumber(effect.params.amount ?? effect.params.strength, 1), 0, 10);
  const shutterDuration = frameDuration * shutterAngle / 360 * amount;
  const centerTime = frameTime + frameDuration * shutterPhase / 360;
  const shutterStartTime = Math.max(0, centerTime - shutterDuration / 2);
  const shutterEndTime = Math.max(shutterStartTime, centerTime + shutterDuration / 2);
  const maxDimension = Math.max(layer.transform.width, layer.transform.height, 1);
  const angularSweep = Math.abs(layer.motion.angularVelocityDegrees) * shutterDuration;
  const translationSweep = layer.motion.speed * shutterDuration;
  const scaleSweep = Math.max(Math.abs(layer.motion.scaleVelocityX), Math.abs(layer.motion.scaleVelocityY)) * shutterDuration * maxDimension;
  const skewSweep = Math.max(Math.abs(layer.motion.skewVelocityX), Math.abs(layer.motion.skewVelocityY)) * shutterDuration * maxDimension * 0.35;
  const angularPixels = Math.abs(angularSweep) * Math.PI / 180 * maxDimension * 0.5;
  const estimatedMaxPixelDisplacement = translationSweep + angularPixels + scaleSweep + skewSweep;
  const estimatedEdgeVelocity = estimatedMaxPixelDisplacement / Math.max(0.0001, shutterDuration);
  const displacementSamples = Math.ceil(estimatedMaxPixelDisplacement / 1.35);
  const angularSamples = Math.ceil(Math.abs(angularSweep) / 18);
  const requiredSampleCount = Math.max(2, displacementSamples, angularSamples);
  const maxSamples = Math.max(2, Math.round(policy.maxSamples.motionBlur ?? 2));
  const fallbackSamples = Math.max(2, Math.round(policy.defaultSamples.motionBlur ?? maxSamples));
  const requestedSampleCount = requestedSamples(effect, fallbackSamples);
  const selectedSampleCount = Math.min(maxSamples, Math.max(requestedSampleCount, requiredSampleCount));
  const diagnostics: string[] = ["motion-blur-adaptive-samples-selected"];
  if (selectedSampleCount < requiredSampleCount) diagnostics.push("motion-blur-samples-clamped-by-backend");
  const curve = String(effect.params.sampleCurve || "filmic");
  const rawSamples = Array.from({ length: selectedSampleCount }, (_, index) => {
    const progress = selectedSampleCount === 1 ? 0.5 : index / (selectedSampleCount - 1);
    return {
      time: shutterStartTime + progress * (shutterEndTime - shutterStartTime),
      weight: reconstructionWeight(progress, curve),
    };
  });
  const totalWeight = Math.max(0.0001, rawSamples.reduce((total, sample) => total + sample.weight, 0));
  const qualityTier: MotionBlurQualityTier = selectedSampleCount < requiredSampleCount
    ? "clamped"
    : selectedSampleCount >= 96
      ? "cinematic"
      : selectedSampleCount >= 48
        ? "high"
        : selectedSampleCount >= 16
          ? "preview"
          : "draft";
  return {
    version: 2,
    shutterStartTime,
    shutterEndTime,
    sampleTimes: rawSamples.map((sample) => sample.time),
    weights: rawSamples.map((sample) => sample.weight / totalWeight),
    estimatedMaxPixelDisplacement,
    estimatedAngularSweep: angularSweep,
    estimatedEdgeVelocity,
    requiredSampleCount,
    selectedSampleCount,
    qualityTier,
    diagnostics,
  };
};
