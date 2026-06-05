import { existsSync, readFileSync, readdirSync, statSync } from "node:fs";
import { fileURLToPath } from "node:url";
import { dirname, extname, join, resolve } from "node:path";

const root = fileURLToPath(new URL("../../", import.meta.url));

const requiredFiles = [
  "apps/imgui/CMakeLists.txt",
  "apps/imgui/src/authoring/ProjectAuthoringService.cpp",
  "apps/imgui/src/authoring/ProjectAuthoringService.hpp",
  "apps/imgui/src/query/FrameQueryService.cpp",
  "apps/imgui/src/query/FrameQueryService.hpp",
  "apps/imgui/src/platform/macos/MacApp.mm",
  "apps/imgui/tests/ProjectAuthoringServiceTests.cpp",
  "apps/imgui/tests/FrameQueryServiceTests.cpp",
  "apps/imgui/tests/FrameTruthParityTests.cpp",
  "apps/imgui/tests/fixtures/pixel-parity-workspace/project.json",
  "apps/imgui/tests/fixtures/pixel-parity-workspace/composition.json",
  "apps/imgui/tests/fixtures/pixel-parity-workspace/timeline.json",
  "apps/imgui/tests/fixtures/pixel-parity-workspace/assets/assets.json",
  "apps/imgui/tests/fixtures/heavy-fx-workspace/project.json",
  "apps/imgui/tests/fixtures/heavy-fx-workspace/composition.json",
  "apps/imgui/tests/fixtures/heavy-fx-workspace/timeline.json",
  "apps/imgui/tests/fixtures/heavy-fx-workspace/assets/assets.json",
  "apps/imgui/tests/fixtures/svg-asset-workspace/project.json",
  "apps/imgui/tests/fixtures/svg-asset-workspace/composition.json",
  "apps/imgui/tests/fixtures/svg-asset-workspace/timeline.json",
  "apps/imgui/tests/fixtures/svg-asset-workspace/assets/assets.json",
  "apps/imgui/tests/fixtures/svg-asset-workspace/assets/originals/svg_badge.svg",
  "apps/imgui/src/ui/EditorShell.cpp",
  "apps/imgui/src/ui/EditorShell.hpp",
  "src/core/hyperframe/project/transactionGate.ts",
  "src/core/hyperframe/project/ir.ts",
  "src/core/hyperframe/frame/frameDescriptor.ts",
  "src/core/hyperframe/fx/fxRegistry.manifest.json",
  "src/core/hyperframe/fx/effectNormalizer.ts",
  "src/core/hyperframe/fx/fxPassGraph.ts",
  "src/core/hyperframe/fx/motionBlurQualityPlanner.ts",
  "src/core/hyperframe/render-plan/canonicalFrameRequest.ts",
  "src/core/hyperframe/render-plan/qualityPolicy.ts",
  "src/core/hyperframe/render-plan/renderPlanner.ts",
  "src/core/hyperframe/render-plan/sourceSurfaceProvider.ts",
  "engine/platform/macos-reference/UnitedGate.swift",
  "engine/platform/macos-reference/CanonicalHyperFrameBridge.swift",
  "engine/platform/macos-reference/RenderGraph.swift",
  "engine/platform/macos-reference/FXPassGraph.swift",
  "engine/platform/macos-reference/FXRegistry.swift",
  "engine/platform/macos-reference/MetalFXRuntime.swift",
  "engine/platform/macos-reference/NativeRenderEngine.swift",
  "engine/platform/macos-reference/NativeRenderSurface.swift",
  "engine/platform/macos-reference/MetalRenderGraphFrameRenderer.swift",
  "engine/platform/macos-reference/MotionBlurQualityPlanner.swift",
  "engine/platform/macos-reference/NativeTimelineExporter.swift",
  "engine/platform/macos/adapter-contract.md",
  "engine/platform/macos/current-native-adapter-map.md",
  "engine/platform/windows/adapter-contract.md",
  "docs/architecture/imgui-professional-plan.md",
  "docs/engine/architecture/render-semantics.md",
  "docs/engine/architecture/fx-animation-contract.md",
  "docs/engine/architecture/platform-adapters.md",
  "docs/Professional HyperFrame FX Development Standard.md",
  "docs/PORTABLE_SOURCE_MANIFEST.md",
];

const missing = requiredFiles.filter((path) => !existsSync(join(root, path)));
if (missing.length > 0) {
  throw new Error(`Portable source is incomplete. Missing:\n${missing.join("\n")}`);
}

const forbiddenPaths = [
  "apps/qt",
  "src/platforms/web",
  "engine/platform/macos-reference/ContentView.swift",
  "engine/platform/macos-reference/MakelabMacApp.swift",
  "engine/platform/macos-reference/EditorState.swift",
];
const presentForbidden = forbiddenPaths.filter((path) => existsSync(join(root, path)));
if (presentForbidden.length > 0) {
  throw new Error(`Portable ImGui repository contains excluded UI path:\n${presentForbidden.join("\n")}`);
}

