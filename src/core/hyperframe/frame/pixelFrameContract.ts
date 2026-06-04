import type {
  HyperFrameFrameTimingContract,
  HyperFrameIRLayer,
  HyperFramePixelFrameContract,
  HyperFramePixelGeometryContract,
} from "../contracts/types";
import type { WorkspaceComposition } from "../contracts/projectTypes";

const toPositiveFps = (fps: number) => (
  Number.isFinite(fps) && fps > 0 ? fps : 30
);

export const createHyperFrameFrameTimingContract = (
  fps: number,
): HyperFrameFrameTimingContract => {
  const safeFps = toPositiveFps(fps);
  return {
    version: 1,
    timeBase: "integer-frame-index",
    fps: safeFps,
    frameDurationSeconds: 1 / safeFps,
    clipRangePolicy: "half-open-start-inclusive-end-exclusive",
    seekPolicy: "frame-indexed-deterministic",
  };
};

export const createHyperFramePixelGeometryContract = (): HyperFramePixelGeometryContract => ({
  version: 1,
  coordinateSpace: "composition-pixels",
  origin: "top-left",
  units: "px",
  rounding: "float-until-raster-boundary",
  anchorPolicy: "resolved-by-hyperframe-renderer",
  boundsPolicy: "render-before-encode",
  alpha: "premultiplied",
  colorSpace: "srgb",
  unsupportedGeometry: [],
});

export const createHyperFramePixelFrameContract = (
  composition: WorkspaceComposition,
): HyperFramePixelFrameContract => ({
  version: 1,
  pixelGeometry: createHyperFramePixelGeometryContract(),
  frameTiming: createHyperFrameFrameTimingContract(composition.fps),
});

export const secondsToHyperFrameIndex = (
  seconds: number,
  fps: number,
): number => {
  const safeFps = toPositiveFps(fps);
  const safeSeconds = Number.isFinite(seconds) ? Math.max(0, seconds) : 0;
  return Math.max(0, Math.round(safeSeconds * safeFps));
};

export const hyperFrameIndexToSeconds = (
  frameIndex: number,
  fps: number,
): number => {
  const safeFps = toPositiveFps(fps);
  const safeFrameIndex = Number.isFinite(frameIndex) ? Math.max(0, Math.round(frameIndex)) : 0;
  return safeFrameIndex / safeFps;
};

export const toHyperFrameRange = (
  startSeconds: number,
  durationSeconds: number,
  fps: number,
) => {
  const startFrame = secondsToHyperFrameIndex(startSeconds, fps);
  const durationFrames = Math.max(1, secondsToHyperFrameIndex(durationSeconds, fps));
  const endFrame = startFrame + durationFrames;
  return {
    startFrame,
    endFrame,
    durationFrames,
  };
};

export const isLayerActiveOnFrame = (
  layer: HyperFrameIRLayer,
  frameIndex: number,
  fps: number,
) => {
  const range = toHyperFrameRange(layer.timing.start, layer.timing.duration, fps);
  return frameIndex >= range.startFrame && frameIndex < range.endFrame;
};
