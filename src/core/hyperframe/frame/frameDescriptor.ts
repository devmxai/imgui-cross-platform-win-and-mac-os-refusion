import type {
  HyperFrameFrameDescriptor,
  HyperFrameFrameDescriptorLayer,
  HyperFrameFrameDescriptorPlan,
  HyperFrameIR,
  HyperFrameIRLayer,
} from "../contracts/types";
import {
  hyperFrameIndexToSeconds,
  isLayerActiveOnFrame,
  secondsToHyperFrameIndex,
} from "./pixelFrameContract";
import { normalizeHyperFrameEffects } from "../fx/effectNormalizer";

export type HyperFrameFrameDescriptorEvaluationOptions = {
  subframe?: boolean;
};

type AnimationFrame = {
  time: number;
  value: number;
  easing?: string;
};

type AnimationTracks = Record<string, AnimationFrame[]>;

type AnimationState = {
  x: number;
  y: number;
  positionX: number;
  positionY: number;
  centerX: number;
  centerY: number;
  opacity: number;
  translateX: number;
  translateY: number;
  scaleX: number;
  scaleY: number;
  rotation: number;
  skewX: number;
  skewY: number;
  cornerRadius: number;
  blur: number;
  brightness: number;
  contrast: number;
  saturation: number;
  exposure: number;
  hue: number;
  grayscale: number;
  sepia: number;
  invert: number;
};

const animatedPropertyAliases: Record<string, string> = {
  x: "positionX",
  y: "positionY",
  positionX: "positionX",
  positionY: "positionY",
  left: "x",
  top: "y",
  centerX: "centerX",
  centerY: "centerY",
  cx: "centerX",
  cy: "centerY",
  tx: "translateX",
  ty: "translateY",
  translate: "translateX",
  translateX: "translateX",
  translateY: "translateY",
  scale: "scale",
  scaleX: "scaleX",
  scaleY: "scaleY",
  rotate: "rotation",
  rotation: "rotation",
  opacity: "opacity",
  skewX: "skewX",
  skewY: "skewY",
  radius: "cornerRadius",
  cornerRadius: "cornerRadius",
  blur: "blur",
  brightness: "brightness",
  contrast: "contrast",
  saturation: "saturation",
  saturate: "saturation",
  exposure: "exposure",
  hue: "hue",
  grayscale: "grayscale",
  sepia: "sepia",
  invert: "invert",
};

const clamp = (value: number, min: number, max: number) => (
  Math.max(min, Math.min(max, value))
);

const clamp01 = (value: number, fallback = 0) => {
  const next = Number.isFinite(value) ? value : fallback;
  return clamp(next, 0, 1);
};

const toNumber = (value: unknown, fallback: number) => {
  const next = Number(value);
  return Number.isFinite(next) ? next : fallback;
};

const animatedOrBase = (value: number, base: number) => (
  Number.isFinite(value) ? value : base
);

export const normalizeHyperFrameAnimatedProperty = (property: string): string => (
  animatedPropertyAliases[property] || property
);

export const applyHyperFrameEasing = (value: number, easing?: string): number => {
  const t = clamp01(value, 0);
  if (easing === "easeIn") return t * t * t;
  if (easing === "linear") return t;
  if (easing === "easeInOut") return t < 0.5 ? 2 * t * t : 1 - ((-2 * t + 2) ** 2) / 2;
  if (easing === "easeOutBack" || easing === "backOut") {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return 1 + c3 * ((t - 1) ** 3) + c1 * ((t - 1) ** 2);
  }
  if (easing === "easeInBack" || easing === "backIn") {
    const c1 = 1.70158;
    const c3 = c1 + 1;
    return c3 * t * t * t - c1 * t * t;
  }
  if (easing === "easeInOutBack" || easing === "backInOut") {
    const c1 = 1.70158;
    const c2 = c1 * 1.525;
    return t < 0.5
      ? ((2 * t) ** 2 * ((c2 + 1) * 2 * t - c2)) / 2
      : (((2 * t - 2) ** 2) * ((c2 + 1) * (t * 2 - 2) + c2) + 2) / 2;
  }
  return 1 - ((1 - t) ** 3);
};

