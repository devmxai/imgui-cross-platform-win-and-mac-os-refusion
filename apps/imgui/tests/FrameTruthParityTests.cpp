#include "query/FrameQueryService.hpp"

#include <cassert>
#include <cmath>
#include <cstdint>

using makelab::imgui::ClipItem;
using makelab::imgui::TrackItem;
using makelab::imgui::WorkspaceViewState;
using makelab::query::CreateCanvasViewTransform;
using makelab::query::FrameTruthFingerprint;
using makelab::query::QueryFrame;
using makelab::query::ViewportToComposition;

namespace {

WorkspaceViewState BuildWorkspace() {
  WorkspaceViewState workspace;
  workspace.opened = true;
  workspace.width = 1920;
  workspace.height = 1080;
  workspace.fps = 29.97;
  workspace.frameRate = makelab::timeline::FrameRateFromFps(workspace.fps);
  workspace.durationFrames = 300;
  workspace.durationSeconds = makelab::timeline::FrameToSeconds({workspace.durationFrames}, workspace.frameRate);

  ClipItem background;
  background.id = "bg_solid";
  background.name = "Background";
  background.type = "background";
  background.trackId = "track_bg";
  background.startFrame = 0;
  background.durationFrames = 300;
  background.fillEnabled = true;
  background.fillColor = "#101820";

  ClipItem video;
  video.id = "video_primary";
  video.name = "Primary Video";
  video.type = "video";
  video.trackId = "track_video";
  video.assetId = "asset_video";
  video.startFrame = 30;
  video.durationFrames = 150;
  video.trimInSeconds = 0.5;
  video.x = 240.0;
  video.y = 120.0;
  video.width = 960.0;
  video.height = 540.0;
  video.cornerRadius = 24.0;
  video.borderEnabled = true;
  video.shadowEnabled = true;
  video.effects.push_back({"fx_blur", "gaussianBlur", "gaussianBlur", true, {{"radius", 3.0}}, {}});
  video.effects.push_back({"fx_tile", "motionTile", "motionTile", true, {{"outputWidth", 120.0}}, {{"mode", "mirror"}}});

  ClipItem text;
  text.id = "text_title";
  text.name = "Title";
  text.type = "text";
  text.trackId = "track_text";
  text.startFrame = 90;
  text.durationFrames = 60;
  text.x = 400.0;
  text.y = 820.0;
  text.width = 600.0;
  text.height = 120.0;
  text.textContent = "Frame Truth";
  text.animationFrames.push_back({"opacity", 0.0, 0.0, "linear"});
  text.animationFrames.push_back({"opacity", 1.0, 1.0, "linear"});

  ClipItem shape;
  shape.id = "shape_badge";
  shape.name = "Badge";
  shape.type = "shape";
  shape.trackId = "track_shape";
  shape.startFrame = 100;
  shape.durationFrames = 80;
  shape.x = 1300.0;
  shape.y = 220.0;
  shape.width = 220.0;
  shape.height = 220.0;
  shape.shapeKind = "circle";
  shape.fillEnabled = true;
  shape.cornerRadius = 110.0;
  shape.shadowEnabled = true;

  workspace.tracks.push_back({"track_text", "Text", "text", false, false, {text}});
  workspace.tracks.push_back({"track_shape", "Shape", "shape", false, false, {shape}});
  workspace.tracks.push_back({"track_video", "Video", "video", false, false, {video}});
  workspace.tracks.push_back({"track_bg", "Background", "background", false, false, {background}});
  return workspace;
}

}  // namespace

int main() {
  const auto workspace = BuildWorkspace();

  const int64_t frame = 105;
  const auto agentTruth = QueryFrame(workspace, frame);
  const auto previewTruth = QueryFrame(workspace, frame);
  const auto exportTruth = QueryFrame(workspace, frame);
  assert(FrameTruthFingerprint(agentTruth) == FrameTruthFingerprint(previewTruth));
  assert(FrameTruthFingerprint(previewTruth) == FrameTruthFingerprint(exportTruth));
  assert(agentTruth.layers.size() == 4);

  const auto beforeText = QueryFrame(workspace, 89);
  const auto firstText = QueryFrame(workspace, 90);
  const auto afterText = QueryFrame(workspace, 150);
  assert(FrameTruthFingerprint(beforeText) != FrameTruthFingerprint(firstText));
  assert(FrameTruthFingerprint(firstText) != FrameTruthFingerprint(afterText));

  int textFrameCount = 0;
  int videoFrameCount = 0;
  for (int64_t exportFrame = 0; exportFrame < workspace.durationFrames; ++exportFrame) {
    const auto truth = QueryFrame(workspace, exportFrame);
    const uint64_t previewHash = FrameTruthFingerprint(QueryFrame(workspace, exportFrame));
    const uint64_t exportHash = FrameTruthFingerprint(truth);
    assert(previewHash == exportHash);
    for (const auto& layer : truth.layers) {
      if (layer.clipId == "text_title") ++textFrameCount;
      if (layer.clipId == "video_primary") ++videoFrameCount;
    }
  }
  assert(textFrameCount == 60);
  assert(videoFrameCount == 150);

  const auto transform = CreateCanvasViewTransform(1920, 1080, 800, 800);
  const auto topLeft = ViewportToComposition(transform, {0.0, 175.0});
  assert(std::abs(topLeft.x - 0.0) < 0.5);
  assert(std::abs(topLeft.y - 0.0) < 0.5);

  return 0;
}
