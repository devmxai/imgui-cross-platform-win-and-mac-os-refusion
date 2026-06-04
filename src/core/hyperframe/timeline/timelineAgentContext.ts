import type {
  WorkspaceAsset,
  WorkspaceComposition,
  WorkspaceTimeline,
  WorkspaceTimelineClip,
  WorkspaceTimelineTrack,
} from "../contracts/projectTypes";
import { clipFrameRange, snapTimeToFrame } from "./timelineFrameMath";
import type { TimelineOperationDiagnostic } from "./timelineOperationTypes";

export type TimelineAgentContextLayer = {
  clipId: string;
  trackId: string;
  zIndex: number;
  type: WorkspaceTimelineClip["type"];
  assetId?: string;
  name: string;
  hidden: boolean;
  muted: boolean;
  timing: {
    start: number;
    end: number;
    duration: number;
    trimIn: number;
    mediaStart: number;
    mediaEnd: number;
    startFrame: number;
    endFrame: number;
    durationFrames: number;
  };
  canvas: {
    x: number;
    y: number;
    width: number;
    height: number;
    right: number;
    bottom: number;
    centerX: number;
    centerY: number;
    anchorX: number;
    anchorY: number;
    rotation: number;
    scaleX: number;
    scaleY: number;
  };
  asset?: {
    duration?: number;
    fileName: string;
    height?: number;
    name: string;
    path: string;
    type: WorkspaceAsset["type"];
    width?: number;
  };
  diagnostics: TimelineOperationDiagnostic[];
};

export type TimelineAgentContext = {
  version: 1;
  generatedAt: string;
  timelineUpdatedAt: string;
  composition: {
    width: number;
    height: number;
    fps: number;
    durationSeconds: number;
  };
  framePolicy: {
    range: "half-open";
    startFrame: "inclusive";
    endFrame: "exclusive";
  };
  layers: TimelineAgentContextLayer[];
  diagnostics: TimelineOperationDiagnostic[];
};

const numberOr = (value: unknown, fallback: number): number => {
  const numeric = Number(value);
  return Number.isFinite(numeric) ? numeric : fallback;
};

const createLayerDiagnostics = (
  clip: WorkspaceTimelineClip,
  track: WorkspaceTimelineTrack,
  asset: WorkspaceAsset | undefined,
): TimelineOperationDiagnostic[] => {
  const diagnostics: TimelineOperationDiagnostic[] = [];
  if (clip.trackId !== track.id && track.kind !== "background") {
    diagnostics.push({
      clipId: clip.id,
      code: "agent-context-track-id-mismatch",
      message: `Clip trackId "${clip.trackId}" does not match owning track "${track.id}".`,
      severity: "warning",
      trackId: track.id,
    });
  }
  if ((clip.type === "video" || clip.type === "image" || clip.type === "audio") && !clip.assetId) {
    diagnostics.push({
      clipId: clip.id,
      code: "agent-context-missing-asset-id",
      message: `Media clip "${clip.name}" has no assetId.`,
      severity: "error",
      trackId: track.id,
    });
  }
  if (clip.assetId && !asset) {
    diagnostics.push({
      clipId: clip.id,
      code: "agent-context-asset-not-found",
      message: `Clip "${clip.name}" references missing assetId "${clip.assetId}".`,
      severity: "error",
      trackId: track.id,
    });
  }
  return diagnostics;
};

export const createTimelineAgentContext = (
  timeline: WorkspaceTimeline,
  composition: WorkspaceComposition,
  assets: WorkspaceAsset[] = [],
): TimelineAgentContext => {
  const assetById = new Map(assets.map((asset) => [asset.id, asset]));
  const diagnostics: TimelineOperationDiagnostic[] = [];
  const layers: TimelineAgentContextLayer[] = [];
  let zIndex = 0;

  for (const track of timeline.tracks) {
    for (const clip of track.clips) {
      const asset = clip.assetId ? assetById.get(clip.assetId) : undefined;
      const style = clip.style;
      const x = numberOr(style.x, 0);
      const y = numberOr(style.y, 0);
      const width = Math.max(1, numberOr(style.width, composition.width));
      const height = Math.max(1, numberOr(style.height, composition.height));
      const anchorX = numberOr(style.anchorX, 0.5);
      const anchorY = numberOr(style.anchorY, 0.5);
      const start = snapTimeToFrame(clip.start, composition.fps);
      const duration = Math.max(1 / Math.max(1, composition.fps), snapTimeToFrame(clip.duration, composition.fps));
      const end = snapTimeToFrame(start + duration, composition.fps);
      const trimIn = snapTimeToFrame(clip.trimIn, composition.fps);
      const mediaStart = trimIn;
      const mediaEnd = snapTimeToFrame(trimIn + duration, composition.fps);
      const frameRange = clipFrameRange(start, duration, composition.fps);
      const layerDiagnostics = createLayerDiagnostics(clip, track, asset);
      diagnostics.push(...layerDiagnostics);
      layers.push({
        asset: asset ? {
          duration: asset.duration,
          fileName: asset.fileName,
          height: asset.height,
          name: asset.name,
          path: asset.path,
          type: asset.type,
          width: asset.width,
        } : undefined,
        assetId: clip.assetId,
        canvas: {
          anchorX,
          anchorY,
          bottom: y + height,
          centerX: x + width * anchorX,
          centerY: y + height * anchorY,
          height,
          right: x + width,
          rotation: numberOr(style.rotation, 0),
          scaleX: numberOr(style.scaleX, 1),
          scaleY: numberOr(style.scaleY, 1),
          width,
          x,
          y,
        },
        clipId: clip.id,
        diagnostics: layerDiagnostics,
        hidden: Boolean(track.isHidden),
        muted: Boolean(track.isMuted),
        name: clip.name,
        timing: {
          duration,
          durationFrames: frameRange.durationFrames,
          end,
          endFrame: frameRange.endFrame,
          mediaEnd,
          mediaStart,
          start,
          startFrame: frameRange.startFrame,
          trimIn,
        },
        trackId: track.id,
        type: clip.type,
        zIndex,
      });
      zIndex += 1;
    }
  }

  return {
    version: 1,
    generatedAt: new Date().toISOString(),
    timelineUpdatedAt: timeline.updatedAt,
    composition: {
      durationSeconds: composition.durationSeconds,
      fps: composition.fps,
      height: composition.height,
      width: composition.width,
    },
    diagnostics,
    framePolicy: {
      endFrame: "exclusive",
      range: "half-open",
      startFrame: "inclusive",
    },
    layers,
  };
};
