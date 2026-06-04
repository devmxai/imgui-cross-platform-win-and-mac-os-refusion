import type {
  WorkspaceTimeline,
  WorkspaceTimelineClip,
  WorkspaceTimelineTrack,
} from "../contracts/projectTypes";
import { clampTimelineTime, frameDurationSeconds, snapTimeToFrame } from "./timelineFrameMath";
import type {
  TimelineCompositionInfo,
  TimelineOperation,
  TimelineOperationDiagnostic,
  TimelineOperationOptions,
  TimelineOperationResult,
} from "./timelineOperationTypes";

type ClipLocation = {
  clip: WorkspaceTimelineClip;
  clipIndex: number;
  track: WorkspaceTimelineTrack;
  trackIndex: number;
};

const cloneTimeline = (timeline: WorkspaceTimeline): WorkspaceTimeline => ({
  ...timeline,
  tracks: timeline.tracks.map((track) => ({
    ...track,
    clips: track.clips.map((clip) => ({ ...clip, style: { ...clip.style } })),
  })),
});

const findClip = (timeline: WorkspaceTimeline, clipId: string): ClipLocation | null => {
  for (let trackIndex = 0; trackIndex < timeline.tracks.length; trackIndex += 1) {
    const track = timeline.tracks[trackIndex];
    const clipIndex = track.clips.findIndex((clip) => clip.id === clipId);
    if (clipIndex >= 0) return { clip: track.clips[clipIndex], clipIndex, track, trackIndex };
  }
  return null;
};

const defaultCreateClipId = () => `clip_${Math.random().toString(36).slice(2, 10)}`;

const defaultCreateTrackId = (clipId: string) => `track_${clipId}`;

const addDiagnostic = (
  diagnostics: TimelineOperationDiagnostic[],
  diagnostic: TimelineOperationDiagnostic,
): void => {
  diagnostics.push(diagnostic);
};

const minimumDuration = (composition: TimelineCompositionInfo): number => (
  frameDurationSeconds(composition.fps)
);

const removeEmptyNonBackgroundTracks = (tracks: WorkspaceTimelineTrack[]): WorkspaceTimelineTrack[] => (
  tracks.filter((track) => track.kind === "background" || track.clips.length > 0)
);

const replaceClip = (
  timeline: WorkspaceTimeline,
  location: ClipLocation,
  nextClip: WorkspaceTimelineClip,
): void => {
  timeline.tracks[location.trackIndex] = {
    ...location.track,
    clips: location.track.clips.map((clip, index) => (index === location.clipIndex ? nextClip : clip)),
  };
};

const operationError = (
  timeline: WorkspaceTimeline,
  operation: TimelineOperation,
  message: string,
): TimelineOperationResult => ({
  timeline,
  changedClipIds: [],
  createdClipIds: [],
  deletedClipIds: [],
  selectedClipId: operation.kind === "deleteClip" ? null : operation.clipId,
  diagnostics: [{
    clipId: operation.clipId,
    code: "timeline-operation-invalid",
    message,
    severity: "error",
  }],
});

const clampStartForClip = (
  startSeconds: number,
  clip: WorkspaceTimelineClip,
  composition: TimelineCompositionInfo,
): number => {
  const maxStart = Math.max(0, composition.durationSeconds - Math.max(minimumDuration(composition), clip.duration));
  return Math.max(0, Math.min(maxStart, snapTimeToFrame(startSeconds, composition.fps)));
};