const addFrameToTracks = (
  tracks: AnimationTracks,
  frame: Record<string, unknown>,
  defaultEasing?: string,
) => {
  const time = toNumber(frame.time ?? frame.t, Number.NaN);
  if (!Number.isFinite(time)) return;

  const easing = String(frame.easing || defaultEasing || "");
  for (const [rawProperty, rawValue] of Object.entries(frame)) {
    if (rawProperty === "time" || rawProperty === "t" || rawProperty === "easing") continue;

    const value = toNumber(rawValue, Number.NaN);
    if (!Number.isFinite(value)) continue;

    const property = normalizeHyperFrameAnimatedProperty(rawProperty);
    tracks[property] ??= [];
    tracks[property].push({ time, value, easing });
  }
};

const presetFrames = (preset: string, duration: number): Array<Record<string, number | string>> => {
  const d = Math.max(0.001, duration || 0.35);
  if (preset === "fade") return [
    { time: 0, opacity: 0 },
    { time: d, opacity: 1 },
  ];
  if (preset === "pop") return [
    { time: 0, opacity: 0, scaleX: 0.82, scaleY: 0.82 },
    { time: d, opacity: 1, scaleX: 1, scaleY: 1 },
  ];
  if (preset === "pop-up-spin" || preset === "popUpSpin") return [
    { time: 0, opacity: 0, scaleX: 0.18, scaleY: 0.18, translateY: 90, rotation: -540 },
    { time: d * 0.76, opacity: 1, scaleX: 1.08, scaleY: 1.08, translateY: 0, rotation: 8, easing: "easeOutBack" },
    { time: d, opacity: 1, scaleX: 1, scaleY: 1, translateY: 0, rotation: 0, easing: "easeOut" },
  ];
  if (preset === "bounce-in" || preset === "bounceIn") return [
    { time: 0, opacity: 0, scaleX: 0.18, scaleY: 0.18, translateY: 300, rotation: 0 },
    { time: d * 0.49, opacity: 1, scaleX: 1.1, scaleY: 1.1, translateY: 0, rotation: -2, easing: "easeOutBack" },
    { time: d * 0.64, opacity: 1, scaleX: 0.96, scaleY: 0.96, translateY: 0, rotation: 1.4, easing: "easeOut" },
    { time: d * 0.79, opacity: 1, scaleX: 1.025, scaleY: 1.025, translateY: 0, rotation: -0.65, easing: "easeOut" },
    { time: d, opacity: 1, scaleX: 1, scaleY: 1, translateY: 0, rotation: 0, easing: "easeOut" },
  ];
  if (preset === "fade-up" || preset === "fadeUp") return [
    { time: 0, opacity: 0, translateY: 72 },
    { time: d, opacity: 1, translateY: 0 },
  ];
  if (preset === "slide-left") return [
    { time: 0, opacity: 0, translateX: 96 },
    { time: d, opacity: 1, translateX: 0 },
  ];
  if (preset === "slide-right") return [
    { time: 0, opacity: 0, translateX: -96 },
    { time: d, opacity: 1, translateX: 0 },
  ];
  if (preset === "slide-up") return [
    { time: 0, opacity: 0, translateY: 96 },
    { time: d, opacity: 1, translateY: 0 },
  ];
  if (preset === "slide-down") return [
    { time: 0, opacity: 0, translateY: -96 },
    { time: d, opacity: 1, translateY: 0 },
  ];
  return [];
};

export const compileHyperFrameAnimationTracks = (layer: HyperFrameIRLayer): AnimationTracks => {
  const tracks: AnimationTracks = {};
  const style = layer.style;
  const motion = style.motion || {};
  const defaultEasing = motion.easing || "easeOut";
  const preset = motion.preset || "none";

  if (preset !== "none") {
    for (const frame of presetFrames(preset, toNumber(motion.inDuration, 0.35))) {
      addFrameToTracks(tracks, frame, defaultEasing);
    }
  }

  if (Array.isArray(motion.keyframes)) {
    for (const frame of motion.keyframes) addFrameToTracks(tracks, frame, defaultEasing);
  }

  if (style.keyframes && typeof style.keyframes === "object") {
    for (const [rawProperty, frames] of Object.entries(style.keyframes)) {
      if (!Array.isArray(frames)) continue;
      const property = normalizeHyperFrameAnimatedProperty(rawProperty);
      tracks[property] ??= [];

      for (const frame of frames) {
        const time = toNumber(frame.time, Number.NaN);
        const value = toNumber(frame.value, Number.NaN);
        if (Number.isFinite(time) && Number.isFinite(value)) {
          tracks[property].push({ time, value, easing: String(frame.easing || defaultEasing) });
        }
      }
    }
  }

  if (Array.isArray(style.animations)) {
    for (const animation of style.animations) {
      if (!animation || !Array.isArray(animation.keyframes)) continue;
      const easing = animation.easing || defaultEasing;

      if (animation.property) {
        const property = normalizeHyperFrameAnimatedProperty(animation.property);
        tracks[property] ??= [];
        for (const frame of animation.keyframes) {
          const time = toNumber(frame.time ?? frame.t, Number.NaN);
          const value = toNumber(frame.value, Number.NaN);
          if (Number.isFinite(time) && Number.isFinite(value)) {
            tracks[property].push({ time, value, easing: String(frame.easing || easing) });
          }
        }
      } else {
        for (const frame of animation.keyframes) addFrameToTracks(tracks, frame, easing);
      }
    }
  }

  for (const frames of Object.values(tracks)) frames.sort((a, b) => a.time - b.time);
  return tracks;
};

