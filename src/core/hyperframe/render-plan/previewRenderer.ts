import type { HyperFrameIR, HyperFramePreviewRendererJob } from "../contracts/types";
import { layerHasActiveEffects } from "../fx/effects";

export const createPreviewRendererJob = (ir: HyperFrameIR): HyperFramePreviewRendererJob => ({
  version: 1,
  target: "preview",
  executionContract: "hyperframe-ir-frame-descriptor",
  surfaceContract: "deterministic-final-frame-surface",
  revision: ir.revision,
  composition: ir.composition,
  layerOrder: ir.layers.map((layer) => layer.id),
  mediaLayerIds: ir.layers
    .filter((layer) => Boolean(layer.asset))
    .map((layer) => layer.id),
  cacheLayerIds: ir.layers
    .filter((layer) => layer.kind === "shape" || layer.kind === "text")
    .map((layer) => layer.id),
  effectLayerIds: ir.layers.filter(layerHasActiveEffects).map((layer) => layer.id),
  deterministicCanvas: true,
});