export const applyTimelineOperation = (
  inputTimeline: WorkspaceTimeline,
  composition: TimelineCompositionInfo,
  operation: TimelineOperation,
  options: TimelineOperationOptions = {},
): TimelineOperationResult => {
  const timeline = cloneTimeline(inputTimeline);
  const diagnostics: TimelineOperationDiagnostic[] = [];
  const location = findClip(timeline, operation.clipId);
  if (!location) return operationError(timeline, operation, "Selected timeline clip was not found.");

  const fps = Math.max(1, composition.fps || timeline.fps || 30);
  const minimum = minimumDuration({ ...composition, fps });
  const end = location.clip.start + location.clip.duration;

  if (operation.kind === "moveClip") {
    const start = clampStartForClip(operation.start, location.clip, { ...composition, fps });
    const nextClip = { ...location.clip, start };
    replaceClip(timeline, location, nextClip);
    return {
      timeline,
      changedClipIds: [nextClip.id],
      createdClipIds: [],
      deletedClipIds: [],
      selectedClipId: nextClip.id,
      diagnostics,
    };
  }

  if (operation.kind === "trimClipLeft") {
    const trimTime = clampTimelineTime(operation.time, composition.durationSeconds, fps);
    if (trimTime <= location.clip.start + minimum || trimTime >= end - minimum) {
      return operationError(timeline, operation, "Trim start must remain inside the selected clip.");
    }
    const removed = trimTime - location.clip.start;
    const nextClip = {
      ...location.clip,
      duration: snapTimeToFrame(end - trimTime, fps),
      start: trimTime,
      trimIn: snapTimeToFrame(location.clip.trimIn + removed, fps),
    };
    replaceClip(timeline, location, nextClip);
    return {
      timeline,
      changedClipIds: [nextClip.id],
      createdClipIds: [],
      deletedClipIds: [],
      selectedClipId: nextClip.id,
      diagnostics,
    };
  }

  if (operation.kind === "trimClipRight") {
    const trimTime = clampTimelineTime(operation.time, composition.durationSeconds, fps);
    if (trimTime <= location.clip.start + minimum || trimTime >= end - minimum) {
      return operationError(timeline, operation, "Trim end must remain inside the selected clip.");
    }
    const nextClip = {
      ...location.clip,
      duration: snapTimeToFrame(trimTime - location.clip.start, fps),
    };
    replaceClip(timeline, location, nextClip);
    return {
      timeline,
      changedClipIds: [nextClip.id],
      createdClipIds: [],
      deletedClipIds: [],
      selectedClipId: nextClip.id,
      diagnostics,
    };
  }

  if (operation.kind === "splitClip") {
    const splitTime = clampTimelineTime(operation.time, composition.durationSeconds, fps);
    if (splitTime <= location.clip.start + minimum || splitTime >= end - minimum) {
      return operationError(timeline, operation, "Split time must be inside the selected clip.");
    }
    const leftDuration = snapTimeToFrame(splitTime - location.clip.start, fps);
    const rightDuration = snapTimeToFrame(end - splitTime, fps);
    const newClipId = operation.newClipId ?? options.createClipId?.() ?? defaultCreateClipId();
    const leftClip = {
      ...location.clip,
      duration: leftDuration,
    };
    const rightClip = {
      ...location.clip,
      duration: rightDuration,
      id: newClipId,
      name: `${location.clip.name} split`,
      start: splitTime,
      trimIn: snapTimeToFrame(location.clip.trimIn + leftDuration, fps),
    };
    timeline.tracks[location.trackIndex] = {
      ...location.track,
      clips: [
        ...location.track.clips.slice(0, location.clipIndex),
        leftClip,
        rightClip,
        ...location.track.clips.slice(location.clipIndex + 1),
      ],
    };
    return {
      timeline,
      changedClipIds: [leftClip.id],
      createdClipIds: [rightClip.id],
      deletedClipIds: [],
      selectedClipId: rightClip.id,
      diagnostics,
    };
  }

  if (operation.kind === "duplicateClip") {
    const newClipId = operation.newClipId ?? options.createClipId?.() ?? defaultCreateClipId();
    const nextTrackId = operation.newTrackId
      ?? options.createTrackId?.(newClipId, location.clip)
      ?? defaultCreateTrackId(newClipId);
    const start = clampStartForClip(location.clip.start + location.clip.duration, location.clip, { ...composition, fps });
    const duplicate: WorkspaceTimelineClip = {
      ...location.clip,
      id: newClipId,
      name: `${location.clip.name} copy`,
      start,
      trackId: nextTrackId,
    };
    const track: WorkspaceTimelineTrack = {
      id: nextTrackId,
      name: duplicate.name,
      kind: location.track.kind,
      clips: [duplicate],
    };
    timeline.tracks = [track, ...timeline.tracks];
    return {
      timeline,
      changedClipIds: [],
      createdClipIds: [duplicate.id],
      deletedClipIds: [],
      selectedClipId: duplicate.id,
      diagnostics,
    };
  }

  if (operation.kind === "deleteClip") {
    const nextTracks = timeline.tracks.map((track, index) => (
      index === location.trackIndex
        ? { ...track, clips: track.clips.filter((clip) => clip.id !== location.clip.id) }
        : track
    ));
    timeline.tracks = removeEmptyNonBackgroundTracks(nextTracks);
    const nextClip = timeline.tracks.flatMap((track) => track.clips)[0] ?? null;
    return {
      timeline,
      changedClipIds: [],
      createdClipIds: [],
      deletedClipIds: [location.clip.id],
      selectedClipId: nextClip?.id ?? null,
      diagnostics,
    };
  }

  addDiagnostic(diagnostics, {
    code: "timeline-operation-unsupported",
    message: "Unsupported timeline operation.",
    severity: "error",
  });
  return {
    timeline,
    changedClipIds: [],
    createdClipIds: [],
    deletedClipIds: [],
    selectedClipId: operation.clipId,
    diagnostics,
  };
};
