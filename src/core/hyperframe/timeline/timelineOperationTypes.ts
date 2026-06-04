import type {
  WorkspaceTimeline,
  WorkspaceTimelineClip,
} from "../contracts/projectTypes";

export type TimelineOperation =
  | { kind: "moveClip"; clipId: string; start: number }
  | { kind: "trimClipLeft"; clipId: string; time: number }
  | { kind: "trimClipRight"; clipId: string; time: number }
  | { kind: "splitClip"; clipId: string; time: number; newClipId?: string }
  | { kind: "duplicateClip"; clipId: string; newClipId?: string; newTrackId?: string }
  | { kind: "deleteClip"; clipId: string };

export type TimelineOperationSeverity = "info" | "warning" | "error";

export type TimelineOperationDiagnostic = {
  code: string;
  message: string;
  severity: TimelineOperationSeverity;
  clipId?: string;
  trackId?: string;
};

export type TimelineCompositionInfo = {
  durationSeconds: number;
  fps: number;
};

export type TimelineOperationOptions = {
  createClipId?: () => string;
  createTrackId?: (clipId: string, clip: WorkspaceTimelineClip) => string;
};

export type TimelineOperationResult = {
  timeline: WorkspaceTimeline;
  changedClipIds: string[];
  createdClipIds: string[];
  deletedClipIds: string[];
  selectedClipId?: string | null;
  diagnostics: TimelineOperationDiagnostic[];
};