const app = readFileSync(join(root, "apps/imgui/src/platform/macos/MacApp.mm"), "utf8");
const appTokens = [
  "BuildHyperFrameIR",
  "EvaluateFrameDescriptor",
  "CompileRenderGraph",
  "CompileFXPassGraph",
  "MacMetalRenderFrameExecutor",
  "FinalFrameSurface",
  "renderMotionBlurTexture",
  "drawDropShadow",
  "drawBorder",
  "mac_preview_shape_fragment",
  "svgTexture",
  "prewarmStaticImageTextures",
  "prewarmGeneratedVisualTextures",
  "prewarmVideoTextures",
  "prewarmScrubVideoWindow",
  "prewarmLayerActivationFrames",
  "activeStartSeconds",
  "CubicBezierEasedProgress",
  "scheduleFinalFrameRenderWithScrubPrewarm",
  "requestedFrameIndex",
  "lunasvg::Document",
];
for (const token of appTokens) {
  if (!app.includes(token)) {
    throw new Error(`Current ImGui application is missing required engine bridge token: ${token}`);
  }
}

const cmake = readFileSync(join(root, "apps/imgui/CMakeLists.txt"), "utf8");
if (!cmake.includes("GIT_TAG fc5e2f28fedf6bbe0d20885a5a144d1206a3474e")) {
  throw new Error("Dear ImGui dependency must remain pinned to the validated source commit.");
}
if (!cmake.includes("json/releases/download/v3.12.0/json.tar.xz") ||
    !cmake.includes("SHA256=42f6e95cad6ec532fd372391373363b62a14af6d771056dbfc86160e6dfff7aa")) {
  throw new Error("nlohmann/json dependency must remain pinned to the validated release archive and checksum.");
}
if (!cmake.includes("GIT_TAG 83c58df8103dc7dca423dfd824992af94d49bed6") ||
    !cmake.includes("lunasvg::lunasvg")) {
  throw new Error("LunaSVG dependency must remain pinned and linked for native SVG source texture support.");
}
if (!cmake.includes('"-framework CoreServices"') ||
    !cmake.includes('OUTPUT_NAME "Makelab IMGUI Professional"') ||
    !cmake.includes("install(TARGETS makelab-imgui-professional BUNDLE DESTINATION .)") ||
    !cmake.includes("frame-query-service-tests") ||
    !cmake.includes("frame-truth-parity-tests") ||
    !cmake.includes("final-frame-surface-pixel-parity-smoke") ||
    !cmake.includes("final-frame-surface-performance-smoke") ||
    !cmake.includes("final-frame-surface-heavy-fx-pixel-parity-smoke") ||
    !cmake.includes("final-frame-surface-heavy-fx-performance-smoke") ||
    !cmake.includes("final-frame-surface-heavy-fx-scrub-performance-smoke") ||
    !cmake.includes("final-frame-surface-svg-asset-pixel-parity-smoke") ||
    !cmake.includes("final-frame-surface-svg-asset-performance-smoke")) {
  throw new Error("The macOS native project watcher and persistent app installation contract are missing.");
}

const frameQuery = readFileSync(join(root, "apps/imgui/src/query/FrameQueryService.cpp"), "utf8");
for (const token of ["QueryFrame", "QueryLayerAtPixel", "CreateCanvasViewTransform", "FrameTruthFingerprint", "FrameToSeconds"]) {
  if (!frameQuery.includes(token)) {
    throw new Error(`FrameQueryService is missing required evaluated truth token: ${token}`);
  }
}

const timelineTruth = readFileSync(join(root, "apps/imgui/src/timeline/TimelineTruth.hpp"), "utf8");
if (!timelineTruth.includes("FrameToClockTimecode")) {
  throw new Error("TimelineTruth must own frame-index timecode display formatting.");
}

const coreTokens = [
  ["src/core/hyperframe/project/transactionGate.ts", "validateHyperFrameTransaction"],
  ["src/core/hyperframe/project/ir.ts", "compileHyperFrameIR"],
  ["src/core/hyperframe/frame/frameDescriptor.ts", "evaluateHyperFrameFrameDescriptor"],
  ["src/core/hyperframe/fx/fxPassGraph.ts", "createHyperFrameFxPassGraph"],
  ["src/core/hyperframe/render-plan/canonicalFrameRequest.ts", "FinalFrameSurface"],
];
for (const [path, token] of coreTokens) {
  const source = readFileSync(join(root, path), "utf8");
  if (!source.includes(token)) {
    throw new Error(`${path} is missing required token: ${token}`);
  }
}

const walkFiles = (directory) => readdirSync(directory).flatMap((entry) => {
  const path = join(directory, entry);
  return statSync(path).isDirectory() ? walkFiles(path) : [path];
});

const resolveRelativeImport = (sourcePath, specifier) => {
  const candidate = resolve(dirname(sourcePath), specifier);
  const candidates = extname(candidate)
    ? [candidate]
    : [`${candidate}.ts`, `${candidate}.json`, join(candidate, "index.ts")];
  return candidates.some((path) => existsSync(path));
};

const coreRoot = join(root, "src/core/hyperframe");
const brokenImports = [];
for (const sourcePath of walkFiles(coreRoot).filter((path) => path.endsWith(".ts"))) {
  const source = readFileSync(sourcePath, "utf8");
  const imports = source.matchAll(/from\s+["'](\.[^"']+)["']/g);
  for (const [, specifier] of imports) {
    if (!resolveRelativeImport(sourcePath, specifier)) {
      brokenImports.push(`${sourcePath.slice(root.length)} -> ${specifier}`);
    }
  }
}
if (brokenImports.length > 0) {
  throw new Error(`Portable HyperFrame Core has broken relative imports:\n${brokenImports.join("\n")}`);
}

JSON.parse(readFileSync(join(root, "src/core/hyperframe/fx/fxRegistry.manifest.json"), "utf8"));

console.log("Portable ImGui + HyperFrame source verified: Gate -> IR -> FrameDescriptor -> RenderGraph/FXPassGraph -> FinalFrameSurface.");
