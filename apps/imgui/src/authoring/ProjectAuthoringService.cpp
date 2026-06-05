#include "authoring/ProjectAuthoringService.hpp"
#include "timeline/TimelineTruth.hpp"

#include <algorithm>
#include <cerrno>
#include <chrono>
#include <cstdio>
#include <cstdint>
#include <ctime>
#include <fstream>
#include <iomanip>
#include <random>
#include <sstream>
#include <stdexcept>
#include <system_error>
#include <unordered_set>

#include <nlohmann/json.hpp>

#ifdef _WIN32
#include <windows.h>
#endif

namespace makelab::authoring {
namespace {

using Json = nlohmann::json;
namespace fs = std::filesystem;

std::string IsoNow() {
  const auto now = std::chrono::system_clock::now();
  const std::time_t value = std::chrono::system_clock::to_time_t(now);
  std::tm utc{};
#ifdef _WIN32
  gmtime_s(&utc, &value);
#else
  gmtime_r(&value, &utc);
#endif
  std::ostringstream out;
  out << std::put_time(&utc, "%Y-%m-%dT%H:%M:%SZ");
  return out.str();
}

std::string MakeId(const std::string& prefix) {
  static std::mt19937_64 generator(std::random_device{}());
  std::ostringstream out;
  out << prefix << "_" << std::hex << std::setw(12) << std::setfill('0') << (generator() & 0xffffffffffffULL);
  return out.str();
}

Json ReadJson(const fs::path& path) {
  std::ifstream input(path);
  if (!input) {
    throw std::runtime_error("Required project file is missing: " + path.string());
  }
  Json value;
  input >> value;
  return value;
}

void WriteJsonAtomic(const fs::path& path, const Json& value) {
  const fs::path temporary = path.string() + ".authoring.tmp";
  {
    std::ofstream output(temporary, std::ios::trunc);
    if (!output) {
      throw std::runtime_error("Cannot create transactional project file: " + temporary.string());
    }
    output << std::setw(2) << value << '\n';
    output.flush();
    if (!output) {
      throw std::runtime_error("Cannot flush transactional project file: " + temporary.string());
    }
  }
#ifdef _WIN32
  if (!MoveFileExW(temporary.c_str(), path.c_str(), MOVEFILE_REPLACE_EXISTING | MOVEFILE_WRITE_THROUGH)) {
    const std::error_code error(static_cast<int>(GetLastError()), std::system_category());
    fs::remove(temporary);
    throw std::runtime_error("Cannot atomically replace project file: " + path.string() + " (" + error.message() + ")");
  }
#else
  if (std::rename(temporary.c_str(), path.c_str()) != 0) {
    const std::error_code error(errno, std::generic_category());
    fs::remove(temporary);
    throw std::runtime_error("Cannot atomically replace project file: " + path.string() + " (" + error.message() + ")");
  }
#endif
}

double Number(const Json& value, const char* key, double fallback) {
  if (!value.contains(key) || !value[key].is_number()) {
    return fallback;
  }
  return value[key].get<double>();
}

bool HasNumber(const Json& value, const char* key) {
  return value.contains(key) && value[key].is_number();
}

int64_t Integer(const Json& value, const char* key, int64_t fallback) {
  if (!HasNumber(value, key)) {
    return fallback;
  }
  return std::max<int64_t>(0, static_cast<int64_t>(std::llround(value[key].get<double>())));
}

std::string String(const Json& value, const char* key, const std::string& fallback = {}) {
  if (!value.contains(key) || !value[key].is_string()) {
    return fallback;
  }
  return value[key].get<std::string>();
}

Json DefaultStyle(double x, double y, double width, double height, const std::string& fit = "contain") {
  return {
      {"x", x},
      {"y", y},
      {"width", width},
      {"height", height},
      {"anchorX", 0.5},
      {"anchorY", 0.5},
      {"opacity", 1.0},
      {"rotation", 0.0},
      {"scaleX", 1.0},
      {"scaleY", 1.0},
      {"skewX", 0.0},
      {"skewY", 0.0},
      {"cornerRadius", 0.0},
      {"fit", fit},
      {"fill", {{"enabled", false}, {"color", "#FFFFFF"}, {"opacity", 1.0}}},
      {"border", {{"enabled", false}, {"width", 0.0}, {"color", "#FFFFFF"}, {"opacity", 1.0}, {"position", "inside"}}},
      {"shadow", {{"enabled", false}, {"x", 0.0}, {"y", 0.0}, {"blur", 0.0}, {"spread", 0.0}, {"color", "#000000"}, {"opacity", 1.0}}},
      {"effects", Json::object()},
      {"motion", {{"preset", "none"}, {"inDuration", 0.0}, {"outDuration", 0.0}, {"easing", "easeOut"}}},
  };
}

struct ProjectFiles {
  Json composition;
  Json manifest;
  Json timeline;
};

makelab::timeline::FrameRate ProjectRate(const ProjectFiles& files);
int64_t ProjectDurationFrames(const ProjectFiles& files);
int64_t ClipStartFrame(const Json& clip, makelab::timeline::FrameRate rate);
int64_t ClipDurationFrames(const Json& clip, makelab::timeline::FrameRate rate);
int64_t ClipTrimInFrame(const Json& clip, makelab::timeline::FrameRate rate);
void StampTimelineTimebase(ProjectFiles& files);

ProjectFiles ReadProject(const fs::path& workspace) {
  return {
      ReadJson(workspace / "composition.json"),
      ReadJson(workspace / "assets/assets.json"),
      ReadJson(workspace / "timeline.json"),
  };
}

std::vector<std::string> ValidateCandidate(const fs::path& workspace, const ProjectFiles& files) {
  std::vector<std::string> diagnostics;
  const auto rate = ProjectRate(files);
  const int64_t projectDurationFrames = ProjectDurationFrames(files);
  if (Number(files.composition, "width", 0.0) <= 0.0 ||
      Number(files.composition, "height", 0.0) <= 0.0 ||
      Number(files.composition, "fps", 0.0) <= 0.0 ||
      Number(files.composition, "durationSeconds", 0.0) <= 0.0) {
    diagnostics.push_back("blocked-invalid-composition: composition dimensions, fps, and duration must be positive.");
  }

  const Json assets = files.manifest.value("assets", Json::array());
  const Json tracks = files.timeline.value("tracks", Json::array());
  std::unordered_set<std::string> assetIds;
  for (const Json& asset : assets) {
    const std::string id = String(asset, "id");
    const std::string type = String(asset, "type");
    const std::string path = String(asset, "path");
    if (id.empty() || !assetIds.insert(id).second) {
      diagnostics.push_back("blocked-invalid-asset-id: asset IDs must be present and unique.");
    }
    if (type != "video" && type != "image" && type != "audio") {
      diagnostics.push_back("blocked-invalid-asset-type: imported assets must be video, image, or audio.");
    }
    if (path.empty() || !fs::exists(workspace / path)) {
      diagnostics.push_back("blocked-missing-asset-file: every imported asset must exist inside the project.");
    }
  }

  for (const Json& track : tracks) {
    const std::string trackId = String(track, "id");
    const std::string trackKind = String(track, "kind");
    for (const Json& clip : track.value("clips", Json::array())) {
      const std::string clipId = String(clip, "id");
      const std::string clipType = String(clip, "type");
      const int64_t startFrame = ClipStartFrame(clip, rate);
      const int64_t durationFrames = ClipDurationFrames(clip, rate);
      const int64_t trimInFrame = ClipTrimInFrame(clip, rate);
      if (clipId.empty() || startFrame < 0 || durationFrames <= 0) {
        diagnostics.push_back("blocked-invalid-clip: clips require an ID, non-negative startFrame, and positive durationFrames.");
      }
      if (startFrame + durationFrames > projectDurationFrames) {
        diagnostics.push_back("blocked-clip-outside-composition: clips must end within the accepted composition duration.");
      }
      if (trimInFrame < 0) {
        diagnostics.push_back("blocked-invalid-trim: trimInFrame must be non-negative.");
      }
      if (String(clip, "trackId") != trackId) {
        diagnostics.push_back("blocked-track-mismatch: clip.trackId must match its owning track.");
      }
      if (clipType == "video" || clipType == "image" || clipType == "audio") {
        const std::string assetId = String(clip, "assetId");
        if (assetId.empty() || !assetIds.contains(assetId)) {
          diagnostics.push_back("blocked-missing-asset-id: media clips must reference an accepted asset.");
        }
      }
      if (clipType == "background" && trackKind != "background") {
        diagnostics.push_back("blocked-background-track: background clips must use the background track.");
      }
    }
  }
  return diagnostics;
}

AuthoringResult CommitTimeline(const fs::path& workspace, ProjectFiles files, const std::string& createdId, const std::string& message) {
  StampTimelineTimebase(files);
  files.timeline["updatedAt"] = IsoNow();
  const std::vector<std::string> diagnostics = ValidateCandidate(workspace, files);
  if (!diagnostics.empty()) {
    return {false, "UnitedGate blocked authoring command.", {}, diagnostics};
  }
  WriteJsonAtomic(workspace / "timeline.json", files.timeline);
  return {true, message, createdId, {}};
}

Json& Tracks(Json& timeline) {
  if (!timeline.contains("tracks") || !timeline["tracks"].is_array()) {
    timeline["tracks"] = Json::array();
  }
  return timeline["tracks"];
}

void AddTrackWithClip(Json& timeline, Json clip, const std::string& kind, const std::string& name) {
  const std::string trackId = String(clip, "trackId");
  Json track = {
      {"id", trackId},
      {"name", name},
      {"kind", kind},
      {"isHidden", false},
      {"isMuted", false},
      {"clips", Json::array({std::move(clip)})},
  };
  Tracks(timeline).insert(Tracks(timeline).begin(), std::move(track));
}

std::pair<double, double> CompositionSize(const ProjectFiles& files) {
  return {Number(files.composition, "width", 1080.0), Number(files.composition, "height", 1920.0)};
}

double ProjectDuration(const ProjectFiles& files) {
  return Number(files.composition, "durationSeconds", Number(files.timeline, "durationSeconds", 13.26));
}

makelab::timeline::FrameRate ProjectRate(const ProjectFiles& files) {
  if (files.timeline.contains("timebase") && files.timeline["timebase"].is_object()) {
    const Json rate = files.timeline["timebase"].value("rate", Json::object());
    const int64_t numerator = Integer(rate, "numerator", 0);
    const int64_t denominator = Integer(rate, "denominator", 0);
    if (numerator > 0 && denominator > 0) {
      return makelab::timeline::NormalizeRate({numerator, denominator});
    }
  }
  return makelab::timeline::FrameRateFromFps(Number(files.composition, "fps", Number(files.timeline, "fps", 30.0)));
}

int64_t ProjectDurationFrames(const ProjectFiles& files) {
  const auto rate = ProjectRate(files);
  const int64_t canonical = Integer(files.timeline, "durationFrames", 0);
  if (canonical > 0) {
    return canonical;
  }
  return std::max<int64_t>(1, makelab::timeline::SecondsToFrameRound(ProjectDuration(files), rate));
}

double ToSeconds(int64_t frame, makelab::timeline::FrameRate rate) {
  return makelab::timeline::FrameToSeconds({frame}, rate);
}

int64_t ClipStartFrame(const Json& clip, makelab::timeline::FrameRate rate) {
  if (HasNumber(clip, "startFrame")) {
    return Integer(clip, "startFrame", 0);
  }
  return makelab::timeline::SecondsToFrameRound(Number(clip, "start", 0.0), rate);
}

int64_t ClipDurationFrames(const Json& clip, makelab::timeline::FrameRate rate) {
  if (HasNumber(clip, "durationFrames")) {
    return std::max<int64_t>(1, Integer(clip, "durationFrames", 1));
  }
  return std::max<int64_t>(1, makelab::timeline::SecondsToFrameRound(Number(clip, "duration", 0.0), rate));
}

int64_t ClipTrimInFrame(const Json& clip, makelab::timeline::FrameRate rate) {
  if (HasNumber(clip, "trimInFrame")) {
    return Integer(clip, "trimInFrame", 0);
  }
  return makelab::timeline::SecondsToFrameRound(Number(clip, "trimIn", 0.0), rate);
}

void ApplyCanonicalTiming(Json& clip,
                          int64_t startFrame,
                          int64_t durationFrames,
                          int64_t trimInFrame,
                          makelab::timeline::FrameRate rate) {
  startFrame = std::max<int64_t>(0, startFrame);
  durationFrames = std::max<int64_t>(1, durationFrames);
  trimInFrame = std::max<int64_t>(0, trimInFrame);
  clip["startFrame"] = startFrame;
  clip["durationFrames"] = durationFrames;
  clip["trimInFrame"] = trimInFrame;
  clip["start"] = ToSeconds(startFrame, rate);
  clip["duration"] = ToSeconds(durationFrames, rate);
  clip["trimIn"] = ToSeconds(trimInFrame, rate);
}

std::pair<int64_t, int64_t> StartAndDurationFrames(const ProjectFiles& files,
                                                   int64_t requestedStartFrame,
                                                   int64_t requestedDurationFrames) {
  const int64_t projectDuration = std::max<int64_t>(1, ProjectDurationFrames(files));
  const int64_t start = std::clamp<int64_t>(requestedStartFrame, 0, std::max<int64_t>(0, projectDuration - 1));
  const int64_t duration = std::clamp<int64_t>(std::max<int64_t>(1, requestedDurationFrames), 1, projectDuration - start);
  return {start, duration};
}

void StampTimelineTimebase(ProjectFiles& files) {
  const auto rate = ProjectRate(files);
  files.timeline["timebase"] = {
      {"rate", {{"numerator", rate.numerator}, {"denominator", rate.denominator}}},
      {"rangePolicy", "half-open"},
  };
  files.timeline["durationFrames"] = ProjectDurationFrames(files);
}

}  // namespace

AuthoringResult ProjectAuthoringService::importAsset(const fs::path& workspace,
                                                     const fs::path& source,
                                                     const ImportedAssetMetadata& metadata) const {
  try {
    if (!fs::exists(source) || !fs::is_regular_file(source)) {
      return {false, "ImportAsset blocked: selected source file does not exist.", {}, {}};
    }
    if (metadata.type != "video" && metadata.type != "image" && metadata.type != "audio") {
      return {false, "ImportAsset blocked: unsupported media type.", {}, {}};
    }
    ProjectFiles files = ReadProject(workspace);
    const std::string assetId = MakeId("asset");
    const std::string extension = source.extension().string();
    const std::string targetName = assetId + extension;
    const fs::path target = workspace / "assets/originals" / targetName;
    fs::create_directories(target.parent_path());
    fs::copy_file(source, target, fs::copy_options::overwrite_existing);
    try {
      if (!files.manifest.contains("assets") || !files.manifest["assets"].is_array()) {
        files.manifest["assets"] = Json::array();
      }
      Json asset = {
          {"id", assetId},
          {"type", metadata.type},
          {"name", source.stem().string()},
          {"fileName", source.filename().string()},
          {"path", (fs::path("assets/originals") / targetName).generic_string()},
          {"size", static_cast<std::uintmax_t>(fs::file_size(target))},
          {"createdAt", IsoNow()},
      };
      if (metadata.width > 0) asset["width"] = metadata.width;
      if (metadata.height > 0) asset["height"] = metadata.height;
      if (metadata.durationSeconds > 0.0) asset["duration"] = metadata.durationSeconds;
      if (metadata.fps > 0.0) asset["fps"] = metadata.fps;
      files.manifest["assets"].push_back(std::move(asset));
      files.manifest["updatedAt"] = IsoNow();
      const std::vector<std::string> diagnostics = ValidateCandidate(workspace, files);
      if (!diagnostics.empty()) {
        fs::remove(target);
        return {false, "UnitedGate blocked ImportAsset.", {}, diagnostics};
      }
      WriteJsonAtomic(workspace / "assets/assets.json", files.manifest);
      return {true, "Asset imported into the accepted project library.", assetId, {}};
    } catch (...) {
      fs::remove(target);
      throw;
    }
  } catch (const std::exception& error) {
    return {false, std::string("ImportAsset failed: ") + error.what(), {}, {}};
  }
}

AuthoringResult ProjectAuthoringService::addAssetClip(const fs::path& workspace,
                                                      const std::string& assetId,
                                                      int64_t startFrame) const {
  try {
    ProjectFiles files = ReadProject(workspace);
    const Json assets = files.manifest.value("assets", Json::array());
    const auto asset = std::find_if(assets.begin(), assets.end(), [&](const Json& item) { return String(item, "id") == assetId; });
    if (asset == assets.end()) {
      return {false, "AddAssetClip blocked: asset was not found in assets/assets.json.", {}, {}};
    }
    const std::string type = String(*asset, "type");
    const auto [compositionWidth, compositionHeight] = CompositionSize(files);
    const double width = std::max(1.0, Number(*asset, "width", compositionWidth));
    const double height = std::max(1.0, Number(*asset, "height", compositionHeight));
    const double scale = std::min(compositionWidth / width, compositionHeight / height);
    const double layerWidth = width * scale;
    const double layerHeight = height * scale;
    const auto rate = ProjectRate(files);
    const int64_t requestedDurationFrames = type == "image"
                                                ? makelab::timeline::SecondsToFrameRound(5.0, rate)
                                                : std::max<int64_t>(1, makelab::timeline::SecondsToFrameRound(
                                                                          std::max(Number(*asset, "duration", ProjectDuration(files)), 1.0),
                                                                          rate));
    const auto [start, duration] = StartAndDurationFrames(files, startFrame, requestedDurationFrames);
    const std::string clipId = MakeId("clip");
    const std::string trackId = MakeId("track");
    Json clip = {
        {"id", clipId},
        {"name", String(*asset, "name", type)},
        {"type", type},
        {"assetId", assetId},
        {"trackId", trackId},
        {"style", DefaultStyle((compositionWidth - layerWidth) * 0.5, (compositionHeight - layerHeight) * 0.5,
                               layerWidth, layerHeight, type == "video" ? "cover" : "contain")},
    };
    ApplyCanonicalTiming(clip, start, duration, 0, rate);
    AddTrackWithClip(files.timeline, std::move(clip), type, String(*asset, "name", type));
    return CommitTimeline(workspace, std::move(files), clipId, "Asset clip added through UnitedGate.");
  } catch (const std::exception& error) {
    return {false, std::string("AddAssetClip failed: ") + error.what(), {}, {}};
  }
}

AuthoringResult ProjectAuthoringService::addTextLayer(const fs::path& workspace,
                                                      const std::string& preset,
                                                      int64_t startFrame) const {
  try {
    ProjectFiles files = ReadProject(workspace);
    const auto [width, height] = CompositionSize(files);
    const std::string clipId = MakeId("text");
    const std::string trackId = MakeId("track");
    const auto rate = ProjectRate(files);
    const auto [start, duration] = StartAndDurationFrames(files, startFrame, makelab::timeline::SecondsToFrameRound(5.0, rate));
    const double fontSize = preset == "title" ? 104.0 : preset == "caption" ? 44.0 : 72.0;
    const std::string content = preset == "title" ? "Title" : preset == "caption" ? "Caption" : "Text";
    Json style = DefaultStyle(width * 0.1, height * 0.42, width * 0.8, std::max(140.0, fontSize * 1.8), "contain");
    style["fill"] = {{"enabled", true}, {"color", "#FFFFFF"}, {"opacity", 1.0}};
    Json clip = {
        {"id", clipId}, {"name", content}, {"type", "text"}, {"trackId", trackId},
        {"style", std::move(style)},
        {"text", {{"content", content}, {"fontFamily", "Inter"}, {"fontSize", fontSize}, {"fontWeight", "400"},
                  {"color", "#FFFFFF"}, {"align", "center"}}},
    };
    ApplyCanonicalTiming(clip, start, duration, 0, rate);
    AddTrackWithClip(files.timeline, std::move(clip), "text", content);
    return CommitTimeline(workspace, std::move(files), clipId, "Text layer added through UnitedGate.");
  } catch (const std::exception& error) {
    return {false, std::string("AddTextLayer failed: ") + error.what(), {}, {}};
  }
}

AuthoringResult ProjectAuthoringService::addBackgroundLayer(const fs::path& workspace,
                                                            const std::string& color,
                                                            int64_t startFrame) const {
  try {
    ProjectFiles files = ReadProject(workspace);
    const auto [width, height] = CompositionSize(files);
    const auto rate = ProjectRate(files);
    const auto [start, duration] = StartAndDurationFrames(files, startFrame, ProjectDurationFrames(files));
    Json& tracks = Tracks(files.timeline);
    auto backgroundTrack = std::find_if(tracks.begin(), tracks.end(), [](const Json& track) {
      return String(track, "kind") == "background";
    });
    if (backgroundTrack == tracks.end()) {
      Json track = {{"id", "background"}, {"name", "Background"}, {"kind", "background"},
                    {"isHidden", false}, {"isMuted", false}, {"clips", Json::array()}};
      tracks.push_back(std::move(track));
      backgroundTrack = std::prev(tracks.end());
    }
    const std::string clipId = MakeId("background");
    Json style = DefaultStyle(0.0, 0.0, width, height, "fill");
    style["fill"] = {{"enabled", true}, {"color", color}, {"opacity", color == "#00000000" ? 0.0 : 1.0}};
    Json clip = {
        {"id", clipId}, {"name", color == "#00000000" ? "Transparent Background" : "Solid Background"},
        {"type", "background"}, {"trackId", String(*backgroundTrack, "id", "background")},
        {"style", std::move(style)},
    };
    ApplyCanonicalTiming(clip, start, duration, 0, rate);
    (*backgroundTrack)["clips"].push_back(std::move(clip));
    return CommitTimeline(workspace, std::move(files), clipId, "Background layer added through UnitedGate.");
  } catch (const std::exception& error) {
    return {false, std::string("AddBackgroundLayer failed: ") + error.what(), {}, {}};
  }
}

AuthoringResult ProjectAuthoringService::addShapeLayer(const fs::path& workspace,
                                                       const std::string& shapeKind,
                                                       int64_t startFrame) const {
  try {
    static const std::unordered_set<std::string> accepted{"rectangle", "circle", "line", "arrow"};
    if (!accepted.contains(shapeKind)) {
      return {false, "AddShapeLayer blocked: unsupported shape kind.", {}, {}};
    }
    ProjectFiles files = ReadProject(workspace);
    const auto [width, height] = CompositionSize(files);
    const std::string clipId = MakeId("shape");
    const std::string trackId = MakeId("track");
    const auto rate = ProjectRate(files);
    const auto [start, duration] = StartAndDurationFrames(files, startFrame, makelab::timeline::SecondsToFrameRound(5.0, rate));
    const double shapeWidth = shapeKind == "line" || shapeKind == "arrow" ? width * 0.55 : width * 0.35;
    const double shapeHeight = shapeKind == "line" || shapeKind == "arrow" ? 24.0 : width * 0.35;
    Json style = DefaultStyle((width - shapeWidth) * 0.5, (height - shapeHeight) * 0.5, shapeWidth, shapeHeight, "contain");
    style["fill"] = {{"enabled", true}, {"color", "#66C7FF"}, {"opacity", 1.0}};
    style["cornerRadius"] = shapeKind == "rectangle" ? 36.0 : 0.0;
    Json clip = {
        {"id", clipId}, {"name", shapeKind}, {"type", "shape"}, {"trackId", trackId},
        {"style", std::move(style)},
        {"shape", {{"kind", shapeKind}}},
    };
    ApplyCanonicalTiming(clip, start, duration, 0, rate);
    AddTrackWithClip(files.timeline, std::move(clip), "shape", shapeKind);
    return CommitTimeline(workspace, std::move(files), clipId, "Shape layer added through UnitedGate.");
  } catch (const std::exception& error) {
    return {false, std::string("AddShapeLayer failed: ") + error.what(), {}, {}};
  }
}

}  // namespace makelab::authoring