const evaluateTrack = (
  frames: AnimationFrame[] | undefined,
  time: number,
  fallback: number,
) => {
  if (!frames || frames.length === 0) return fallback;
  if (time <= frames[0].time) return frames[0].value;
  const last = frames[frames.length - 1];
  if (time >= last.time) return last.value;

  for (let index = 1; index < frames.length; index += 1) {
    const previous = frames[index - 1];
    const next = frames[index];
    if (time <= next.time) {
      const span = Math.max(0.0001, next.time - previous.time);
      const progress = applyHyperFrameEasing((time - previous.time) / span, next.easing || previous.easing);
      return previous.value + (next.value - previous.value) * progress;
    }
  }

  return fallback;
};

export const evaluateHyperFrameLayerAnimation = (
  layer: HyperFrameIRLayer,
  localTime: number,
): AnimationState => {
  const motion = layer.style.motion || {};
  const tracks = compileHyperFrameAnimationTracks(layer);
  const clipDuration = Math.max(0, toNumber(layer.timing.duration, 0));
  const outDuration = Math.max(0, toNumber(motion.outDuration, 0));
  const outOpacity = outDuration > 0
    ? applyHyperFrameEasing((clipDuration - localTime) / outDuration, motion.easing)
    : 1;

  return {
    x: evaluateTrack(tracks.x, localTime, Number.NaN),
    y: evaluateTrack(tracks.y, localTime, Number.NaN),
    positionX: evaluateTrack(tracks.positionX, localTime, Number.NaN),
    positionY: evaluateTrack(tracks.positionY, localTime, Number.NaN),
    centerX: evaluateTrack(tracks.centerX, localTime, Number.NaN),
    centerY: evaluateTrack(tracks.centerY, localTime, Number.NaN),
    opacity: evaluateTrack(tracks.opacity, localTime, 1) * outOpacity,
    translateX: evaluateTrack(tracks.translateX, localTime, 0),
    translateY: evaluateTrack(tracks.translateY, localTime, 0),
    scaleX: evaluateTrack(tracks.scaleX, localTime, evaluateTrack(tracks.scale, localTime, 1)),
    scaleY: evaluateTrack(tracks.scaleY, localTime, evaluateTrack(tracks.scale, localTime, 1)),
    rotation: evaluateTrack(tracks.rotation, localTime, 0),
    skewX: evaluateTrack(tracks.skewX, localTime, 0),
    skewY: evaluateTrack(tracks.skewY, localTime, 0),
    cornerRadius: evaluateTrack(tracks.cornerRadius, localTime, Number.NaN),
    blur: evaluateTrack(tracks.blur, localTime, Number.NaN),
    brightness: evaluateTrack(tracks.brightness, localTime, Number.NaN),
    contrast: evaluateTrack(tracks.contrast, localTime, Number.NaN),
    saturation: evaluateTrack(tracks.saturation, localTime, Number.NaN),
    exposure: evaluateTrack(tracks.exposure, localTime, Number.NaN),
    hue: evaluateTrack(tracks.hue, localTime, Number.NaN),
    grayscale: evaluateTrack(tracks.grayscale, localTime, Number.NaN),
    sepia: evaluateTrack(tracks.sepia, localTime, Number.NaN),
    invert: evaluateTrack(tracks.invert, localTime, Number.NaN),
  };
};

