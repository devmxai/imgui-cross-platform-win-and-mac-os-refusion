import type { WorkspaceTimelineClip } from "../contracts/projectTypes";
import { validateMotionFxCapabilities } from "../fx/motionFxCapabilities";
import type { HyperFrameGateIssue, HyperFrameTransactionGateResult, HyperFrameTransactionInput } from "../contracts/types";

const mediaClipTypes = new Set<WorkspaceTimelineClip["type"]>(["image", "video", "audio"]);

const stableHash = (value: unknown) => {
  const text = JSON.stringify(value);
  let hash = 2166136261;
  for (let index = 0; index < text.length; index += 1) {
    hash ^= text.charCodeAt(index);
    hash = Math.imul(hash, 16777619);
  }
  return (hash >>> 0).toString(16).padStart(8, "0");
};

export const createHyperFrameRevision = (input: HyperFrameTransactionInput) => stableHash({
  composition: input.composition,
  assets: input.assets.map((asset) => ({
    id: asset.id,
    type: asset.type,
    path: asset.path,
    width: asset.width,
    height: asset.height,
    duration: asset.duration,
    fps: asset.fps,
  })),
  timeline: input.timeline,
  sceneLengths: {
    html: input.scene.indexHtml.length,
    css: input.scene.css.length,
    js: input.scene.js.length,
  },
});

export const validateHyperFrameTransaction = (input: HyperFrameTransactionInput): HyperFrameTransactionGateResult => {
  const assetIds = new Set(input.assets.map((asset) => asset.id));
  const issues: HyperFrameGateIssue[] = [];

  if (input.composition.width <= 0 || input.composition.height <= 0 || input.composition.fps <= 0) {
    issues.push({
      severity: "error",
      code: "invalid-composition",
      message: "Composition width, height, and fps must be positive before building a HyperFrame plan.",
    });
  }

  for (const track of input.timeline.tracks) {
    for (const clip of track.clips) {
      if (clip.start < 0 || clip.duration <= 0) {
        issues.push({
          severity: "error",
          code: "invalid-clip-timing",
          message: "Timeline clips must have non-negative start and positive duration.",
          clipId: clip.id,
          trackId: track.id,
        });
      }

      if (mediaClipTypes.has(clip.type) && !clip.assetId) {
        issues.push({
          severity: "error",
          code: "missing-asset-id",
          message: "Media clips must reference a real assetId.",
          clipId: clip.id,
          trackId: track.id,
        });
      }

      if (clip.assetId && !assetIds.has(clip.assetId)) {
        issues.push({
          severity: "error",
          code: "unknown-asset-id",
          message: "Timeline clip references an assetId that is not present in assets/assets.json.",
          clipId: clip.id,
          trackId: track.id,
          assetId: clip.assetId,
        });
      }

      if (clip.type === "background" && clip.trackId !== "background") {
        issues.push({
          severity: "warning",
          code: "background-track-mismatch",
          message: "Background clips should stay on the shared background track.",
          clipId: clip.id,
          trackId: track.id,
        });
      }
    }
  }

  issues.push(...validateMotionFxCapabilities({
    intent: input.intent,
    composition: input.composition,
    tracks: input.timeline.tracks,
  }));

  return {
    accepted: !issues.some((issue) => issue.severity === "error"),
    revision: createHyperFrameRevision(input),
    source: input.source,
    intent: input.intent,
    issues,
  };
};
