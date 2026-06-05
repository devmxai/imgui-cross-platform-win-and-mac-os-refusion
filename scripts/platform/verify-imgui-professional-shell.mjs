import { createHash } from 'node:crypto';
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { fileURLToPath } from 'node:url';
import { join } from 'node:path';

const root = fileURLToPath(new URL('../../', import.meta.url));
const appRoot = join(root, 'apps/imgui');
const iconFontPath = join(appRoot, 'assets/fonts/fa-solid-900.otf');
const iconLicensePath = join(appRoot, 'third_party/font-awesome/LICENSE.txt');
const expectedIconFontSha256 = 'c1091147299a846195bbca8b26528de6c9af842f236e7db44a1c2e8c9df52372';
const uiFontPath = join(appRoot, 'assets/fonts/Inter-Regular.ttf');
const uiFontLicensePath = join(appRoot, 'third_party/inter/LICENSE.txt');
const expectedUiFontSha256 = '40d692fce188e4471e2b3cba937be967878f631ad3ebbbdcd587687c7ebe0c82';

const forbiddenTokens = [
  'WebView',
  'WKWebView',
  'QWebEngine',
  'MediaPlayer',
  'AVPlayer',
  'Canvas fallback',
  'HTMLCanvasElement',
];

const requiredTokens = [
  'FinalFrameSurface',
  'Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph',
  '--design-fixture',
  'Preview blocked',
  'OpenProject',
  'ImportMedia',
  'ImportAudio',
  'AddAssetClip',
  'AddTextLayer',
  'AddBackgroundLayer',
  'AddShapeLayer',
  'SelectLibrarySection',
  'ProjectAuthoringService',
  'FrameQueryService',
  'QueryFrame',
  'QueryLayerAtPixel',
  'CreateCanvasViewTransform',
  'NativeFinalFrameSurfaceExporter',
  'ExportMp4',
  'Export completed from FinalFrameSurface',
  'updateLiveScopeFromAcceptedSurface',
  'DrawLiveScope',
  'LiveScopeSnapshot',
  'PerformanceTelemetry',
  'DrawPerformanceTelemetry',
  'FrameTruthFingerprint',
  'FrameToClockTimecode',
  'frame-truth-parity-tests',
  '--pixel-parity-smoke',
  'RunPixelParitySmoke',
  'HashBGRA8Pixels',
  'Pixel parity smoke passed',
  '--performance-smoke',
  'RunPerformanceSmoke',
  'Performance smoke passed',
  '--scrub-performance-smoke',
  'RunScrubPerformanceSmoke',
  'Scrub performance smoke passed',
  'final-frame-surface-heavy-fx-pixel-parity-smoke',
  'final-frame-surface-heavy-fx-performance-smoke',
  'final-frame-surface-heavy-fx-scrub-performance-smoke',
  'heavy-fx-workspace',
  'final-frame-surface-svg-asset-pixel-parity-smoke',
  'final-frame-surface-svg-asset-performance-smoke',
  'svg-asset-workspace',
  'lunasvg::lunasvg',
  'svgTexture',
  'prewarmStaticImageTextures',
  'prewarmGeneratedVisualTextures',
  'prewarmVideoTextures',
  'prewarmScrubVideoWindow',
  'prewarmLayerActivationFrames',
  'activeStartSeconds',
  'CubicBezierEasedProgress',
  'scheduleFinalFrameRenderWithScrubPrewarm',
  '_renderQueue',
  'requestedFrameIndex',
  'WorkspaceSourceSignature',
  '_openProjectPanelInFlight',
  'completeOpenProjectFolder',
  'beginSheetModalForWindow',
  'FSEventStreamCreate',
  'reloadAcceptedWorkspaceFromDisk',
  'invalidateProjectResources',
  'UnitedGate preserved the previous accepted project state',
  'RequestExport',
  'BeginPlayback',
  'FinalFrameSurfaceResult',
  'FinalFrameSurfaceStatus::Accepted',
  'FinalFrameSurfaceStatus::Preserved',
  'FinalFrameSurfaceStatus::Rejected',
  'requestGeneration',
  'mac_preview_shape_fragment',
  'drawDropShadow',
  'drawBorder',
  'cornerRadii',
  'IconGlyphs.hpp',
  'fa-solid-900.otf',
  'Font Awesome Free 7.2.0',
  'Inter-Regular.ttf',
];

function collectFiles(dir) {
  return readdirSync(dir).flatMap((entry) => {
    const path = join(dir, entry);
    const stat = statSync(path);
    if (stat.isDirectory()) {
      if (entry === 'build') return [];
      return collectFiles(path);
    }
    return [path];
  });
}

const files = collectFiles(appRoot).filter((path) => /\.(md|txt|cmake|cpp|hpp|h|mm)$/.test(path) || path.endsWith('CMakeLists.txt'));
const corpus = files.map((path) => readFileSync(path, 'utf8')).join('\n');

for (const token of forbiddenTokens) {
  if (corpus.includes(token)) {
    throw new Error(`IMGUI Professional shell contains forbidden token: ${token}`);
  }
}

for (const token of requiredTokens) {
  if (!corpus.includes(token)) {
    throw new Error(`IMGUI Professional shell is missing required token: ${token}`);
  }
}