const evaluateLayerDescriptor = (
  ir: HyperFrameIR,
  layer: HyperFrameIRLayer,
  time: number,
  frameIndex: number,
  options: HyperFrameFrameDescriptorEvaluationOptions = {},
): HyperFrameFrameDescriptorLayer | null => {
  if (options.subframe) {
    const end = layer.timing.start + Math.max(0, layer.timing.duration);
    if (time < layer.timing.start || time >= end) return null;
  } else if (!isLayerActiveOnFrame(layer, frameIndex, ir.fps)) {
    return null;
  }

  const style = layer.style;
  const localTime = Math.max(0, time - layer.timing.start);
  const width = Math.max(1, toNumber(style.width, ir.composition.width));
  const height = Math.max(1, toNumber(style.height, ir.composition.height));
  const baseX = toNumber(style.x, 0);
  const baseY = toNumber(style.y, 0);
  const anchorX = toNumber(style.anchorX, 0.5);
  const anchorY = toNumber(style.anchorY, 0.5);
  const baseScaleX = toNumber(style.scaleX, 1);
  const baseScaleY = toNumber(style.scaleY, 1);
  const baseRotation = toNumber(style.rotation, 0);
  const baseSkewX = toNumber(style.skewX, 0);
  const baseSkewY = toNumber(style.skewY, 0);
  const baseOpacity = clamp01(toNumber(style.opacity, 1), 1);
  const animation = evaluateHyperFrameLayerAnimation(layer, localTime);

  let x = Number.isFinite(animation.x)
    ? animation.x
    : Number.isFinite(animation.positionX)
      ? animation.positionX - width * anchorX
      : baseX;
  let y = Number.isFinite(animation.y)
    ? animation.y
    : Number.isFinite(animation.positionY)
      ? animation.positionY - height * anchorY
      : baseY;

  if (Number.isFinite(animation.centerX)) x = animation.centerX - width / 2;
  if (Number.isFinite(animation.centerY)) y = animation.centerY - height / 2;

  const centerX = x + width * anchorX + animation.translateX;
  const centerY = y + height * anchorY + animation.translateY;
  const previousLocalTime = Math.max(0, localTime - 1 / Math.max(1, ir.fps));
  const previousAnimation = evaluateHyperFrameLayerAnimation(layer, previousLocalTime);
  let previousX = Number.isFinite(previousAnimation.x)
    ? previousAnimation.x
    : Number.isFinite(previousAnimation.positionX)
      ? previousAnimation.positionX - width * anchorX
      : baseX;
  let previousY = Number.isFinite(previousAnimation.y)
    ? previousAnimation.y
    : Number.isFinite(previousAnimation.positionY)
      ? previousAnimation.positionY - height * anchorY
      : baseY;

  if (Number.isFinite(previousAnimation.centerX)) previousX = previousAnimation.centerX - width / 2;
  if (Number.isFinite(previousAnimation.centerY)) previousY = previousAnimation.centerY - height / 2;

  const previousCenterX = previousX + width * anchorX + previousAnimation.translateX;
  const previousCenterY = previousY + height * anchorY + previousAnimation.translateY;
  const velocityX = (centerX - previousCenterX) * Math.max(1, ir.fps);
  const velocityY = (centerY - previousCenterY) * Math.max(1, ir.fps);
  const frameRate = Math.max(1, ir.fps);
  const scaleX = baseScaleX * animation.scaleX;
  const scaleY = baseScaleY * animation.scaleY;
  const rotationDegrees = baseRotation + animation.rotation;
  const skewXDegrees = baseSkewX + animation.skewX;
  const skewYDegrees = baseSkewY + animation.skewY;
  const opacity = clamp01(baseOpacity * animation.opacity, 1);
  const previousScaleX = baseScaleX * previousAnimation.scaleX;
  const previousScaleY = baseScaleY * previousAnimation.scaleY;
  const previousRotationDegrees = baseRotation + previousAnimation.rotation;
  const previousSkewXDegrees = baseSkewX + previousAnimation.skewX;
  const previousSkewYDegrees = baseSkewY + previousAnimation.skewY;
  const previousOpacity = clamp01(baseOpacity * previousAnimation.opacity, 1);
  const filters = style.filters;

  return {
    id: layer.id,
    clipId: layer.clipId,
    trackId: layer.trackId,
    kind: layer.kind,
    zIndex: layer.zIndex,
    localTime,
    mediaTime: layer.timing.trimIn + localTime,
    timing: layer.timing,
    asset: layer.asset,
    text: layer.text,
    shape: layer.shape,
    transform: {
      x,
      y,
      width,
      height,
      centerX,
      centerY,
      originX: width * anchorX,
      originY: height * anchorY,
      anchorX,
      anchorY,
      scaleX,
      scaleY,
      rotationDegrees,
      rotationRadians: rotationDegrees * Math.PI / 180,
      skewXDegrees,
      skewYDegrees,
      skewXRadians: skewXDegrees * Math.PI / 180,
      skewYRadians: skewYDegrees * Math.PI / 180,
    },
    opacity,
    cornerRadius: {
      topLeft: animatedOrBase(animation.cornerRadius, toNumber(style.cornerRadiusTopLeft ?? style.cornerRadius, 0)),
      topRight: animatedOrBase(animation.cornerRadius, toNumber(style.cornerRadiusTopRight ?? style.cornerRadius, 0)),
      bottomRight: animatedOrBase(animation.cornerRadius, toNumber(style.cornerRadiusBottomRight ?? style.cornerRadius, 0)),
      bottomLeft: animatedOrBase(animation.cornerRadius, toNumber(style.cornerRadiusBottomLeft ?? style.cornerRadius, 0)),
    },
    crop: style.crop,
    blendMode: style.blendMode || "source-over",
    filters: {
      ...filters,
      brightness: Math.max(0, animatedOrBase(animation.brightness, toNumber(filters.brightness, 1)) * (2 ** animatedOrBase(animation.exposure, toNumber(filters.exposure, 0)))),
      contrast: Math.max(0, animatedOrBase(animation.contrast, toNumber(filters.contrast, 1))),
      saturation: Math.max(0, animatedOrBase(animation.saturation, toNumber(filters.saturation, 1))),
      exposure: animatedOrBase(animation.exposure, toNumber(filters.exposure, 0)),
      hue: animatedOrBase(animation.hue, toNumber(filters.hue, 0)),
      blur: Math.max(0, animatedOrBase(animation.blur, toNumber(filters.blur, 0))),
      grayscale: clamp01(animatedOrBase(animation.grayscale, toNumber(filters.grayscale, 0)), 0),
      sepia: clamp01(animatedOrBase(animation.sepia, toNumber(filters.sepia, 0)), 0),
      invert: clamp01(animatedOrBase(animation.invert, toNumber(filters.invert, 0)), 0),
    },
    effects: style.effects,
    normalizedEffects: normalizeHyperFrameEffects(style, layer.id),
    motion: {
      velocityX,
      velocityY,
      speed: Math.hypot(velocityX, velocityY),
      angularVelocityDegrees: (rotationDegrees - previousRotationDegrees) * frameRate,
      scaleVelocityX: (scaleX - previousScaleX) * frameRate,
      scaleVelocityY: (scaleY - previousScaleY) * frameRate,
      skewVelocityX: (skewXDegrees - previousSkewXDegrees) * frameRate,
      skewVelocityY: (skewYDegrees - previousSkewYDegrees) * frameRate,
      opacityVelocity: (opacity - previousOpacity) * frameRate,
    },
    muted: layer.muted,
  };
};

