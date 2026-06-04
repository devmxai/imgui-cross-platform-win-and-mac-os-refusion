import type { HyperFrameBmfExportJob, HyperFrameBmfExportNode } from "../contracts/types";

export type HyperFrameBmfSchemaIssueSeverity = "warning" | "error";

export type HyperFrameBmfSchemaIssue = {
  severity: HyperFrameBmfSchemaIssueSeverity;
  code: string;
  message: string;
  nodeId?: string;
};

export type HyperFrameBmfJobValidation = {
  valid: boolean;
  errorCount: number;
  warningCount: number;
  issues: HyperFrameBmfSchemaIssue[];
};

const requiredExportModules: HyperFrameBmfExportNode["module"][] = ["frame_stream", "encode"];

const isFinitePositive = (value: number) => Number.isFinite(value) && value > 0;

const pushIssue = (
  issues: HyperFrameBmfSchemaIssue[],
  issue: HyperFrameBmfSchemaIssue,
) => {
  issues.push(issue);
};

export const validateBmfExportJob = (job: HyperFrameBmfExportJob): HyperFrameBmfJobValidation => {
  const issues: HyperFrameBmfSchemaIssue[] = [];
  const nodeIds = new Set<string>();

  if (job.version !== 1) {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-version-unsupported",
      message: `Unsupported BMF job version ${job.version}.`,
    });
  }

  if (job.target !== "bmf" || job.source !== "hyperframe-final-frame-stream") {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-job-source-invalid",
      message: "BMF export jobs must target bmf and originate from the HyperFrame final frame stream.",
    });
  }

  if (job.executionRole !== "encode-mux-only") {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-execution-role-invalid",
      message: "BMF export jobs must declare encode-mux-only execution. BMF is not a preview, scrub, live preview, timeline, effect, or layer compositor.",
    });
  }

  if (job.visualAuthority !== "hyperframe-ir-frame-descriptor-platform-renderer") {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-visual-authority-invalid",
      message: "BMF export jobs must declare HyperFrame IR -> FrameDescriptor -> Platform Renderer as the visual authority.",
    });
  }

  if (!isFinitePositive(job.composition.width) || !isFinitePositive(job.composition.height)) {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-composition-size-invalid",
      message: "BMF job composition dimensions must be positive finite numbers.",
    });
  }

  if (!isFinitePositive(job.durationSeconds)) {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-duration-invalid",
      message: "BMF job duration must be a positive finite number.",
    });
  }

  if (!isFinitePositive(job.fps)) {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-fps-invalid",
      message: "BMF job fps must be a positive finite number.",
    });
  }

  if (job.contracts?.pixelGeometry?.coordinateSpace !== "composition-pixels" || job.contracts.pixelGeometry.origin !== "top-left") {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-pixel-contract-invalid",
      message: "BMF export requires top-left composition-pixel geometry before execution.",
    });
  }

  if (job.contracts?.frameTiming?.timeBase !== "integer-frame-index" || job.contracts.frameTiming.fps !== job.fps) {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-frame-contract-invalid",
      message: "BMF export requires integer frame timing that matches the export fps.",
    });
  }

  if (
    job.output.container !== "mp4"
    || job.output.videoCodec !== "h264"
    || job.output.audioCodec !== "aac"
    || job.output.videoSource !== "hyperframe-final-frame-stream"
    || job.output.audioSource !== "hyperframe-audio-pcm"
  ) {
    pushIssue(issues, {
      severity: "error",
      code: "bmf-output-contract-invalid",
      message: "Current BMF export contract requires HyperFrame final frames plus HyperFrame AudioPCM encoded as mp4/h264/aac output.",
    });
  }

  for (const node of job.nodes) {
    if (!node.id.trim()) {
      pushIssue(issues, {
        severity: "error",
        code: "bmf-node-id-empty",
        message: "BMF nodes must have non-empty ids.",
      });
      continue;
    }

    if (nodeIds.has(node.id)) {
      pushIssue(issues, {
        severity: "error",
        code: "bmf-node-id-duplicate",
        message: `Duplicate BMF node id ${node.id}.`,
        nodeId: node.id,
      });
    }
    nodeIds.add(node.id);

    if (!Array.isArray(node.inputs) || !Array.isArray(node.layerIds)) {
      pushIssue(issues, {
        severity: "error",
        code: "bmf-node-shape-invalid",
        message: "BMF node inputs and layerIds must be arrays.",
        nodeId: node.id,
      });
    }
  }

  const nodeById = new Map(job.nodes.map((node) => [node.id, node]));
  for (const node of job.nodes) {
    for (const inputId of node.inputs) {
      if (!nodeById.has(inputId)) {
        pushIssue(issues, {
          severity: "error",
          code: "bmf-node-input-missing",
          message: `BMF node ${node.id} references missing input ${inputId}.`,
          nodeId: node.id,
        });
      }
    }

    if (node.module === "frame_stream") {
      if (node.options.stream !== "final-composition-pixels") {
        pushIssue(issues, {
          severity: "error",
          code: "bmf-frame-stream-contract-missing",
          message: "BMF frame stream nodes must declare final-composition-pixels.",
          nodeId: node.id,
        });
      }
      if (node.options.timeBase !== "integer-frame-index") {
        pushIssue(issues, {
          severity: "error",
          code: "bmf-frame-stream-timing-missing",
          message: "BMF frame stream nodes must declare integer-frame-index timing.",
          nodeId: node.id,
        });
      }
    }

    if (node.module === "audio_pcm") {
      if (node.options.provider !== "HyperFrameAudioPcmPlan") {
        pushIssue(issues, {
          severity: "error",
          code: "bmf-audio-pcm-provider-invalid",
          message: "BMF audio nodes must consume a HyperFrameAudioPcmPlan, not timeline audio sources.",
          nodeId: node.id,
        });
      }
      if (node.options.sampleFormat !== "f32-planar") {
        pushIssue(issues, {
          severity: "error",
          code: "bmf-audio-pcm-format-invalid",
          message: "BMF audio nodes must declare f32-planar AudioPCM input.",
          nodeId: node.id,
        });
      }
    }

    if (node.module === "encode" && node.inputs.length === 0) {
      pushIssue(issues, {
        severity: "error",
        code: "bmf-node-inputs-empty",
        message: "BMF encode node has no inputs.",
        nodeId: node.id,
      });
    }
  }

  for (const module of requiredExportModules) {
    if (!job.nodes.some((node) => node.module === module)) {
      pushIssue(issues, {
        severity: "error",
        code: `bmf-${module}-missing`,
        message: `BMF export job must include a ${module} node.`,
      });
    }
  }

  const encodeNodes = job.nodes.filter((node) => node.module === "encode");
  for (const node of encodeNodes) {
    const hasFrameStreamInput = node.inputs.some((inputId) => nodeById.get(inputId)?.module === "frame_stream");
    if (!hasFrameStreamInput) {
      pushIssue(issues, {
        severity: "error",
        code: "bmf-encode-frame-stream-input-missing",
        message: "BMF encode node must consume the HyperFrame final frame stream.",
        nodeId: node.id,
      });
    }
    if (job.output.audioPolicy === "pcm") {
      const hasAudioPcmInput = node.inputs.some((inputId) => nodeById.get(inputId)?.module === "audio_pcm");
      if (!hasAudioPcmInput) {
        pushIssue(issues, {
          severity: "error",
          code: "bmf-encode-audio-pcm-input-missing",
          message: "BMF encode node must consume HyperFrame AudioPCM when audioPolicy is pcm.",
          nodeId: node.id,
        });
      }
    }
  }

  for (const forbiddenModule of ["audio_source", "audio_mix", "decode", "effects", "composite"]) {
    if (job.nodes.some((node) => String(node.module) === forbiddenModule)) {
      pushIssue(issues, {
        severity: "error",
        code: "bmf-forbidden-render-module",
        message: `BMF job contains forbidden module ${forbiddenModule}. BMF only receives FinalFrameStream + AudioPCM for encode/mux/output.`,
      });
    }
  }

  const errorCount = issues.filter((issue) => issue.severity === "error").length;
  const warningCount = issues.filter((issue) => issue.severity === "warning").length;

  return {
    valid: errorCount === 0,
    errorCount,
    warningCount,
    issues,
  };
};

export const formatBmfValidationMessages = (
  validation: HyperFrameBmfJobValidation,
): string[] => {
  if (validation.issues.length === 0) {
    return ["BMF schema validation passed."];
  }

  return validation.issues.map((issue) => (
    `${issue.severity.toUpperCase()} ${issue.code}${issue.nodeId ? ` (${issue.nodeId})` : ""}: ${issue.message}`
  ));
};