if (!existsSync(iconFontPath) || !existsSync(iconLicensePath)) {
  throw new Error('IMGUI Professional shell is missing the vendored Font Awesome icon font or its license.');
}
if (!existsSync(uiFontPath) || !existsSync(uiFontLicensePath)) {
  throw new Error('IMGUI Professional shell is missing the vendored Inter Regular UI font or its license.');
}

const iconFontSha256 = createHash('sha256').update(readFileSync(iconFontPath)).digest('hex');
if (iconFontSha256 !== expectedIconFontSha256) {
  throw new Error(`IMGUI Professional icon font checksum changed: ${iconFontSha256}`);
}
const uiFontSha256 = createHash('sha256').update(readFileSync(uiFontPath)).digest('hex');
if (uiFontSha256 !== expectedUiFontSha256) {
  throw new Error(`IMGUI Professional UI font checksum changed: ${uiFontSha256}`);
}

const editorShell = readFileSync(join(appRoot, 'src/ui/EditorShell.cpp'), 'utf8');
const editorShellHeader = readFileSync(join(appRoot, 'src/ui/EditorShell.hpp'), 'utf8');
if (editorShell.includes('std::filesystem') || editorShell.includes('nlohmann::json')) {
  throw new Error('IMGUI UI must remain command/display only and may not write project files.');
}
for (const forbiddenUiClock of ['CACurrentMediaTime', 'std::chrono', 'ImGui::GetTime']) {
  if (editorShell.includes(forbiddenUiClock) || editorShellHeader.includes(forbiddenUiClock)) {
    throw new Error(`IMGUI UI must not own clock truth: ${forbiddenUiClock}`);
  }
}
if (editorShell.includes('timelineTimeSeconds') || editorShellHeader.includes('timelineTimeSeconds')) {
  throw new Error('IMGUI UI scrub commands must be frame-only and must not emit timelineTimeSeconds.');
}
if (editorShell.includes('FormatClock(')) {
  throw new Error('Transport timecode must be formatted from frame indices, not UI-owned seconds.');
}
if (!editorShell.includes('FrameToClockTimecode')) {
  throw new Error('Transport display must use TimelineTruth FrameToClockTimecode.');
}
if (editorShell.includes('asset-open-folder-plus')) {
  throw new Error('The asset library add tile must import an asset, not open a project folder.');
}
for (const legacyPlaceholder of ['"AC"', '"UD"', '"PLAY"', '"::"']) {
  if (editorShell.includes(legacyPlaceholder)) {
    throw new Error(`IMGUI Professional shell contains a legacy placeholder icon: ${legacyPlaceholder}`);
  }
}

const macApp = readFileSync(join(appRoot, 'src/platform/macos/MacApp.mm'), 'utf8');
if (macApp.includes('timelineTimeSeconds')) {
  throw new Error('Native command bridge must not accept timelineTimeSeconds from UI commands.');
}
if (!macApp.includes('- (void)openProjectFolder') ||
    !macApp.includes('beginSheetModalForWindow:self.window') ||
    !macApp.includes('completeOpenProjectFolder:panel.URL')) {
  throw new Error('Open Folder must show the native folder picker asynchronously before loading a project.');
}
if (macApp.includes('id<MTLTexture> render(const makelab::imgui::WorkspaceViewState& workspace')) {
  throw new Error('Platform renderer must return FinalFrameSurfaceResult, not a raw texture pointer.');
}
if (!macApp.includes('result.accepted()')) {
  throw new Error('Accepted playhead/frame updates must be gated by FinalFrameSurfaceResult::accepted().');
}
if (!macApp.includes('acceptRequestedFrame(result.requestGeneration)')) {
  throw new Error('Accepted playhead/frame updates must reject stale render generations.');
}
if (macApp.includes('Export blocked until FinalFrameSurface exporter is connected')) {
  throw new Error('Export must be connected to FinalFrameSurface, not left as a placeholder.');
}
if (!macApp.includes('executor.render(workspace, frameIndex') || !macApp.includes('frame.accepted()')) {
  throw new Error('Export must iterate FinalFrameSurfaceResult frames and reject non-accepted frames.');
}
if (!macApp.includes('copyTextureBGRA8')) {
  throw new Error('FinalFrameSurface readback must go through the native Metal blit readback helper.');
}
if (macApp.includes('getBytes:bgra.data')) {
  throw new Error('FinalFrameSurface readback must not call getBytes directly on a GPU-private texture.');
}
if (!macApp.includes('_liveScopeReadbackInFlight') || !macApp.includes('addCompletedHandler')) {
  throw new Error('Live Scope must use asynchronous FinalFrameSurface readback and must not block playback/scrub.');
}
if (macApp.includes('copyTextureBGRA8(_finalFrameSurface')) {
  throw new Error('Live Scope must not use the synchronous export readback helper on the playback path.');
}
if (!editorShell.includes('DrawPerformanceTelemetry') || !editorShell.includes('renderSubmitMs')) {
  throw new Error('The native shell must expose performance telemetry from the platform adapter.');
}

console.log('IMGUI Professional shell verification passed. UI remains command/display only.');