export const createHyperFrameFrameDescriptorPlan = (ir: HyperFrameIR): HyperFrameFrameDescriptorPlan => ({
  version: 1,
  evaluator: "hyperframe-ir-frame-descriptor",
  revision: ir.revision,
  deterministic: true,
  layerCount: ir.layers.length,
  contracts: ir.contracts,
});

export const evaluateHyperFrameFrameDescriptor = (
  ir: HyperFrameIR,
  time: number,
  options: HyperFrameFrameDescriptorEvaluationOptions = {},
): HyperFrameFrameDescriptor => {
  const requestedTime = clamp(toNumber(time, 0), 0, ir.durationSeconds);
  const frameIndex = secondsToHyperFrameIndex(requestedTime, ir.fps);
  const descriptorTime = options.subframe
    ? requestedTime
    : clamp(hyperFrameIndexToSeconds(frameIndex, ir.fps), 0, ir.durationSeconds);
  const layers = ir.layers
    .map((layer) => evaluateLayerDescriptor(ir, layer, descriptorTime, frameIndex, options))
    .filter((layer): layer is HyperFrameFrameDescriptorLayer => Boolean(layer))
    .sort((a, b) => a.zIndex - b.zIndex);

  return {
    version: 1,
    revision: ir.revision,
    time: descriptorTime,
    frameIndex,
    frameTime: descriptorTime,
    frameDurationSeconds: ir.contracts.frameTiming.frameDurationSeconds,
    fps: ir.fps,
    contracts: ir.contracts,
    composition: ir.composition,
    activeLayerIds: layers.map((layer) => layer.id),
    layers,
  };
};

export const evaluateHyperFrameSubframeDescriptor = (
  ir: HyperFrameIR,
  time: number,
): HyperFrameFrameDescriptor => (
  evaluateHyperFrameFrameDescriptor(ir, time, { subframe: true })
);
