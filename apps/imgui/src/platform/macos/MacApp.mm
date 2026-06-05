#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreServices/CoreServices.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <VideoToolbox/VideoToolbox.h>
#import <simd/simd.h>

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"
#include "authoring/ProjectAuthoringService.hpp"
#include "ui/EditorShell.hpp"
#include "lunasvg.h"

#include <algorithm>
#include <array>
#include <atomic>
#include <cmath>
#include <cctype>
#include <cstdio>
#include <cstring>
#include <cstdlib>
#include <deque>
#include <iomanip>
#include <limits>
#include <functional>
#include <memory>
#include <sstream>
#include <unordered_map>
#include <unordered_set>
#include <string>
#include <utility>
#include <vector>

namespace {

std::string ToStdString(NSString* value) {
  if (value == nil) {
    return {};
  }
  return std::string([value UTF8String] ?: "");
}

NSString* NowIsoString() {
  NSISO8601DateFormatter* formatter = [[NSISO8601DateFormatter alloc] init];
  return [formatter stringFromDate:[NSDate date]];
}

NSString* MakeId(NSString* prefix) {
  NSString* uuid = [[[NSUUID UUID] UUIDString] stringByReplacingOccurrencesOfString:@"-" withString:@""];
  NSString* shortUuid = [uuid substringToIndex:std::min<NSUInteger>(12, uuid.length)];
  return [NSString stringWithFormat:@"%@_%@", prefix, shortUuid];
}

void EnsureDirectory(NSURL* url) {
  [[NSFileManager defaultManager] createDirectoryAtURL:url withIntermediateDirectories:YES attributes:nil error:nil];
}

void EnsureFile(NSURL* url, NSString* content) {
  if (![[NSFileManager defaultManager] fileExistsAtPath:url.path]) {
    [content writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];
  }
}

NSDictionary* ReadDictionary(NSURL* url) {
  NSData* data = [NSData dataWithContentsOfURL:url];
  if (data == nil) {
    return nil;
  }
  id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
  return [object isKindOfClass:NSDictionary.class] ? object : nil;
}

NSArray* ArrayValue(NSDictionary* dictionary, NSString* key) {
  id value = dictionary[key];
  return [value isKindOfClass:NSArray.class] ? value : @[];
}

NSDictionary* DictionaryValue(NSDictionary* dictionary, NSString* key) {
  id value = dictionary[key];
  return [value isKindOfClass:NSDictionary.class] ? value : @{};
}

std::string StringValue(NSDictionary* dictionary, NSString* key, const char* fallback = "") {
  id value = dictionary[key];
  if ([value isKindOfClass:NSString.class]) {
    return ToStdString(value);
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return ToStdString([value stringValue]);
  }
  return fallback;
}

double DoubleValue(NSDictionary* dictionary, NSString* key, double fallback = 0.0) {
  id value = dictionary[key];
  if ([value respondsToSelector:@selector(doubleValue)]) {
    return [value doubleValue];
  }
  return fallback;
}

int IntValue(NSDictionary* dictionary, NSString* key, int fallback = 0) {
  id value = dictionary[key];
  if ([value respondsToSelector:@selector(intValue)]) {
    return [value intValue];
  }
  return fallback;
}

bool BoolValue(NSDictionary* dictionary, NSString* key, bool fallback = false) {
  id value = dictionary[key];
  if ([value respondsToSelector:@selector(boolValue)]) {
    return [value boolValue];
  }
  return fallback;
}

std::string OptionalStringValue(NSDictionary* dictionary, NSString* key, const std::string& fallback) {
  if (dictionary == nil) {
    return fallback;
  }
  id value = dictionary[key];
  if ([value isKindOfClass:NSString.class]) {
    return ToStdString(value);
  }
  if ([value respondsToSelector:@selector(stringValue)]) {
    return ToStdString([value stringValue]);
  }
  return fallback;
}

bool HasObjectEntries(NSDictionary* dictionary) {
  return dictionary != nil && dictionary.count > 0;
}

std::string LowercaseAscii(std::string value) {
  std::transform(value.begin(), value.end(), value.begin(), [](unsigned char c) {
    return static_cast<char>(std::tolower(c));
  });
  return value;
}

bool IsSvgURL(NSURL* url) {
  return url != nil && LowercaseAscii(ToStdString(url.pathExtension)) == "svg";
}

std::string WorkspaceSourceSignature(NSURL* root) {
  if (root == nil) {
    return {};
  }
  NSFileManager* fileManager = [NSFileManager defaultManager];
  NSArray<NSString*>* sourcePaths = @[
    @"project.json",
    @"composition.json",
    @"timeline.json",
    @"assets/assets.json",
    @"assets/originals",
    @"native-scenes/main",
  ];
  std::vector<std::string> entries;
  auto appendFile = [&](NSURL* file) {
    NSDictionary<NSFileAttributeKey, id>* attributes = [fileManager attributesOfItemAtPath:file.path error:nil];
    if (attributes == nil || [attributes[NSFileType] isEqualToString:NSFileTypeDirectory]) {
      return;
    }
    NSString* prefix = [root.path stringByAppendingString:@"/"];
    NSString* relative = [file.path hasPrefix:prefix] ? [file.path substringFromIndex:prefix.length] : file.path;
    const unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    const NSTimeInterval modified = [attributes[NSFileModificationDate] timeIntervalSince1970];
    std::ostringstream entry;
    entry << ToStdString(relative) << ':' << std::fixed << modified << ':' << size;
    entries.push_back(entry.str());
  };

  for (NSString* relativePath in sourcePaths) {
    NSURL* source = [root URLByAppendingPathComponent:relativePath];
    BOOL isDirectory = NO;
    if (![fileManager fileExistsAtPath:source.path isDirectory:&isDirectory]) {
      continue;
    }
    if (!isDirectory) {
      appendFile(source);
      continue;
    }
    NSDirectoryEnumerator<NSURL*>* enumerator =
        [fileManager enumeratorAtURL:source
          includingPropertiesForKeys:@[NSURLIsDirectoryKey]
                             options:NSDirectoryEnumerationSkipsHiddenFiles
                        errorHandler:nil];
    for (NSURL* file in enumerator) {
      NSNumber* directory = nil;
      [file getResourceValue:&directory forKey:NSURLIsDirectoryKey error:nil];
      if (![directory boolValue]) {
        appendFile(file);
      }
    }
  }
  std::sort(entries.begin(), entries.end());
  std::ostringstream signature;
  for (const std::string& entry : entries) {
    signature << entry << '|';
  }
  return signature.str();
}

id<MTLTexture> CloneMetalTexture(id<MTLDevice> device,
                                 id<MTLCommandQueue> commandQueue,
                                 id<MTLTexture> source) {
  if (device == nil || commandQueue == nil || source == nil) {
    return nil;
  }
  MTLTextureDescriptor* descriptor =
      [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:source.pixelFormat
                                                         width:source.width
                                                        height:source.height
                                                     mipmapped:NO];
  descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
  descriptor.storageMode = MTLStorageModePrivate;
  id<MTLTexture> destination = [device newTextureWithDescriptor:descriptor];
  id<MTLCommandBuffer> commandBuffer = [commandQueue commandBuffer];
  id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
  if (destination == nil || commandBuffer == nil || blit == nil) {
    return nil;
  }
  [blit copyFromTexture:source
            sourceSlice:0
            sourceLevel:0
           sourceOrigin:MTLOriginMake(0, 0, 0)
             sourceSize:MTLSizeMake(source.width, source.height, 1)
              toTexture:destination
       destinationSlice:0
       destinationLevel:0
      destinationOrigin:MTLOriginMake(0, 0, 0)];
  [blit endEncoding];
  [commandBuffer commit];
  [commandBuffer waitUntilCompleted];
  return commandBuffer.status == MTLCommandBufferStatusCompleted ? destination : nil;
}

bool IsPositiveNumber(id value) {
  return [value respondsToSelector:@selector(doubleValue)] && [value doubleValue] > 0.0;
}

bool IsEffectEnabled(id value) {
  if ([value isKindOfClass:NSNumber.class]) {
    return [value boolValue];
  }
  if (![value isKindOfClass:NSDictionary.class]) {
    return false;
  }
  NSDictionary* effect = value;
  id enabled = effect[@"enabled"];
  if ([enabled respondsToSelector:@selector(boolValue)]) {
    return [enabled boolValue];
  }
  return IsPositiveNumber(effect[@"radius"]) ||
         IsPositiveNumber(effect[@"blur"]) ||
         IsPositiveNumber(effect[@"amount"]) ||
         IsPositiveNumber(effect[@"strength"]) ||
         IsPositiveNumber(effect[@"expansion"]) ||
         IsPositiveNumber(effect[@"expansionX"]) ||
         IsPositiveNumber(effect[@"expansionY"]) ||
         IsPositiveNumber(effect[@"outputWidth"]) ||
         IsPositiveNumber(effect[@"outputHeight"]);
}

std::string CanonicalEffectKind(const std::string& source) {
  if (source == "motionBlur") return "transformMotionBlur";
  if (source == "motionTrail") return "motionTrail";
  if (source == "motionTile" || source == "tile" || source == "mirrorTile" || source == "edgeRepeat") return "motionTile";
  if (source == "gaussianBlur" || source == "blur") return "gaussianBlur";
  if (source == "radialBlur" || source == "radialMotionBlur" || source == "spinBlur" || source == "swirlBlur") return "radialBlur";
  if (source == "zoomBlur") return "zoomBlur";
  if (source == "spiralEchoBlur" || source == "spiralBlur") return "spiralEchoBlur";
  if (source == "glowStreak") return "glowStreak";
  if (source == "chromaticSplit") return "chromaticSplit";
  if (source == "shaderTransition") return "shaderTransition";
  return "";
}

void ParseClipEffects(makelab::imgui::ClipItem& clip, NSDictionary* style) {
  NSDictionary* effects = DictionaryValue(style, @"effects");
  for (NSString* rawName in effects) {
    const std::string source = ToStdString(rawName);
    const std::string kind = CanonicalEffectKind(source);
    if (kind.empty()) {
      continue;
    }
    id rawValue = effects[rawName];
    const bool enabled = IsEffectEnabled(rawValue);
    if (!enabled) {
      continue;
    }
    makelab::imgui::ClipItem::EffectItem effect;
    effect.id = clip.id + ":" + source;
    effect.source = source;
    effect.kind = kind;
    effect.enabled = enabled;
    if ([rawValue isKindOfClass:NSDictionary.class]) {
      NSDictionary* params = rawValue;
      NSDictionary* activeRange = DictionaryValue(params, @"activeRange");
      effect.activeStartSeconds = std::max(0.0, DoubleValue(activeRange,
                                                            @"start",
                                                            DoubleValue(params, @"activeStart", 0.0)));
      effect.activeEndSeconds = DoubleValue(activeRange,
                                            @"end",
                                            DoubleValue(params,
                                                        @"activeEnd",
                                                        std::numeric_limits<double>::infinity()));
      if (!std::isfinite(effect.activeEndSeconds) || effect.activeEndSeconds <= effect.activeStartSeconds) {
        effect.activeEndSeconds = std::numeric_limits<double>::infinity();
      }
      for (NSString* rawKey in params) {
        id paramValue = params[rawKey];
        const std::string key = ToStdString(rawKey);
        if ([paramValue isKindOfClass:NSNumber.class]) {
          effect.numbers[key] = [paramValue doubleValue];
        } else if ([paramValue isKindOfClass:NSString.class]) {
          effect.strings[key] = ToStdString(paramValue);
        }
      }
    }
    clip.effects.push_back(effect);
  }
  clip.hasEffects = !clip.effects.empty();
}

std::string NormalizeAnimatedProperty(const std::string& property) {
  if (property == "x") return "positionX";
  if (property == "y") return "positionY";
  if (property == "left") return "x";
  if (property == "top") return "y";
  if (property == "centerX" || property == "cx") return "centerX";
  if (property == "centerY" || property == "cy") return "centerY";
  if (property == "tx" || property == "translate" || property == "translateX") return "translateX";
  if (property == "ty" || property == "translateY") return "translateY";
  if (property == "rotate") return "rotation";
  if (property == "radius") return "cornerRadius";
  if (property == "saturate") return "saturation";
  return property;
}

std::string ClipMotionLabel(const makelab::imgui::ClipItem& clip) {
  if (!clip.name.empty()) return clip.name;
  if (!clip.id.empty()) return clip.id;
  return "<unnamed clip>";
}

std::string FormatMotionNumber(double value, int precision = 2) {
  std::ostringstream text;
  text << std::fixed << std::setprecision(precision) << value;
  return text.str();
}

double ClipVisualExtent(const makelab::imgui::ClipItem& clip,
                        const makelab::imgui::WorkspaceViewState& workspace) {
  const double width = clip.width > 0.0 ? clip.width : workspace.width;
  const double height = clip.height > 0.0 ? clip.height : workspace.height;
  return std::max(1.0, std::max(width, height));
}

void AppendMotionQualityDiagnostics(makelab::imgui::WorkspaceViewState& state) {
  const double fps = std::max(1.0, makelab::timeline::Fps(state.frameRate));
  constexpr double kSilkyRotationDegPerFrame = 6.0;
  constexpr double kHardRotationDegPerFrame = 10.0;
  constexpr double kSilkyPixelTravelPerFrame = 18.0;
  constexpr double kHardPixelTravelPerFrame = 32.0;
  constexpr double kSilkyScalePixelsPerFrame = 24.0;
  constexpr double kHardScalePixelsPerFrame = 42.0;
  int diagnosticCount = 0;
  constexpr int kMaxDiagnostics = 8;

  auto append = [&](const std::string& message) {
    if (diagnosticCount < kMaxDiagnostics) {
      state.diagnostics.push_back(message);
    }
    ++diagnosticCount;
  };

  for (const auto& track : state.tracks) {
    for (const auto& clip : track.clips) {
      std::unordered_map<std::string, std::vector<makelab::imgui::ClipItem::AnimationFrame>> tracks;
      for (const auto& frame : clip.animationFrames) {
        tracks[frame.property].push_back(frame);
      }
      for (auto& entry : tracks) {
        auto& frames = entry.second;
        std::sort(frames.begin(), frames.end(), [](const auto& left, const auto& right) {
          return left.time < right.time;
        });
        for (size_t index = 1; index < frames.size(); ++index) {
          const auto& previous = frames[index - 1];
          const auto& next = frames[index];
          const double seconds = next.time - previous.time;
          if (!std::isfinite(seconds) || seconds <= 0.0001) {
            continue;
          }
          const double frameCount = std::max(1.0, seconds * fps);
          const double delta = std::abs(next.value - previous.value);
          if (entry.first == "rotation") {
            const double degreesPerFrame = delta / frameCount;
            if (degreesPerFrame > kSilkyRotationDegPerFrame) {
              std::string level = degreesPerFrame > kHardRotationDegPerFrame ? "hard" : "notice";
              append("MotionQuality " + level + ": clip " + ClipMotionLabel(clip) +
                     " rotates " + FormatMotionNumber(degreesPerFrame) +
                     " deg/frame at " + FormatMotionNumber(fps, 0) +
                     "fps; silky animation requires slower authored motion or a 60fps Timeline Truth.");
            }
          } else if (entry.first == "x" || entry.first == "positionX" || entry.first == "centerX" ||
                     entry.first == "translateX" || entry.first == "y" || entry.first == "positionY" ||
                     entry.first == "centerY" || entry.first == "translateY") {
            const double pixelsPerFrame = delta / frameCount;
            if (pixelsPerFrame > kSilkyPixelTravelPerFrame) {
              std::string level = pixelsPerFrame > kHardPixelTravelPerFrame ? "hard" : "notice";
              append("MotionQuality " + level + ": clip " + ClipMotionLabel(clip) +
                     " moves " + FormatMotionNumber(pixelsPerFrame) +
                     " px/frame at " + FormatMotionNumber(fps, 0) +
                     "fps; fast positional animation will not feel fully silky without higher timeline fps or retiming.");
            }
          } else if (entry.first == "scale" || entry.first == "scaleX" || entry.first == "scaleY") {
            const double pixelsPerFrame = delta * ClipVisualExtent(clip, state) / frameCount;
            if (pixelsPerFrame > kSilkyScalePixelsPerFrame) {
              std::string level = pixelsPerFrame > kHardScalePixelsPerFrame ? "hard" : "notice";
              append("MotionQuality " + level + ": clip " + ClipMotionLabel(clip) +
                     " scales about " + FormatMotionNumber(pixelsPerFrame) +
                     " px/frame at " + FormatMotionNumber(fps, 0) +
                     "fps; authoring is beyond silky preview cadence.");
            }
          }
        }
      }

      double rotationDegPerFrame = 0.0;
      auto rotationTrack = tracks.find("rotation");
      if (rotationTrack != tracks.end()) {
        for (size_t index = 1; index < rotationTrack->second.size(); ++index) {
          const double seconds = rotationTrack->second[index].time - rotationTrack->second[index - 1].time;
          if (seconds > 0.0001) {
            rotationDegPerFrame = std::max(rotationDegPerFrame,
                                           std::abs(rotationTrack->second[index].value -
                                                    rotationTrack->second[index - 1].value) /
                                               std::max(1.0, seconds * fps));
          }
        }
      }
      for (const auto& effect : clip.effects) {
        if (!effect.enabled) {
          continue;
        }
        auto effectNumber = [&](const std::string& key, double fallback) {
          auto found = effect.numbers.find(key);
          return found == effect.numbers.end() || !std::isfinite(found->second) ? fallback : found->second;
        };
        if (effect.kind == "motionTile" && rotationDegPerFrame > kSilkyRotationDegPerFrame) {
          const double expansion = std::max({1.0,
                                             effectNumber("expansion", 1.0),
                                             effectNumber("expansionX", 1.0),
                                             effectNumber("expansionY", 1.0)});
          if (expansion > 2.0) {
            append("MotionQuality notice: clip " + ClipMotionLabel(clip) +
                   " combines fast rotation with motionTile expansion " +
                   FormatMotionNumber(expansion, 1) +
                   "; playback must keep FXPassGraph and FinalFrameSurface under budget or the motion will feel heavy.");
          }
        } else if (effect.kind == "transformMotionBlur") {
          const double shutter = effectNumber("shutterAngle", effectNumber("shutter", 1.0) * 180.0);
          const double amount = effectNumber("amount", effectNumber("strength", 1.0));
          if (rotationDegPerFrame > kSilkyRotationDegPerFrame || shutter * amount > 360.0) {
            append("MotionQuality notice: clip " + ClipMotionLabel(clip) +
                   " uses transformMotionBlur on fast motion; preview/playback/export must share one FX sample plan from FXPassGraph.");
          }
        }
      }
    }
  }

  if (diagnosticCount > kMaxDiagnostics) {
    state.diagnostics.push_back("MotionQuality: " + std::to_string(diagnosticCount - kMaxDiagnostics) +
                                " additional motion diagnostics suppressed.");
  }
}

void AddAnimationFrame(makelab::imgui::ClipItem& clip,
                       const std::string& property,
                       double time,
                       double value,
                       const std::string& easing) {
  if (!std::isfinite(time) || !std::isfinite(value)) {
    return;
  }
  clip.animationFrames.push_back({NormalizeAnimatedProperty(property), time, value, easing.empty() ? clip.motionEasing : easing});
}

void AddMotionFrame(makelab::imgui::ClipItem& clip, NSDictionary* frame, const std::string& defaultEasing) {
  const double time = DoubleValue(frame, @"time", DoubleValue(frame, @"t", std::numeric_limits<double>::quiet_NaN()));
  const std::string easing = OptionalStringValue(frame, @"easing", defaultEasing);
  AddAnimationFrame(clip, "x", time, DoubleValue(frame, @"x", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "y", time, DoubleValue(frame, @"y", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "positionX", time, DoubleValue(frame, @"positionX", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "positionY", time, DoubleValue(frame, @"positionY", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "centerX", time, DoubleValue(frame, @"centerX", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "centerY", time, DoubleValue(frame, @"centerY", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "opacity", time, DoubleValue(frame, @"opacity", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "translateX", time, DoubleValue(frame, @"translateX", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "translateY", time, DoubleValue(frame, @"translateY", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "scale", time, DoubleValue(frame, @"scale", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "scaleX", time, DoubleValue(frame, @"scaleX", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "scaleY", time, DoubleValue(frame, @"scaleY", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "rotation", time, DoubleValue(frame, @"rotation", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "skewX", time, DoubleValue(frame, @"skewX", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "skewY", time, DoubleValue(frame, @"skewY", std::numeric_limits<double>::quiet_NaN()), easing);
  AddAnimationFrame(clip, "cornerRadius", time, DoubleValue(frame, @"cornerRadius", std::numeric_limits<double>::quiet_NaN()), easing);
}

void AddPresetFrame(makelab::imgui::ClipItem& clip,
                    double time,
                    std::initializer_list<std::pair<const char*, double>> values,
                    const std::string& easing,
                    const std::string& defaultEasing) {
  for (const auto& value : values) {
    AddAnimationFrame(clip, value.first, time, value.second, easing.empty() ? defaultEasing : easing);
  }
}

void AddPresetFrames(makelab::imgui::ClipItem& clip, const std::string& preset, double duration, const std::string& defaultEasing) {
  const double d = std::max(0.001, duration == 0.0 ? 0.35 : duration);
  if (preset == "fade") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}}, "", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}}, "", defaultEasing);
  } else if (preset == "pop") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"scaleX", 0.82}, {"scaleY", 0.82}}, "", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"scaleX", 1.0}, {"scaleY", 1.0}}, "", defaultEasing);
  } else if (preset == "pop-up-spin" || preset == "popUpSpin") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"scaleX", 0.18}, {"scaleY", 0.18}, {"translateY", 90.0}, {"rotation", -540.0}}, "", defaultEasing);
    AddPresetFrame(clip, d * 0.76, {{"opacity", 1.0}, {"scaleX", 1.08}, {"scaleY", 1.08}, {"translateY", 0.0}, {"rotation", 8.0}}, "easeOutBack", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"scaleX", 1.0}, {"scaleY", 1.0}, {"translateY", 0.0}, {"rotation", 0.0}}, "easeOut", defaultEasing);
  } else if (preset == "bounce-in" || preset == "bounceIn") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"scaleX", 0.18}, {"scaleY", 0.18}, {"translateY", 300.0}, {"rotation", 0.0}}, "", defaultEasing);
    AddPresetFrame(clip, d * 0.49, {{"opacity", 1.0}, {"scaleX", 1.1}, {"scaleY", 1.1}, {"translateY", 0.0}, {"rotation", -2.0}}, "easeOutBack", defaultEasing);
    AddPresetFrame(clip, d * 0.64, {{"opacity", 1.0}, {"scaleX", 0.96}, {"scaleY", 0.96}, {"translateY", 0.0}, {"rotation", 1.4}}, "easeOut", defaultEasing);
    AddPresetFrame(clip, d * 0.79, {{"opacity", 1.0}, {"scaleX", 1.025}, {"scaleY", 1.025}, {"translateY", 0.0}, {"rotation", -0.65}}, "easeOut", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"scaleX", 1.0}, {"scaleY", 1.0}, {"translateY", 0.0}, {"rotation", 0.0}}, "easeOut", defaultEasing);
  } else if (preset == "fade-up" || preset == "fadeUp") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"translateY", 72.0}}, "", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"translateY", 0.0}}, "", defaultEasing);
  } else if (preset == "slide-left") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"translateX", 96.0}}, "", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"translateX", 0.0}}, "", defaultEasing);
  } else if (preset == "slide-right") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"translateX", -96.0}}, "", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"translateX", 0.0}}, "", defaultEasing);
  } else if (preset == "slide-up") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"translateY", 96.0}}, "", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"translateY", 0.0}}, "", defaultEasing);
  } else if (preset == "slide-down") {
    AddPresetFrame(clip, 0.0, {{"opacity", 0.0}, {"translateY", -96.0}}, "", defaultEasing);
    AddPresetFrame(clip, d, {{"opacity", 1.0}, {"translateY", 0.0}}, "", defaultEasing);
  }
}

void ParseClipAnimations(makelab::imgui::ClipItem& clip, NSDictionary* clipDictionary, NSDictionary* style) {
  NSDictionary* motion = DictionaryValue(style, @"motion");
  clip.motionEasing = OptionalStringValue(motion, @"easing", "easeOut");
  clip.motionOutDuration = DoubleValue(motion, @"outDuration", 0.0);
  const std::string preset = OptionalStringValue(motion, @"preset", "none");
  if (preset != "none") {
    AddPresetFrames(clip, preset, DoubleValue(motion, @"inDuration", 0.35), clip.motionEasing);
  }
  for (id item in ArrayValue(motion, @"keyframes")) {
    if ([item isKindOfClass:NSDictionary.class]) {
      AddMotionFrame(clip, item, clip.motionEasing);
    }
  }

  NSDictionary* styleKeyframes = DictionaryValue(style, @"keyframes");
  for (NSString* rawProperty in styleKeyframes) {
    id frames = styleKeyframes[rawProperty];
    if (![frames isKindOfClass:NSArray.class]) {
      continue;
    }
    const std::string property = ToStdString(rawProperty);
    for (id item in (NSArray*)frames) {
      if (![item isKindOfClass:NSDictionary.class]) {
        continue;
      }
      NSDictionary* frame = item;
      AddAnimationFrame(clip,
                        property,
                        DoubleValue(frame, @"time", std::numeric_limits<double>::quiet_NaN()),
                        DoubleValue(frame, @"value", std::numeric_limits<double>::quiet_NaN()),
                        OptionalStringValue(frame, @"easing", clip.motionEasing));
    }
  }

  for (id item in ArrayValue(style, @"animations")) {
    if (![item isKindOfClass:NSDictionary.class]) {
      continue;
    }
    NSDictionary* animation = item;
    const std::string easing = OptionalStringValue(animation, @"easing", clip.motionEasing);
    const std::string property = StringValue(animation, @"property");
    for (id frameItem in ArrayValue(animation, @"keyframes")) {
      if (![frameItem isKindOfClass:NSDictionary.class]) {
        continue;
      }
      NSDictionary* frame = frameItem;
      if (!property.empty()) {
        AddAnimationFrame(clip,
                          property,
                          DoubleValue(frame, @"time", DoubleValue(frame, @"t", std::numeric_limits<double>::quiet_NaN())),
                          DoubleValue(frame, @"value", std::numeric_limits<double>::quiet_NaN()),
                          OptionalStringValue(frame, @"easing", easing));
      } else {
        AddMotionFrame(clip, frame, easing);
      }
    }
  }

  for (id item in ArrayValue(clipDictionary, @"keyframes")) {
    if (![item isKindOfClass:NSDictionary.class]) {
      continue;
    }
    NSDictionary* frame = item;
    AddAnimationFrame(clip,
                      StringValue(frame, @"property"),
                      DoubleValue(frame, @"time", std::numeric_limits<double>::quiet_NaN()),
                      DoubleValue(frame, @"value", std::numeric_limits<double>::quiet_NaN()),
                      OptionalStringValue(frame, @"easing", clip.motionEasing));
  }
}

struct MacPreviewVertex {
  vector_float2 position;
  vector_float2 uv;
};

struct MacMotionBlurVertex {
  vector_float2 position;
  vector_float2 uv;
  float opacity;
  float padding;
};

struct MacPreviewUniforms {
  vector_float4 tint;
  vector_float4 cornerRadii;
  vector_float2 size;
  vector_float2 uvExpansion;
  float opacity;
  float borderWidth;
  uint32_t mode;
  uint32_t shapeKind;
  uint32_t tileMode;
  uint32_t _padding;
};

struct MacMotionTileUniforms {
  vector_float2 expansion;
  uint32_t mode;
  uint32_t padding;
};

struct MacGaussianBlurUniforms {
  float radius;
  vector_float2 direction;
  float padding;
};

static NSString* const kMacPreviewMetalShader = @R"METAL(
#include <metal_stdlib>
using namespace metal;

struct MacPreviewVertex {
    float2 position;
    float2 uv;
};

struct MacMotionBlurVertex {
    float2 position;
    float2 uv;
    float opacity;
    float _padding;
};

struct MacPreviewUniforms {
    float4 tint;
    float4 cornerRadii;
    float2 size;
    float2 uvExpansion;
    float opacity;
    float borderWidth;
    uint mode;
    uint shapeKind;
    uint tileMode;
    uint _padding;
};

struct MacMotionTileUniforms {
    float2 expansion;
    uint mode;
    uint _padding;
};

struct MacGaussianBlurUniforms {
    float radius;
    float2 direction;
    float _padding;
};

struct VertexOut {
    float4 position [[position]];
    float2 uv;
    float opacity;
};

vertex VertexOut mac_preview_vertex(const device MacPreviewVertex *vertices [[buffer(0)]], uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.uv = vertices[vid].uv;
    out.opacity = 1.0;
    return out;
}

vertex VertexOut mac_motion_blur_vertex(const device MacMotionBlurVertex *vertices [[buffer(0)]], uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.uv = vertices[vid].uv;
    out.opacity = vertices[vid].opacity;
    return out;
}

float mac_rounded_rect_alpha(float2 uv, float2 size, float4 cornerRadii) {
    float radius = cornerRadii.x;
    if (uv.x >= 0.5 && uv.y < 0.5) {
        radius = cornerRadii.y;
    } else if (uv.x >= 0.5 && uv.y >= 0.5) {
        radius = cornerRadii.z;
    } else if (uv.x < 0.5 && uv.y >= 0.5) {
        radius = cornerRadii.w;
    }
    radius = clamp(radius, 0.0, min(size.x, size.y) * 0.5);
    if (radius <= 0.0) { return 1.0; }
    float2 p = (uv - 0.5) * size;
    float2 b = size * 0.5 - float2(radius);
    float2 q = abs(p) - b;
    float distance = length(max(q, float2(0.0))) + min(max(q.x, q.y), 0.0) - radius;
    return 1.0 - smoothstep(-1.0, 1.0, distance);
}

float mac_ellipse_alpha(float2 uv) {
    float distance = length((uv - 0.5) * 2.0) - 1.0;
    return 1.0 - smoothstep(-0.015, 0.015, distance);
}

float mac_line_alpha(float2 uv, float2 size) {
    float halfWidth = max(0.004, min(0.5, 1.0 / max(1.0, size.y)));
    return 1.0 - smoothstep(halfWidth, halfWidth + 0.01, abs(uv.y - 0.5));
}

float mac_arrow_alpha(float2 uv, float2 size) {
    float width = max(0.008, min(0.12, 2.0 / max(1.0, size.y)));
    float shaft = mac_line_alpha(uv, size) * (1.0 - smoothstep(0.80, 0.88, uv.x));
    float2 tip = float2(0.98, 0.5);
    float2 upper = float2(0.80, 0.28);
    float2 lower = float2(0.80, 0.72);
    float headTop = abs((uv.y - tip.y) - (upper.y - tip.y) / (upper.x - tip.x) * (uv.x - tip.x));
    float headBottom = abs((uv.y - tip.y) - (lower.y - tip.y) / (lower.x - tip.x) * (uv.x - tip.x));
    float head = (1.0 - smoothstep(width, width + 0.012, min(headTop, headBottom))) * step(0.76, uv.x);
    return max(shaft, head);
}

float mac_shape_alpha(float2 uv, float2 size, float4 cornerRadii, uint shapeKind) {
    if (shapeKind == 1) {
        return mac_ellipse_alpha(uv);
    }
    if (shapeKind == 2) {
        return mac_line_alpha(uv, size);
    }
    if (shapeKind == 3) {
        return mac_arrow_alpha(uv, size);
    }
    return mac_rounded_rect_alpha(uv, size, cornerRadii);
}

float mac_preview_repeat_coord(float value) {
    return fract(value);
}

float mac_preview_mirror_coord(float value) {
    float repeated = fmod(value, 2.0);
    if (repeated < 0.0) {
        repeated += 2.0;
    }
    return repeated <= 1.0 ? repeated : 2.0 - repeated;
}

float2 mac_preview_wrap_uv(float2 uv, uint mode) {
    if (mode == 1) {
        return float2(mac_preview_repeat_coord(uv.x), mac_preview_repeat_coord(uv.y));
    }
    if (mode == 2) {
        return clamp(uv, float2(0.0), float2(1.0));
    }
    return float2(mac_preview_mirror_coord(uv.x), mac_preview_mirror_coord(uv.y));
}

fragment float4 mac_preview_texture_fragment(VertexOut in [[stage_in]],
                                             texture2d<float> texture [[texture(0)]],
                                             constant MacPreviewUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 sampleUV = (in.uv - 0.5) * max(u.uvExpansion, float2(1.0)) + 0.5;
    sampleUV = mac_preview_wrap_uv(sampleUV, u.tileMode);
    float4 color = texture.sample(s, sampleUV) * u.tint;
    float coverage = mac_rounded_rect_alpha(in.uv, u.size, u.cornerRadii) * u.opacity * in.opacity;
    color.a *= coverage;
    color.rgb *= color.a;
    return color;
}

fragment float4 mac_preview_premultiplied_fragment(VertexOut in [[stage_in]],
                                                   texture2d<float> texture [[texture(0)]],
                                                   constant MacPreviewUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float2 sampleUV = (in.uv - 0.5) * max(u.uvExpansion, float2(1.0)) + 0.5;
    sampleUV = mac_preview_wrap_uv(sampleUV, u.tileMode);
    float4 color = texture.sample(s, sampleUV) * u.tint;
    float coverage = mac_rounded_rect_alpha(in.uv, u.size, u.cornerRadii) * u.opacity * in.opacity;
    color.rgb *= coverage;
    color.a *= coverage;
    return color;
}

fragment float4 mac_preview_shape_fragment(VertexOut in [[stage_in]],
                                           constant MacPreviewUniforms &u [[buffer(0)]]) {
    float outer = mac_shape_alpha(in.uv, u.size, u.cornerRadii, u.shapeKind);
    float alpha = outer;
    if (u.mode == 1 && u.borderWidth > 0.0) {
        float2 innerSize = max(float2(1.0), u.size - float2(u.borderWidth * 2.0));
        float2 innerUv = (in.uv - 0.5) * (u.size / innerSize) + 0.5;
        float4 innerRadii = max(float4(0.0), u.cornerRadii - float4(u.borderWidth));
        float inner = mac_shape_alpha(innerUv, innerSize, innerRadii, u.shapeKind);
        alpha = max(0.0, outer - inner);
    }
    float4 color = u.tint;
    color.a *= alpha * u.opacity;
    color.rgb *= color.a;
    return color;
}

float mac_repeat_coord(float value) {
    return fract(value);
}

float mac_mirror_coord(float value) {
    float repeated = fmod(value, 2.0);
    if (repeated < 0.0) {
        repeated += 2.0;
    }
    return repeated <= 1.0 ? repeated : 2.0 - repeated;
}

float2 mac_wrap_uv(float2 uv, uint mode) {
    if (mode == 1) {
        return float2(mac_repeat_coord(uv.x), mac_repeat_coord(uv.y));
    }
    if (mode == 2) {
        return clamp(uv, float2(0.0), float2(1.0));
    }
    return float2(mac_mirror_coord(uv.x), mac_mirror_coord(uv.y));
}

kernel void mac_fx_motion_tile(texture2d<float, access::sample> source [[texture(0)]],
                               texture2d<float, access::write> output [[texture(1)]],
                               constant MacMotionTileUniforms &uniforms [[buffer(0)]],
                               uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 outputSize = float2(output.get_width(), output.get_height());
    float2 outputUV = (float2(gid) + 0.5) / outputSize;
    float2 sourceUV = (outputUV - 0.5) * max(uniforms.expansion, float2(1.0)) + 0.5;
    output.write(source.sample(linearSampler, mac_wrap_uv(sourceUV, uniforms.mode)), gid);
}

kernel void mac_fx_gaussian_blur(texture2d<float, access::sample> source [[texture(0)]],
                                 texture2d<float, access::write> output [[texture(1)]],
                                 constant MacGaussianBlurUniforms &uniforms [[buffer(0)]],
                                 uint2 gid [[thread_position_in_grid]]) {
    if (gid.x >= output.get_width() || gid.y >= output.get_height()) {
        return;
    }
    constexpr sampler linearSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float2 size = float2(output.get_width(), output.get_height());
    float2 uv = (float2(gid) + 0.5) / size;
    float radius = max(0.0, uniforms.radius);
    if (radius < 0.01) {
        output.write(source.sample(linearSampler, uv), gid);
        return;
    }
    int sampleRadius = min(48, max(1, int(ceil(radius * 2.0))));
    float sigma = max(0.01, radius);
    float4 total = float4(0.0);
    float weightTotal = 0.0;
    for (int i = -sampleRadius; i <= sampleRadius; i++) {
        float x = float(i);
        float weight = exp(-(x * x) / (2.0 * sigma * sigma));
        float2 sampleUV = uv + uniforms.direction * x / size;
        total += source.sample(linearSampler, clamp(sampleUV, float2(0.0), float2(1.0))) * weight;
        weightTotal += weight;
    }
    output.write(total / max(weightTotal, 0.0001), gid);
}
)METAL";

class RealtimeVideoSourceProvider {
 public:
  explicit RealtimeVideoSourceProvider(NSURL* url) : url_(url) {}

  ~RealtimeVideoSourceProvider() {
    resetReader();
    releaseLastTexture();
    releaseCachedTextures();
    releaseCurrentSample();
  }

  void sync(double mediaTime, bool playing, double fps) {
    fps_ = std::max(1.0, fps);
    const double target = std::max(0.0, mediaTime);
    requestedMediaTime_ = target;
    requestedPlaying_ = playing;
  }

  void prewarm(double startMediaTime,
               double fps,
               int frameCount,
               CVMetalTextureCacheRef textureCache,
               const std::function<bool()>& shouldContinue = {}) {
    const double stableFps = std::max(1.0, fps);
    const int count = std::clamp(frameCount, 1, 360);
    for (int frame = 0; frame < count; ++frame) {
      if (shouldContinue && !shouldContinue()) {
        break;
      }
      sync(std::max(0.0, startMediaTime) + static_cast<double>(frame) / stableFps, false, stableFps);
      (void)texture(textureCache);
    }
  }

  id<MTLTexture> texture(CVMetalTextureCacheRef textureCache) {
    const double target = std::max(0.0, requestedMediaTime_);
    const int64_t requestedFrame = frameIndexForTime(target);
    const int64_t requestedSourceFrame = sourceFrameCacheKey(target);
    if (id<MTLTexture> cached = cachedTexture(requestedSourceFrame)) {
      return cached;
    }
    if (id<MTLTexture> cached = cachedTexture(requestedFrame)) {
      return cached;
    }
    if (lastTexture_ != nullptr && !requestedPlaying_ && std::abs(target - lastTextureMediaTime_) <= 0.001) {
      return CVMetalTextureGetTexture(lastTexture_);
    }
    if (reader_ == nil || shouldResetReader(target)) {
      resetReader();
      startReader(target);
    }

    CVPixelBufferRef pixelBuffer = pixelBufferForTime(target, textureCache);
    if (pixelBuffer == nullptr) {
      return nil;
    }
    const double halfFrame = std::max(0.5 / std::max(1.0, fps_), sourceFrameDuration_ * 0.5 + 0.0005);
    if (std::abs(currentSampleTime_ - target) > halfFrame) {
      return nil;
    }
    if (lastTexture_ != nullptr && std::abs(currentSampleTime_ - lastTextureSampleTime_) <= halfFrame) {
      return CVMetalTextureGetTexture(lastTexture_);
    }

    CVMetalTextureRef cvTexture = nullptr;
    CVMetalTextureCacheCreateTextureFromImage(nil,
                                              textureCache,
                                              pixelBuffer,
                                              nil,
                                              MTLPixelFormatBGRA8Unorm,
                                              CVPixelBufferGetWidth(pixelBuffer),
                                              CVPixelBufferGetHeight(pixelBuffer),
                                              0,
                                              &cvTexture);
    if (cvTexture != nullptr) {
      releaseLastTexture();
      lastTexture_ = cvTexture;
      lastTextureMediaTime_ = target;
      lastTextureSampleTime_ = currentSampleTime_;
      cacheTexture(requestedFrame, cvTexture);
      cacheTexture(sourceFrameCacheKey(currentSampleTime_), cvTexture);
      return CVMetalTextureGetTexture(lastTexture_);
    }
    return nil;
  }

 private:
  NSURL* url_ = nil;
  AVAssetReader* reader_ = nil;
  AVAssetReaderTrackOutput* output_ = nil;
  CVMetalTextureRef lastTexture_ = nullptr;
  std::unordered_map<int64_t, CVMetalTextureRef> cachedTextures_;
  std::unordered_map<int64_t, size_t> cachedTextureBytesByFrame_;
  std::deque<int64_t> cachedFrameOrder_;
  size_t cachedTextureBytes_ = 0;
  CMSampleBufferRef currentSample_ = nullptr;
  double currentSampleTime_ = -1.0;
  double lastTextureMediaTime_ = -1.0;
  double lastTextureSampleTime_ = -1.0;
  double readerStartTime_ = -1.0;
  double requestedMediaTime_ = 0.0;
  double fps_ = 30.0;
  double sourceFrameDuration_ = 1.0 / 30.0;
  double lastRequestedMediaTime_ = -1.0;
  bool requestedPlaying_ = false;
  bool readerStarted_ = false;

  void releaseLastTexture() {
    if (lastTexture_ != nullptr) {
      CFRelease(lastTexture_);
      lastTexture_ = nullptr;
    }
    lastTextureMediaTime_ = -1.0;
    lastTextureSampleTime_ = -1.0;
  }

  void releaseCachedTextures() {
    for (auto& item : cachedTextures_) {
      if (item.second != nullptr) {
        CFRelease(item.second);
      }
    }
    cachedTextures_.clear();
    cachedTextureBytesByFrame_.clear();
    cachedFrameOrder_.clear();
    cachedTextureBytes_ = 0;
  }

  int64_t frameIndexForTime(double timeSeconds) const {
    return std::max<int64_t>(0, static_cast<int64_t>(std::llround(std::max(0.0, timeSeconds) * fps_)));
  }

  int64_t sourceFrameCacheKey(double timeSeconds) const {
    const double duration = std::max(1.0 / 240.0, sourceFrameDuration_);
    const int64_t sourceFrame = std::max<int64_t>(0, static_cast<int64_t>(std::llround(std::max(0.0, timeSeconds) / duration)));
    return -1 - sourceFrame;
  }

  id<MTLTexture> cachedTexture(int64_t frameIndex) {
    auto found = cachedTextures_.find(frameIndex);
    if (found == cachedTextures_.end() || found->second == nullptr) {
      return nil;
    }
    releaseLastTexture();
    CFRetain(found->second);
    lastTexture_ = found->second;
    const double cachedTime = frameIndex >= 0
                                  ? static_cast<double>(frameIndex) / std::max(1.0, fps_)
                                  : static_cast<double>(-frameIndex - 1) * std::max(1.0 / 240.0, sourceFrameDuration_);
    lastTextureMediaTime_ = cachedTime;
    lastTextureSampleTime_ = cachedTime;
    return CVMetalTextureGetTexture(lastTexture_);
  }

  void cacheTexture(int64_t frameIndex, CVMetalTextureRef texture) {
    if (texture == nullptr || cachedTextures_.find(frameIndex) != cachedTextures_.end()) {
      return;
    }
    id<MTLTexture> metalTexture = CVMetalTextureGetTexture(texture);
    const size_t byteCost = metalTexture == nil ? 0 : static_cast<size_t>(metalTexture.width) *
                                                    static_cast<size_t>(metalTexture.height) * 4;
    CFRetain(texture);
    cachedTextures_[frameIndex] = texture;
    cachedTextureBytesByFrame_[frameIndex] = byteCost;
    cachedTextureBytes_ += byteCost;
    cachedFrameOrder_.push_back(frameIndex);
    constexpr size_t kMaxCachedFrames = 180;
    constexpr size_t kMaxCachedBytes = 384ULL * 1024ULL * 1024ULL;
    while (cachedFrameOrder_.size() > kMaxCachedFrames || cachedTextureBytes_ > kMaxCachedBytes) {
      const int64_t evict = cachedFrameOrder_.front();
      cachedFrameOrder_.pop_front();
      auto found = cachedTextures_.find(evict);
      if (found != cachedTextures_.end()) {
        if (found->second != nullptr) {
          CFRelease(found->second);
        }
        cachedTextures_.erase(found);
      }
      auto bytes = cachedTextureBytesByFrame_.find(evict);
      if (bytes != cachedTextureBytesByFrame_.end()) {
        cachedTextureBytes_ = bytes->second > cachedTextureBytes_ ? 0 : cachedTextureBytes_ - bytes->second;
        cachedTextureBytesByFrame_.erase(bytes);
      }
    }
  }

  void cacheCurrentSampleTexture(CVMetalTextureCacheRef textureCache) {
    if (currentSample_ == nullptr || currentSampleTime_ < 0.0) {
      return;
    }
    const int64_t frameIndex = sourceFrameCacheKey(currentSampleTime_);
    if (cachedTextures_.find(frameIndex) != cachedTextures_.end()) {
      return;
    }
    CVPixelBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(currentSample_);
    if (pixelBuffer == nullptr) {
      return;
    }
    CVMetalTextureRef cvTexture = nullptr;
    CVMetalTextureCacheCreateTextureFromImage(nil,
                                              textureCache,
                                              pixelBuffer,
                                              nil,
                                              MTLPixelFormatBGRA8Unorm,
                                              CVPixelBufferGetWidth(pixelBuffer),
                                              CVPixelBufferGetHeight(pixelBuffer),
                                              0,
                                              &cvTexture);
    if (cvTexture != nullptr) {
      cacheTexture(frameIndex, cvTexture);
      CFRelease(cvTexture);
    }
  }

  void releaseCurrentSample() {
    if (currentSample_ != nullptr) {
      CFRelease(currentSample_);
      currentSample_ = nullptr;
    }
    currentSampleTime_ = -1.0;
  }

  bool shouldResetReader(double target) const {
    if (reader_ == nil || !readerStarted_) {
      return true;
    }
    if (target + 0.001 < lastRequestedMediaTime_) {
      return true;
    }
    const double resetThreshold = requestedPlaying_ ? 0.25 : 8.0;
    if (std::abs(target - lastRequestedMediaTime_) > resetThreshold) {
      return true;
    }
    return false;
  }

  void resetReader() {
    if (reader_ != nil) {
      [reader_ cancelReading];
    }
    reader_ = nil;
    output_ = nil;
    readerStarted_ = false;
    readerStartTime_ = -1.0;
    releaseCurrentSample();
  }

  bool startReader(double mediaTime) {
    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url_ options:nil];
    AVAssetTrack* track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    if (!track) {
      return false;
    }
    const double nominalFrameRate = track.nominalFrameRate > 0.0 ? track.nominalFrameRate : fps_;
    const double minFrameDuration = CMTIME_IS_VALID(track.minFrameDuration)
                                        ? CMTimeGetSeconds(track.minFrameDuration)
                                        : 0.0;
    sourceFrameDuration_ = (std::isfinite(minFrameDuration) && minFrameDuration > 0.0)
                               ? minFrameDuration
                               : 1.0 / std::max(1.0, nominalFrameRate);

    NSError* error = nil;
    reader_ = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    if (!reader_) {
      return false;
    }
    const double target = std::max(0.0, mediaTime);
    CMTime start = CMTimeMakeWithSeconds(target, 60000);
    CMTime duration = CMTimeSubtract(asset.duration, start);
    if (CMTimeCompare(duration, kCMTimeZero) <= 0) {
      duration = CMTimeMakeWithSeconds(1.0 / 30.0, 60000);
    }
    reader_.timeRange = CMTimeRangeMake(start, duration);
    output_ = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:@{
      (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
      (NSString*)kCVPixelBufferMetalCompatibilityKey: @YES
    }];
    output_.alwaysCopiesSampleData = NO;
    if (![reader_ canAddOutput:output_]) {
      resetReader();
      return false;
    }
    [reader_ addOutput:output_];
    if (![reader_ startReading]) {
      resetReader();
      return false;
    }
    readerStarted_ = true;
    readerStartTime_ = target;
    lastRequestedMediaTime_ = target;
    return true;
  }

  CVPixelBufferRef pixelBufferForTime(double mediaTime, CVMetalTextureCacheRef textureCache) {
    if (reader_ == nil || output_ == nil) {
      return nullptr;
    }
    const double target = std::max(0.0, mediaTime);
    const double halfFrame = std::max(0.5 / std::max(1.0, fps_), sourceFrameDuration_ * 0.5 + 0.0005);

    if (currentSample_ == nullptr) {
      currentSample_ = [output_ copyNextSampleBuffer];
      currentSampleTime_ = presentationTime(currentSample_);
    }

    while (currentSample_ != nullptr && currentSampleTime_ + halfFrame < target) {
      cacheCurrentSampleTexture(textureCache);
      releaseCurrentSample();
      currentSample_ = [output_ copyNextSampleBuffer];
      currentSampleTime_ = presentationTime(currentSample_);
    }

    lastRequestedMediaTime_ = target;
    return currentSample_ ? CMSampleBufferGetImageBuffer(currentSample_) : nullptr;
  }

  double presentationTime(CMSampleBufferRef sample) const {
    if (sample == nullptr) {
      return -1.0;
    }
    return CMTimeGetSeconds(CMSampleBufferGetPresentationTimeStamp(sample));
  }
};

enum class NativeNodeKind {
  Background,
  Video,
  Image,
  Text,
  Shape,
  Audio
};

struct NativeIRLayer {
  const makelab::imgui::TrackItem* track = nullptr;
  const makelab::imgui::ClipItem* clip = nullptr;
  const makelab::imgui::AssetItem* asset = nullptr;
  NativeNodeKind kind = NativeNodeKind::Shape;
  int zIndex = 0;
};

struct NativeFrameDescriptorNode {
  NativeIRLayer layer;
  double localTime = 0.0;
  double mediaTime = 0.0;
  double animationX = std::numeric_limits<double>::quiet_NaN();
  double animationY = std::numeric_limits<double>::quiet_NaN();
  double animationPositionX = std::numeric_limits<double>::quiet_NaN();
  double animationPositionY = std::numeric_limits<double>::quiet_NaN();
  double animationCenterX = std::numeric_limits<double>::quiet_NaN();
  double animationCenterY = std::numeric_limits<double>::quiet_NaN();
  double translateX = 0.0;
  double translateY = 0.0;
  double opacityMultiplier = 1.0;
  double scaleMultiplierX = 1.0;
  double scaleMultiplierY = 1.0;
  double rotationOffsetDegrees = 0.0;
  double skewOffsetXDegrees = 0.0;
  double skewOffsetYDegrees = 0.0;
  double animationCornerRadius = std::numeric_limits<double>::quiet_NaN();
  double animationBorderOpacity = std::numeric_limits<double>::quiet_NaN();
  double animationShadowOpacity = std::numeric_limits<double>::quiet_NaN();
};

struct NativeRenderGraphNode {
  NativeFrameDescriptorNode frameNode;
  double x = 0.0;
  double y = 0.0;
  double width = 1.0;
  double height = 1.0;
  double anchorX = 0.5;
  double anchorY = 0.5;
  double opacity = 1.0;
  double rotationDegrees = 0.0;
  double scaleX = 1.0;
  double scaleY = 1.0;
  double skewXDegrees = 0.0;
  double skewYDegrees = 0.0;
  double cornerRadiusTopLeft = 0.0;
  double cornerRadiusTopRight = 0.0;
  double cornerRadiusBottomRight = 0.0;
  double cornerRadiusBottomLeft = 0.0;
  std::string fillColor = "#000000";
  double fillOpacity = 1.0;
  bool borderEnabled = false;
  double borderWidth = 0.0;
  std::string borderColor = "#FFFFFF";
  double borderOpacity = 1.0;
  std::string borderPosition = "inside";
  bool shadowEnabled = false;
  double shadowX = 0.0;
  double shadowY = 0.0;
  double shadowBlur = 0.0;
  double shadowSpread = 0.0;
  std::string shadowColor = "#000000";
  double shadowOpacity = 1.0;
};

struct NativeFXPass {
  std::string id;
  std::string clipId;
  std::string source;
  std::string kind;
  std::string executionClass;
  int order = 0;
  int sampleBudget = 1;
  std::unordered_map<std::string, double> numbers;
  std::unordered_map<std::string, std::string> strings;
};

struct NativeFXPassGraph {
  std::vector<NativeFXPass> passes;
  std::vector<std::string> diagnostics;
  int audioNodeCount = 0;
  int unsupportedFXCount = 0;
};

struct NativeResolvedTexture {
  id<MTLTexture> texture = nil;
  double boundsScaleX = 1.0;
  double boundsScaleY = 1.0;
  bool premultiplied = false;
  double uvExpansionX = 1.0;
  double uvExpansionY = 1.0;
  uint32_t tileMode = 2;
};

struct NativeCompositeNode {
  NativeRenderGraphNode styleNode;
  NativeRenderGraphNode drawNode;
  NativeResolvedTexture resolved;
};

struct NativeMotionBlurSample {
  double time = 0.0;
  double weight = 1.0;
};

vector_float4 HexColor(const std::string& value, float alphaScale = 1.0f) {
  std::string hex = value;
  if (!hex.empty() && hex[0] == '#') {
    hex = hex.substr(1);
  }
  if (hex.size() == 3) {
    std::string expanded;
    for (char c : hex) {
      expanded.push_back(c);
      expanded.push_back(c);
    }
    hex = expanded;
  }
  unsigned int rgba = 0;
  if (hex.size() == 6 || hex.size() == 8) {
    NSScanner* scanner = [NSScanner scannerWithString:[NSString stringWithUTF8String:hex.c_str()]];
    [scanner scanHexInt:&rgba];
  }
  const float r = static_cast<float>((rgba >> (hex.size() == 8 ? 24 : 16)) & 0xff) / 255.0f;
  const float g = static_cast<float>((rgba >> (hex.size() == 8 ? 16 : 8)) & 0xff) / 255.0f;
  const float b = static_cast<float>((rgba >> (hex.size() == 8 ? 8 : 0)) & 0xff) / 255.0f;
  const float a = hex.size() == 8 ? static_cast<float>(rgba & 0xff) / 255.0f : 1.0f;
  return vector_float4{r, g, b, std::clamp(a * alphaScale, 0.0f, 1.0f)};
}

NSColor* NSColorFromHex(const std::string& value, double alphaScale = 1.0) {
  vector_float4 color = HexColor(value, static_cast<float>(alphaScale));
  return [NSColor colorWithCalibratedRed:color.x green:color.y blue:color.z alpha:color.w];
}

CGPathRef CreateRoundedRectPath(CGRect rect, double topLeft, double topRight, double bottomRight, double bottomLeft) {
  const CGFloat maxRadius = std::max<CGFloat>(0.0, std::min(rect.size.width, rect.size.height) * 0.5);
  const CGFloat tl = std::min<CGFloat>(maxRadius, std::max<CGFloat>(0.0, topLeft));
  const CGFloat tr = std::min<CGFloat>(maxRadius, std::max<CGFloat>(0.0, topRight));
  const CGFloat br = std::min<CGFloat>(maxRadius, std::max<CGFloat>(0.0, bottomRight));
  const CGFloat bl = std::min<CGFloat>(maxRadius, std::max<CGFloat>(0.0, bottomLeft));
  CGMutablePathRef path = CGPathCreateMutable();
  CGPathMoveToPoint(path, nullptr, CGRectGetMinX(rect) + bl, CGRectGetMinY(rect));
  CGPathAddLineToPoint(path, nullptr, CGRectGetMaxX(rect) - br, CGRectGetMinY(rect));
  CGPathAddQuadCurveToPoint(path, nullptr, CGRectGetMaxX(rect), CGRectGetMinY(rect), CGRectGetMaxX(rect), CGRectGetMinY(rect) + br);
  CGPathAddLineToPoint(path, nullptr, CGRectGetMaxX(rect), CGRectGetMaxY(rect) - tr);
  CGPathAddQuadCurveToPoint(path, nullptr, CGRectGetMaxX(rect), CGRectGetMaxY(rect), CGRectGetMaxX(rect) - tr, CGRectGetMaxY(rect));
  CGPathAddLineToPoint(path, nullptr, CGRectGetMinX(rect) + tl, CGRectGetMaxY(rect));
  CGPathAddQuadCurveToPoint(path, nullptr, CGRectGetMinX(rect), CGRectGetMaxY(rect), CGRectGetMinX(rect), CGRectGetMaxY(rect) - tl);
  CGPathAddLineToPoint(path, nullptr, CGRectGetMinX(rect), CGRectGetMinY(rect) + bl);
  CGPathAddQuadCurveToPoint(path, nullptr, CGRectGetMinX(rect), CGRectGetMinY(rect), CGRectGetMinX(rect) + bl, CGRectGetMinY(rect));
  CGPathCloseSubpath(path);
  return path;
}

double Clamp01(double value, double fallback = 0.0) {
  const double next = std::isfinite(value) ? value : fallback;
  return std::clamp(next, 0.0, 1.0);
}

double CubicBezierCoordinate(double t, double p1, double p2) {
  const double c = 3.0 * p1;
  const double b = 3.0 * (p2 - p1) - c;
  const double a = 1.0 - c - b;
  return ((a * t + b) * t + c) * t;
}

double CubicBezierDerivative(double t, double p1, double p2) {
  const double c = 3.0 * p1;
  const double b = 3.0 * (p2 - p1) - c;
  const double a = 1.0 - c - b;
  return (3.0 * a * t + 2.0 * b) * t + c;
}

bool ParseCubicBezier(const std::string& easing, double& x1, double& y1, double& x2, double& y2) {
  return std::sscanf(easing.c_str(), "cubic-bezier(%lf,%lf,%lf,%lf)", &x1, &y1, &x2, &y2) == 4 ||
         std::sscanf(easing.c_str(), "cubic-bezier(%lf, %lf, %lf, %lf)", &x1, &y1, &x2, &y2) == 4;
}

double CubicBezierEasedProgress(double x, double x1, double y1, double x2, double y2) {
  const double target = Clamp01(x, 0.0);
  x1 = std::clamp(x1, 0.0, 1.0);
  x2 = std::clamp(x2, 0.0, 1.0);
  double t = target;
  for (int i = 0; i < 8; ++i) {
    const double current = CubicBezierCoordinate(t, x1, x2) - target;
    const double derivative = CubicBezierDerivative(t, x1, x2);
    if (std::abs(current) < 0.000001 || std::abs(derivative) < 0.000001) {
      break;
    }
    t = std::clamp(t - current / derivative, 0.0, 1.0);
  }
  double low = 0.0;
  double high = 1.0;
  for (int i = 0; i < 8; ++i) {
    const double current = CubicBezierCoordinate(t, x1, x2);
    if (std::abs(current - target) < 0.000001) {
      break;
    }
    if (current < target) {
      low = t;
    } else {
      high = t;
    }
    t = (low + high) * 0.5;
  }
  return CubicBezierCoordinate(t, y1, y2);
}

double EasedProgress(double value, const std::string& easing) {
  const double t = Clamp01(value, 0.0);
  if (easing == "linear") return t;
  double x1 = 0.0;
  double y1 = 0.0;
  double x2 = 1.0;
  double y2 = 1.0;
  if (ParseCubicBezier(easing, x1, y1, x2, y2)) {
    return CubicBezierEasedProgress(t, x1, y1, x2, y2);
  }
  if (easing == "easeIn" || easing == "easeInCubic") return t * t * t;
  if (easing == "easeOut" || easing == "easeOutCubic") return 1.0 - std::pow(1.0 - t, 3.0);
  if (easing == "easeInQuad") return t * t;
  if (easing == "easeOutQuad") return 1.0 - (1.0 - t) * (1.0 - t);
  if (easing == "easeInOutQuad") {
    return t < 0.5 ? 2.0 * t * t : 1.0 - std::pow(-2.0 * t + 2.0, 2.0) / 2.0;
  }
  if (easing == "easeInQuart") return t * t * t * t;
  if (easing == "easeOutQuart") return 1.0 - std::pow(1.0 - t, 4.0);
  if (easing == "easeInOutQuart") {
    return t < 0.5 ? 8.0 * t * t * t * t : 1.0 - std::pow(-2.0 * t + 2.0, 4.0) / 2.0;
  }
  if (easing == "easeInOut" || easing == "cubic-bezier(0.42, 0, 0.58, 1)") {
    return t < 0.5 ? 2.0 * t * t : 1.0 - std::pow(-2.0 * t + 2.0, 2.0) / 2.0;
  }
  if (easing == "easeOutBack" || easing == "backOut") {
    const double c1 = 1.70158;
    const double c3 = c1 + 1.0;
    return 1.0 + c3 * std::pow(t - 1.0, 3.0) + c1 * std::pow(t - 1.0, 2.0);
  }
  if (easing == "easeInBack" || easing == "backIn") {
    const double c1 = 1.70158;
    const double c3 = c1 + 1.0;
    return c3 * t * t * t - c1 * t * t;
  }
  if (easing == "easeInOutBack" || easing == "backInOut") {
    const double c1 = 1.70158;
    const double c2 = c1 * 1.525;
    return t < 0.5
               ? (std::pow(2.0 * t, 2.0) * ((c2 + 1.0) * 2.0 * t - c2)) / 2.0
               : (std::pow(2.0 * t - 2.0, 2.0) * ((c2 + 1.0) * (t * 2.0 - 2.0) + c2) + 2.0) / 2.0;
  }
  return 1.0 - std::pow(1.0 - t, 3.0);
}

double EvaluateAnimationTrack(const std::vector<makelab::imgui::ClipItem::AnimationFrame>& frames,
                              double time,
                              double fallback) {
  if (frames.empty()) return fallback;
  if (time <= frames.front().time) return frames.front().value;
  if (time >= frames.back().time) return frames.back().value;
  for (size_t index = 1; index < frames.size(); ++index) {
    const auto& previous = frames[index - 1];
    const auto& next = frames[index];
    if (time <= next.time) {
      const double span = std::max(0.0001, next.time - previous.time);
      const double progress = EasedProgress((time - previous.time) / span, next.easing.empty() ? previous.easing : next.easing);
      return previous.value + (next.value - previous.value) * progress;
    }
  }
  return fallback;
}

double EffectNumber(const makelab::imgui::ClipItem::EffectItem& effect,
                    const std::string& key,
                    double fallback) {
  auto found = effect.numbers.find(key);
  return found == effect.numbers.end() || !std::isfinite(found->second) ? fallback : found->second;
}

std::string EffectString(const makelab::imgui::ClipItem::EffectItem& effect,
                         const std::string& key,
                         const std::string& fallback) {
  auto found = effect.strings.find(key);
  return found == effect.strings.end() || found->second.empty() ? fallback : found->second;
}

double PassNumber(const NativeFXPass& pass, const std::string& key, double fallback) {
  auto found = pass.numbers.find(key);
  return found == pass.numbers.end() || !std::isfinite(found->second) ? fallback : found->second;
}

std::string PassString(const NativeFXPass& pass, const std::string& key, const std::string& fallback) {
  auto found = pass.strings.find(key);
  return found == pass.strings.end() || found->second.empty() ? fallback : found->second;
}

std::unordered_map<std::string, std::vector<makelab::imgui::ClipItem::AnimationFrame>>
CompileAnimationTracks(const makelab::imgui::ClipItem& clip) {
  std::unordered_map<std::string, std::vector<makelab::imgui::ClipItem::AnimationFrame>> tracks;
  for (const auto& frame : clip.animationFrames) {
    tracks[frame.property].push_back(frame);
  }
  for (auto& entry : tracks) {
    std::sort(entry.second.begin(), entry.second.end(), [](const auto& left, const auto& right) {
      return left.time < right.time;
    });
  }
  return tracks;
}

double EvaluateAnimationProperty(const makelab::imgui::ClipItem& clip,
                                 const std::string& property,
                                 double time,
                                 double fallback) {
  const makelab::imgui::ClipItem::AnimationFrame* first = nullptr;
  const makelab::imgui::ClipItem::AnimationFrame* last = nullptr;
  const makelab::imgui::ClipItem::AnimationFrame* previous = nullptr;
  const makelab::imgui::ClipItem::AnimationFrame* next = nullptr;
  for (const auto& frame : clip.animationFrames) {
    if (frame.property != property) {
      continue;
    }
    if (first == nullptr || frame.time < first->time) {
      first = &frame;
    }
    if (last == nullptr || frame.time > last->time) {
      last = &frame;
    }
    if (frame.time <= time && (previous == nullptr || frame.time > previous->time)) {
      previous = &frame;
    }
    if (frame.time >= time && (next == nullptr || frame.time < next->time)) {
      next = &frame;
    }
  }
  if (first == nullptr || last == nullptr) {
    return fallback;
  }
  if (time <= first->time) {
    return first->value;
  }
  if (time >= last->time) {
    return last->value;
  }
  if (previous == nullptr || next == nullptr) {
    return fallback;
  }
  if (previous == next || std::abs(next->time - previous->time) <= 0.0001) {
    return previous->value;
  }
  const double span = std::max(0.0001, next->time - previous->time);
  const double progress = EasedProgress((time - previous->time) / span,
                                        next->easing.empty() ? previous->easing : next->easing);
  return previous->value + (next->value - previous->value) * progress;
}

NativeFrameDescriptorNode EvaluateAnimation(const NativeFrameDescriptorNode& input) {
  NativeFrameDescriptorNode node = input;
  const auto* clip = node.layer.clip;
  if (clip == nullptr) return node;
  auto evaluate = [&](const std::string& property, double fallback) {
    return EvaluateAnimationProperty(*clip, property, node.localTime, fallback);
  };
  const double scale = evaluate("scale", 1.0);
  const double outDuration = std::max(0.0, clip->motionOutDuration);
  const double outOpacity = outDuration > 0.0 ? EasedProgress((clip->durationSeconds - node.localTime) / outDuration, clip->motionEasing) : 1.0;
  node.animationX = evaluate("x", std::numeric_limits<double>::quiet_NaN());
  node.animationY = evaluate("y", std::numeric_limits<double>::quiet_NaN());
  node.animationPositionX = evaluate("positionX", std::numeric_limits<double>::quiet_NaN());
  node.animationPositionY = evaluate("positionY", std::numeric_limits<double>::quiet_NaN());
  node.animationCenterX = evaluate("centerX", std::numeric_limits<double>::quiet_NaN());
  node.animationCenterY = evaluate("centerY", std::numeric_limits<double>::quiet_NaN());
  node.translateX = evaluate("translateX", 0.0);
  node.translateY = evaluate("translateY", 0.0);
  node.opacityMultiplier = evaluate("opacity", 1.0) * outOpacity;
  node.scaleMultiplierX = evaluate("scaleX", scale);
  node.scaleMultiplierY = evaluate("scaleY", scale);
  node.rotationOffsetDegrees = evaluate("rotation", 0.0);
  node.skewOffsetXDegrees = evaluate("skewX", 0.0);
  node.skewOffsetYDegrees = evaluate("skewY", 0.0);
  node.animationCornerRadius = evaluate("cornerRadius", std::numeric_limits<double>::quiet_NaN());
  node.animationBorderOpacity = evaluate("border.opacity", std::numeric_limits<double>::quiet_NaN());
  node.animationShadowOpacity = evaluate("shadow.opacity", std::numeric_limits<double>::quiet_NaN());
  return node;
}

std::vector<NativeIRLayer> BuildHyperFrameIR(const makelab::imgui::WorkspaceViewState& workspace) {
  std::unordered_map<std::string, const makelab::imgui::AssetItem*> assetsById;
  for (const auto& asset : workspace.assets) {
    assetsById[asset.id] = &asset;
  }

  std::vector<NativeIRLayer> layers;
  for (const auto& track : workspace.tracks) {
    if (track.hidden) {
      continue;
    }
    for (const auto& clip : track.clips) {
      NativeIRLayer layer;
      layer.track = &track;
      layer.clip = &clip;
      auto asset = assetsById.find(clip.assetId);
      if (asset != assetsById.end()) {
        layer.asset = asset->second;
      }
      const std::string type = !clip.type.empty() ? clip.type : track.kind;
      const std::string assetType = layer.asset != nullptr ? layer.asset->type : "";
      if (type == "background" || track.kind == "background") {
        layer.kind = NativeNodeKind::Background;
      } else if (type == "video" || assetType == "video") {
        layer.kind = NativeNodeKind::Video;
      } else if (type == "image" || assetType == "image") {
        layer.kind = NativeNodeKind::Image;
      } else if (type == "text" || track.kind == "text") {
        layer.kind = NativeNodeKind::Text;
      } else if (type == "audio" || track.kind == "audio" || assetType == "audio") {
        layer.kind = NativeNodeKind::Audio;
      } else {
        layer.kind = NativeNodeKind::Shape;
      }
      layers.push_back(layer);
    }
  }

  const int count = static_cast<int>(layers.size());
  for (int i = 0; i < count; ++i) {
    layers[i].zIndex = count - i - 1;
  }
  return layers;
}

std::vector<NativeFrameDescriptorNode> EvaluateFrameDescriptor(const makelab::imgui::WorkspaceViewState& workspace,
                                                               const std::vector<NativeIRLayer>& ir,
                                                               int64_t frameIndex) {
  const double frameTimeSeconds = makelab::timeline::FrameToSeconds({frameIndex}, workspace.frameRate);
  std::vector<NativeFrameDescriptorNode> nodes;
  for (const auto& layer : ir) {
    if (layer.clip == nullptr || layer.track == nullptr || layer.track->hidden) {
      continue;
    }
    const auto& clip = *layer.clip;
    const int64_t startFrame = std::max<int64_t>(0, clip.startFrame);
    const int64_t durationFrames = std::max<int64_t>(1, clip.durationFrames);
    if (frameIndex < startFrame || frameIndex >= startFrame + durationFrames) {
      continue;
    }
    NativeFrameDescriptorNode node;
    node.layer = layer;
    node.localTime = makelab::timeline::FrameToSeconds({frameIndex - startFrame}, workspace.frameRate);
    node.mediaTime = std::max(0.0, node.localTime + clip.trimInSeconds);
    nodes.push_back(EvaluateAnimation(node));
  }
  (void)frameTimeSeconds;
  return nodes;
}

std::vector<NativeFrameDescriptorNode> EvaluateSubframeDescriptorAtTime(const makelab::imgui::WorkspaceViewState& workspace,
                                                                        const std::vector<NativeIRLayer>& ir,
                                                                        double timeSeconds) {
  std::vector<NativeFrameDescriptorNode> nodes;
  for (const auto& layer : ir) {
    if (layer.clip == nullptr || layer.track == nullptr || layer.track->hidden) {
      continue;
    }
    const auto& clip = *layer.clip;
    if (timeSeconds + 0.0001 < clip.startSeconds || timeSeconds >= clip.startSeconds + clip.durationSeconds) {
      continue;
    }
    NativeFrameDescriptorNode node;
    node.layer = layer;
    node.localTime = std::max(0.0, timeSeconds - clip.startSeconds);
    node.mediaTime = std::max(0.0, node.localTime + clip.trimInSeconds);
    nodes.push_back(EvaluateAnimation(node));
  }
  (void)workspace;
  return nodes;
}

NativeRenderGraphNode CompileRenderGraphNode(const makelab::imgui::WorkspaceViewState& workspace,
                                             const NativeFrameDescriptorNode& frameNode) {
  const auto& clip = *frameNode.layer.clip;
  NativeRenderGraphNode node;
  node.frameNode = frameNode;
  node.width = clip.width > 0 ? clip.width : workspace.width;
  node.height = clip.height > 0 ? clip.height : workspace.height;
  node.anchorX = clip.anchorX;
  node.anchorY = clip.anchorY;
  node.x = clip.width > 0 || clip.height > 0 ? clip.x : 0.0;
  node.y = clip.width > 0 || clip.height > 0 ? clip.y : 0.0;
  if (std::isfinite(frameNode.animationX)) {
    node.x = frameNode.animationX;
  } else if (std::isfinite(frameNode.animationPositionX)) {
    node.x = frameNode.animationPositionX - node.width * node.anchorX;
  }
  if (std::isfinite(frameNode.animationY)) {
    node.y = frameNode.animationY;
  } else if (std::isfinite(frameNode.animationPositionY)) {
    node.y = frameNode.animationPositionY - node.height * node.anchorY;
  }
  if (std::isfinite(frameNode.animationCenterX)) {
    node.x = frameNode.animationCenterX - node.width * 0.5;
  }
  if (std::isfinite(frameNode.animationCenterY)) {
    node.y = frameNode.animationCenterY - node.height * 0.5;
  }
  node.x += frameNode.translateX;
  node.y += frameNode.translateY;
  node.opacity = std::clamp(clip.opacity * frameNode.opacityMultiplier, 0.0, 1.0);
  node.rotationDegrees = clip.rotationDegrees + frameNode.rotationOffsetDegrees;
  node.scaleX = (clip.scaleX == 0.0 ? 1.0 : clip.scaleX) * frameNode.scaleMultiplierX;
  node.scaleY = (clip.scaleY == 0.0 ? 1.0 : clip.scaleY) * frameNode.scaleMultiplierY;
  node.skewXDegrees = clip.skewXDegrees + frameNode.skewOffsetXDegrees;
  node.skewYDegrees = clip.skewYDegrees + frameNode.skewOffsetYDegrees;
  const double animatedRadius = std::isfinite(frameNode.animationCornerRadius) ? frameNode.animationCornerRadius : clip.cornerRadius;
  node.cornerRadiusTopLeft = std::max(0.0, clip.cornerRadiusTopLeft > 0.0 ? clip.cornerRadiusTopLeft : animatedRadius);
  node.cornerRadiusTopRight = std::max(0.0, clip.cornerRadiusTopRight > 0.0 ? clip.cornerRadiusTopRight : animatedRadius);
  node.cornerRadiusBottomRight = std::max(0.0, clip.cornerRadiusBottomRight > 0.0 ? clip.cornerRadiusBottomRight : animatedRadius);
  node.cornerRadiusBottomLeft = std::max(0.0, clip.cornerRadiusBottomLeft > 0.0 ? clip.cornerRadiusBottomLeft : animatedRadius);
  node.fillColor = clip.fillEnabled ? clip.fillColor : (frameNode.layer.kind == NativeNodeKind::Background ? "#000000" : "#38BDF8");
  node.fillOpacity = clip.fillEnabled ? clip.fillOpacity : 1.0;
  node.borderEnabled = clip.borderEnabled;
  node.borderWidth = std::max(0.0, clip.borderWidth);
  node.borderColor = clip.borderColor;
  node.borderOpacity = Clamp01(std::isfinite(frameNode.animationBorderOpacity) ? frameNode.animationBorderOpacity : clip.borderOpacity, 1.0);
  node.borderPosition = clip.borderPosition;
  node.shadowEnabled = clip.shadowEnabled;
  node.shadowX = clip.shadowX;
  node.shadowY = clip.shadowY;
  node.shadowBlur = std::max(0.0, clip.shadowBlur);
  node.shadowSpread = clip.shadowSpread;
  node.shadowColor = clip.shadowColor;
  node.shadowOpacity = Clamp01(std::isfinite(frameNode.animationShadowOpacity) ? frameNode.animationShadowOpacity : clip.shadowOpacity, 1.0);
  if (frameNode.layer.kind == NativeNodeKind::Background) {
    node.x = 0.0;
    node.y = 0.0;
    node.width = workspace.width;
    node.height = workspace.height;
    node.anchorX = 0.0;
    node.anchorY = 0.0;
  }
  return node;
}

std::vector<NativeRenderGraphNode> CompileRenderGraph(const makelab::imgui::WorkspaceViewState& workspace,
                                                      const std::vector<NativeFrameDescriptorNode>& descriptor) {
  std::vector<NativeRenderGraphNode> graph;
  for (const auto& frameNode : descriptor) {
    if (frameNode.layer.clip == nullptr) {
      continue;
    }
    graph.push_back(CompileRenderGraphNode(workspace, frameNode));
  }
  std::sort(graph.begin(), graph.end(), [](const auto& left, const auto& right) {
    return left.frameNode.layer.zIndex < right.frameNode.layer.zIndex;
  });
  return graph;
}

NativeFXPassGraph CompileFXPassGraph(const std::vector<NativeRenderGraphNode>& graph) {
  NativeFXPassGraph fxGraph;
  int order = 0;
  for (const auto& node : graph) {
    const auto* clip = node.frameNode.layer.clip;
    if (node.frameNode.layer.kind == NativeNodeKind::Audio) {
      fxGraph.audioNodeCount += 1;
    }
    if (clip == nullptr) {
      continue;
    }
    auto effectActive = [&](const makelab::imgui::ClipItem::EffectItem& effect) {
      const double localTime = node.frameNode.localTime;
      return localTime + 0.0001 >= effect.activeStartSeconds &&
             localTime < effect.activeEndSeconds - 0.0001;
    };
    const auto motionTile = std::find_if(clip->effects.begin(), clip->effects.end(), [](const auto& effect) {
      return effect.enabled && effect.kind == "motionTile";
    });
    if (motionTile != clip->effects.end() && effectActive(*motionTile)) {
      NativeFXPass pass;
      pass.id = motionTile->id + ":pass";
      pass.clipId = clip->id;
      pass.source = motionTile->source;
      pass.kind = "motionTileSampler";
      pass.executionClass = "shader";
      pass.order = ++order;
      pass.numbers = motionTile->numbers;
      pass.strings = motionTile->strings;
      fxGraph.passes.push_back(pass);
    }
    for (const auto& effect : clip->effects) {
      if (!effect.enabled || effect.kind == "motionTile") {
        continue;
      }
      if (!effectActive(effect)) {
        continue;
      }
      NativeFXPass pass;
      pass.id = effect.id + ":pass";
      pass.clipId = clip->id;
      pass.source = effect.source;
      pass.kind = effect.kind == "transformMotionBlur" ? "transformMotionBlur" : effect.kind;
      pass.executionClass = effect.kind == "transformMotionBlur" ? "temporal" : "shader";
      pass.order = ++order;
      pass.numbers = effect.numbers;
      pass.strings = effect.strings;
      if (pass.kind == "gaussianBlur") {
        const double radius = std::max(0.0, PassNumber(pass, "radius", PassNumber(pass, "blur", 0.0)));
        pass.numbers["radius"] = radius;
        pass.sampleBudget = std::max(1, static_cast<int>(std::ceil(radius)));
        fxGraph.passes.push_back(pass);
      } else if (pass.kind == "transformMotionBlur") {
        pass.sampleBudget = 64;
        pass.numbers["playbackSampleBudget"] = 24;
        pass.numbers["scrubInteractiveSampleBudget"] = 32;
        pass.numbers["pausedPreviewSampleBudget"] = 64;
        pass.strings["samplePlanAuthority"] = "core-fxpassgraph";
        fxGraph.passes.push_back(pass);
      } else {
        fxGraph.unsupportedFXCount += 1;
        fxGraph.diagnostics.push_back("FXPassGraph diagnostic: clip " + clip->id + " effect " + pass.kind + " reached native preview, but this Metal adapter pass is not executable yet.");
      }
    }
  }
  if (fxGraph.audioNodeCount > 0) {
    fxGraph.diagnostics.push_back("AudioGraph accepted " + std::to_string(fxGraph.audioNodeCount) + " audio node(s); visual FinalFrameSurface remains video-only until native audio mixer/export is connected.");
  }
  return fxGraph;
}

enum class FinalFrameSurfaceStatus {
  Accepted,
  Preserved,
  Rejected,
};

struct FinalFrameSurfaceResult {
  FinalFrameSurfaceStatus status = FinalFrameSurfaceStatus::Rejected;
  uint64_t requestGeneration = 0;
  int64_t requestedFrame = 0;
  int64_t surfaceFrame = -1;
  int width = 0;
  int height = 0;
  id<MTLTexture> texture = nil;
  std::string diagnostic;

  bool accepted() const {
    return status == FinalFrameSurfaceStatus::Accepted && texture != nil && surfaceFrame == requestedFrame;
  }
};

enum class NativeRenderIntent {
  PausedPreview,
  PlaybackRealtime,
  ScrubInteractive,
};

class MacMetalRenderFrameExecutor {
 public:
  MacMetalRenderFrameExecutor(id<MTLDevice> device, id<MTLCommandQueue> commandQueue)
      : device_(device), commandQueue_(commandQueue), textureLoader_([[MTKTextureLoader alloc] initWithDevice:device]) {
    CVMetalTextureCacheCreate(nil, nil, device_, nil, &textureCache_);
    NSError* error = nil;
    id<MTLLibrary> library = [device_ newLibraryWithSource:kMacPreviewMetalShader options:nil error:&error];
    if (!library) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: Metal shader library failed.";
      return;
    }
    MTLRenderPipelineDescriptor* descriptor = [[MTLRenderPipelineDescriptor alloc] init];
    descriptor.vertexFunction = [library newFunctionWithName:@"mac_preview_vertex"];
    descriptor.fragmentFunction = [library newFunctionWithName:@"mac_preview_texture_fragment"];
    descriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    descriptor.colorAttachments[0].blendingEnabled = YES;
    descriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    descriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    descriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    descriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipeline_ = [device_ newRenderPipelineStateWithDescriptor:descriptor error:&error];
    if (!pipeline_) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: Metal pipeline creation failed.";
    }
    MTLRenderPipelineDescriptor* premultipliedDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    premultipliedDescriptor.vertexFunction = [library newFunctionWithName:@"mac_preview_vertex"];
    premultipliedDescriptor.fragmentFunction = [library newFunctionWithName:@"mac_preview_premultiplied_fragment"];
    premultipliedDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    premultipliedDescriptor.colorAttachments[0].blendingEnabled = YES;
    premultipliedDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    premultipliedDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    premultipliedDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    premultipliedDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    premultipliedDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    premultipliedDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    premultipliedPipeline_ = [device_ newRenderPipelineStateWithDescriptor:premultipliedDescriptor error:&error];
    MTLRenderPipelineDescriptor* shapeDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    shapeDescriptor.vertexFunction = [library newFunctionWithName:@"mac_preview_vertex"];
    shapeDescriptor.fragmentFunction = [library newFunctionWithName:@"mac_preview_shape_fragment"];
    shapeDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    shapeDescriptor.colorAttachments[0].blendingEnabled = YES;
    shapeDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    shapeDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    shapeDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    shapeDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    shapeDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    shapeDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    shapePipeline_ = [device_ newRenderPipelineStateWithDescriptor:shapeDescriptor error:&error];
    MTLRenderPipelineDescriptor* additiveDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    additiveDescriptor.vertexFunction = [library newFunctionWithName:@"mac_preview_vertex"];
    additiveDescriptor.fragmentFunction = [library newFunctionWithName:@"mac_preview_texture_fragment"];
    additiveDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    additiveDescriptor.colorAttachments[0].blendingEnabled = YES;
    additiveDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    additiveDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    additiveDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    additiveDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    additiveDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    additiveDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
    additiveFloatPipeline_ = [device_ newRenderPipelineStateWithDescriptor:additiveDescriptor error:&error];
    MTLRenderPipelineDescriptor* motionBlurBatchDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    motionBlurBatchDescriptor.vertexFunction = [library newFunctionWithName:@"mac_motion_blur_vertex"];
    motionBlurBatchDescriptor.fragmentFunction = [library newFunctionWithName:@"mac_preview_texture_fragment"];
    motionBlurBatchDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatRGBA16Float;
    motionBlurBatchDescriptor.colorAttachments[0].blendingEnabled = YES;
    motionBlurBatchDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    motionBlurBatchDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    motionBlurBatchDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorOne;
    motionBlurBatchDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    motionBlurBatchDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorOne;
    motionBlurBatchDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
    motionBlurBatchPipeline_ = [device_ newRenderPipelineStateWithDescriptor:motionBlurBatchDescriptor error:&error];
    id<MTLFunction> motionTileFunction = [library newFunctionWithName:@"mac_fx_motion_tile"];
    id<MTLFunction> gaussianBlurFunction = [library newFunctionWithName:@"mac_fx_gaussian_blur"];
    if (motionTileFunction) {
      motionTilePipeline_ = [device_ newComputePipelineStateWithFunction:motionTileFunction error:&error];
    }
    if (gaussianBlurFunction) {
      gaussianBlurPipeline_ = [device_ newComputePipelineStateWithFunction:gaussianBlurFunction error:&error];
    }
  }

  ~MacMetalRenderFrameExecutor() {
    if (textureCache_) {
      CFRelease(textureCache_);
    }
  }

  FinalFrameSurfaceResult render(const makelab::imgui::WorkspaceViewState& workspace,
                                 int64_t frameIndex,
                                 uint64_t requestGeneration,
                                 bool playing,
                                 bool waitForCompletion = false,
                                 void (^completion)(FinalFrameSurfaceResult) = nil,
                                 NativeRenderIntent intent = NativeRenderIntent::PausedPreview) {
    FinalFrameSurfaceResult result;
    result.requestGeneration = requestGeneration;
    result.requestedFrame = frameIndex;
    result.width = workspace.width;
    result.height = workspace.height;
    diagnostic_.clear();
    if (!pipeline_ || !shapePipeline_ || !textureCache_) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor blocked: Metal pipeline or CVMetalTextureCache is not ready.";
      }
      result.status = FinalFrameSurfaceStatus::Rejected;
      result.diagnostic = diagnostic_;
      return result;
    }
    if (!workspace.opened) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: workspace is not opened.";
      result.status = FinalFrameSurfaceStatus::Rejected;
      result.diagnostic = diagnostic_;
      return result;
    }
    ensureFinalTexture(workspace.width, workspace.height);
    if (!finalTexture_) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: FinalFrameSurface texture allocation failed.";
      result.status = FinalFrameSurfaceStatus::Rejected;
      result.diagnostic = diagnostic_;
      return result;
    }

    const auto ir = BuildHyperFrameIR(workspace);
    const auto descriptor = EvaluateFrameDescriptor(workspace, ir, frameIndex);
    const auto graph = CompileRenderGraph(workspace, descriptor);
    const auto fxPassGraph = CompileFXPassGraph(graph);
    const double frameTimeSeconds = makelab::timeline::FrameToSeconds({frameIndex}, workspace.frameRate);

    id<MTLCommandBuffer> commandBuffer = [commandQueue_ commandBuffer];
    if (!commandBuffer) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: Metal command buffer creation failed.";
      result.status = FinalFrameSurfaceStatus::Rejected;
      result.diagnostic = diagnostic_;
      return result;
    }

    std::vector<NativeCompositeNode> resolvedNodes;
    int audioNodeCount = 0;
    int missingRequiredSourceCount = 0;
    for (const auto& node : graph) {
      if (node.frameNode.layer.kind == NativeNodeKind::Audio) {
        audioNodeCount += 1;
        continue;
      }
      const auto* clip = node.frameNode.layer.clip;
      if (clip != nullptr) {
        if (const auto* motionBlurPass = transformMotionBlurPassForClip(fxPassGraph, clip->id)) {
          id<MTLTexture> motionBlurTexture = renderMotionBlurTexture(workspace, ir, node, fxPassGraph, *motionBlurPass, frameTimeSeconds, playing, intent, commandBuffer);
          if (motionBlurTexture) {
            NativeRenderGraphNode fullNode = fullscreenNode(node, workspace);
            NativeResolvedTexture postResolved = applyFXPasses(motionBlurTexture, fullNode, fxPassGraph, commandBuffer, false, true);
            postResolved.texture = postResolved.texture ?: motionBlurTexture;
            postResolved.premultiplied = true;
            resolvedNodes.push_back({node, fullNode, postResolved});
            continue;
          }
        }
      }
      const bool realtimeTexturePath = playing ||
                                       intent == NativeRenderIntent::PlaybackRealtime ||
                                       intent == NativeRenderIntent::ScrubInteractive;
      id<MTLTexture> source = sourceTexture(workspace, node, realtimeTexturePath);
      if (!source) {
        missingRequiredSourceCount += 1;
        if (diagnostic_.empty()) {
          const auto* clip = node.frameNode.layer.clip;
          diagnostic_ = "MacMetalRenderFrameExecutor preserved previous FinalFrameSurface: source texture is not ready for frame layer ";
          diagnostic_ += clip ? clip->id : "unknown";
          diagnostic_ += ".";
        }
        continue;
      }
      NativeResolvedTexture resolved = applyFXPasses(source, node, fxPassGraph, commandBuffer);
      resolvedNodes.push_back({node, node, resolved.texture ? resolved : NativeResolvedTexture{source, 1.0, 1.0}});
    }

    if (missingRequiredSourceCount > 0) {
      result.status = FinalFrameSurfaceStatus::Preserved;
      result.surfaceFrame = -1;
      result.diagnostic = diagnostic_;
      return result;
    }

    if (resolvedNodes.empty()) {
      if (diagnostic_.empty()) {
        diagnostic_ = audioNodeCount > 0
                          ? "MacMetalRenderFrameExecutor rejected requested frame: only audio nodes are active; no visual FinalFrameSurface was mutated."
                          : "MacMetalRenderFrameExecutor rejected requested frame: RenderGraph has no drawable visual node.";
      }
      result.status = FinalFrameSurfaceStatus::Rejected;
      result.diagnostic = diagnostic_;
      return result;
    }

    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = finalTexture_;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: render encoder creation failed.";
      result.status = FinalFrameSurfaceStatus::Rejected;
      result.diagnostic = diagnostic_;
      return result;
    }
    [encoder setRenderPipelineState:pipeline_];

    int drawnNodeCount = 0;
    for (const auto& composite : resolvedNodes) {
      if (!composite.resolved.texture) {
        continue;
      }
      drawDropShadow(composite.styleNode, workspace, encoder);
      [encoder setRenderPipelineState:(composite.resolved.premultiplied && premultipliedPipeline_) ? premultipliedPipeline_ : pipeline_];
      drawTexture(composite.resolved.texture,
                  scaledNode(composite.drawNode, composite.resolved.boundsScaleX, composite.resolved.boundsScaleY),
                  workspace,
                  encoder,
                  composite.resolved.uvExpansionX,
                  composite.resolved.uvExpansionY,
                  composite.resolved.tileMode);
      drawBorder(composite.styleNode, workspace, encoder);
      drawnNodeCount += 1;
    }

    [encoder endEncoding];
    if (drawnNodeCount == 0) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor rejected requested frame: no resolved drawable visual node was emitted.";
      }
      result.status = FinalFrameSurfaceStatus::Rejected;
      result.diagnostic = diagnostic_;
      return result;
    }
    if (!fxPassGraph.diagnostics.empty()) {
      diagnostic_ = fxPassGraph.diagnostics.front();
      for (size_t i = 1; i < fxPassGraph.diagnostics.size() && i < 3; ++i) {
        diagnostic_ += " | " + fxPassGraph.diagnostics[i];
      }
    }
    result.status = FinalFrameSurfaceStatus::Accepted;
    result.surfaceFrame = frameIndex;
    result.texture = finalTexture_;
    result.diagnostic = diagnostic_;
    if (completion != nil && !waitForCompletion) {
      FinalFrameSurfaceResult scheduledResult = result;
      [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completedBuffer) {
        FinalFrameSurfaceResult completedResult = scheduledResult;
        if (completedBuffer.status == MTLCommandBufferStatusError) {
          NSError* error = completedBuffer.error;
          std::string message = "MacMetalRenderFrameExecutor rejected requested frame: Metal command buffer failed during FinalFrameSurface playback.";
          if (error != nil && error.localizedDescription != nil) {
            message += " ";
            message += ToStdString(error.localizedDescription);
          }
          completedResult.status = FinalFrameSurfaceStatus::Rejected;
          completedResult.surfaceFrame = -1;
          completedResult.diagnostic = message;
        }
        completion(completedResult);
      }];
    }
    [commandBuffer commit];
    if (waitForCompletion) {
      [commandBuffer waitUntilCompleted];
      if (commandBuffer.status == MTLCommandBufferStatusError) {
        NSError* error = commandBuffer.error;
        diagnostic_ = "MacMetalRenderFrameExecutor rejected requested frame: Metal command buffer failed during FinalFrameSurface export.";
        if (error != nil && error.localizedDescription != nil) {
          diagnostic_ += " ";
          diagnostic_ += ToStdString(error.localizedDescription);
        }
        result.status = FinalFrameSurfaceStatus::Rejected;
        result.diagnostic = diagnostic_;
        return result;
      }
    }
    return result;
  }

  const std::string& diagnostic() const { return diagnostic_; }

  bool copyTextureBGRA8(id<MTLTexture> texture, std::vector<uint8_t>& out, size_t& bytesPerRow) {
    if (texture == nil || commandQueue_ == nil) {
      diagnostic_ = "MacMetalRenderFrameExecutor readback blocked: texture or command queue is not ready.";
      return false;
    }
    const int width = static_cast<int>(texture.width);
    const int height = static_cast<int>(texture.height);
    if (width <= 0 || height <= 0 || texture.pixelFormat != MTLPixelFormatBGRA8Unorm) {
      diagnostic_ = "MacMetalRenderFrameExecutor readback blocked: FinalFrameSurface must be BGRA8Unorm with positive dimensions.";
      return false;
    }
    const size_t compactRowBytes = static_cast<size_t>(width) * 4;
    const size_t alignedRowBytes = ((compactRowBytes + 255) / 256) * 256;
    id<MTLBuffer> readback = [device_ newBufferWithLength:alignedRowBytes * static_cast<size_t>(height)
                                                  options:MTLResourceStorageModeShared];
    if (readback == nil) {
      diagnostic_ = "MacMetalRenderFrameExecutor readback blocked: shared readback buffer allocation failed.";
      return false;
    }
    id<MTLCommandBuffer> commandBuffer = [commandQueue_ commandBuffer];
    id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
    if (commandBuffer == nil || blit == nil) {
      diagnostic_ = "MacMetalRenderFrameExecutor readback blocked: Metal blit encoder creation failed.";
      return false;
    }
    [blit copyFromTexture:texture
              sourceSlice:0
              sourceLevel:0
             sourceOrigin:MTLOriginMake(0, 0, 0)
               sourceSize:MTLSizeMake(width, height, 1)
                 toBuffer:readback
        destinationOffset:0
   destinationBytesPerRow:alignedRowBytes
 destinationBytesPerImage:alignedRowBytes * static_cast<size_t>(height)];
    [blit endEncoding];
    [commandBuffer commit];
    [commandBuffer waitUntilCompleted];
    if (commandBuffer.status == MTLCommandBufferStatusError) {
      diagnostic_ = "MacMetalRenderFrameExecutor readback blocked: Metal blit command failed.";
      if (commandBuffer.error != nil && commandBuffer.error.localizedDescription != nil) {
        diagnostic_ += " ";
        diagnostic_ += ToStdString(commandBuffer.error.localizedDescription);
      }
      return false;
    }
    out.assign(compactRowBytes * static_cast<size_t>(height), 0);
    const uint8_t* source = static_cast<const uint8_t*>(readback.contents);
    for (int y = 0; y < height; ++y) {
      std::memcpy(out.data() + static_cast<size_t>(y) * compactRowBytes,
                  source + static_cast<size_t>(y) * alignedRowBytes,
                  compactRowBytes);
    }
    bytesPerRow = compactRowBytes;
    return true;
  }

  void invalidateProjectResources() {
    imageTextures_.clear();
    generatedTextures_.clear();
    temporalFXTextures_.clear();
    temporalFXTextureOrder_.clear();
    videoProviders_.clear();
    if (textureCache_ != nullptr) {
      CVMetalTextureCacheFlush(textureCache_, 0);
    }
  }

  void prewarmStaticImageTextures(const makelab::imgui::WorkspaceViewState& workspace) {
    if (!workspace.opened) {
      return;
    }
    const auto ir = BuildHyperFrameIR(workspace);
    for (const auto& layer : ir) {
      if (layer.kind != NativeNodeKind::Image || layer.asset == nullptr || layer.clip == nullptr) {
        continue;
      }
      const double width = layer.clip->width > 0.0 ? layer.clip->width : workspace.width;
      const double height = layer.clip->height > 0.0 ? layer.clip->height : workspace.height;
      (void)imageTexture(workspace, *layer.asset, width, height);
    }
  }

  void prewarmVideoTextures(const makelab::imgui::WorkspaceViewState& workspace,
                            int framesPerClip = 18,
                            const std::function<bool()>& shouldContinue = {}) {
    if (!workspace.opened || textureCache_ == nullptr) {
      return;
    }
    const auto ir = BuildHyperFrameIR(workspace);
    for (const auto& layer : ir) {
      if (shouldContinue && !shouldContinue()) {
        break;
      }
      if (layer.kind != NativeNodeKind::Video || layer.asset == nullptr || layer.clip == nullptr) {
        continue;
      }
      NSURL* url = assetURL(workspace, *layer.asset);
      if (url == nil) {
        continue;
      }
      auto provider = videoProviders_.find(layer.clip->id);
      if (provider == videoProviders_.end()) {
        provider = videoProviders_.emplace(layer.clip->id, std::make_unique<RealtimeVideoSourceProvider>(url)).first;
      }
      const int clipFrames = static_cast<int>(std::min<int64_t>(
          std::max<int64_t>(1, layer.clip->durationFrames),
          static_cast<int64_t>(std::max(1, framesPerClip))));
      provider->second->prewarm(layer.clip->trimInSeconds, workspace.fps, clipFrames, textureCache_, shouldContinue);
    }
  }

  void prewarmGeneratedVisualTextures(const makelab::imgui::WorkspaceViewState& workspace) {
    if (!workspace.opened) {
      return;
    }
    const auto ir = BuildHyperFrameIR(workspace);
    std::unordered_set<std::string> warmedClips;
    for (const auto& layer : ir) {
      if (layer.clip == nullptr) {
        continue;
      }
      if (layer.kind != NativeNodeKind::Text &&
          layer.kind != NativeNodeKind::Shape &&
          layer.kind != NativeNodeKind::Background) {
        continue;
      }
      if (!warmedClips.insert(layer.clip->id).second) {
        continue;
      }
      const auto descriptor = EvaluateFrameDescriptor(workspace, ir, layer.clip->startFrame);
      const auto graph = CompileRenderGraph(workspace, descriptor);
      for (const auto& node : graph) {
        if (node.frameNode.layer.clip == layer.clip) {
          (void)sourceTexture(workspace, node, false);
          break;
        }
      }
    }
  }

  void prewarmScrubVideoWindow(const makelab::imgui::WorkspaceViewState& workspace,
                               int64_t frameIndex,
                               int radiusFrames = 3) {
    if (!workspace.opened || textureCache_ == nullptr) {
      return;
    }
    const auto ir = BuildHyperFrameIR(workspace);
    const auto descriptor = EvaluateFrameDescriptor(workspace, ir, makelab::timeline::ClampFrame(frameIndex, workspace.durationFrames));
    const double stableFps = std::max(1.0, workspace.fps);
    const int radius = std::clamp(radiusFrames, 0, 8);
    for (const auto& node : descriptor) {
      if (node.layer.kind != NativeNodeKind::Video || node.layer.asset == nullptr || node.layer.clip == nullptr) {
        continue;
      }
      NSURL* url = assetURL(workspace, *node.layer.asset);
      if (url == nil) {
        continue;
      }
      auto provider = videoProviders_.find(node.layer.clip->id);
      if (provider == videoProviders_.end()) {
        provider = videoProviders_.emplace(node.layer.clip->id, std::make_unique<RealtimeVideoSourceProvider>(url)).first;
      }
      const double startMediaTime = std::max(0.0, node.mediaTime - static_cast<double>(radius) / stableFps);
      provider->second->prewarm(startMediaTime, stableFps, radius * 2 + 1, textureCache_);
    }
  }

  void prewarmLayerActivationFrames(const makelab::imgui::WorkspaceViewState& workspace,
                                    int maxFrames = 96,
                                    const std::function<bool()>& shouldContinue = {}) {
    if (!workspace.opened) {
      return;
    }
    const int64_t durationFrames = std::max<int64_t>(1, workspace.durationFrames);
    const auto ir = BuildHyperFrameIR(workspace);
    std::vector<int64_t> candidateFrames;
    candidateFrames.reserve(ir.size() * 4);
    auto addFrame = [&](int64_t frameIndex) {
      candidateFrames.push_back(makelab::timeline::ClampFrame(frameIndex, durationFrames));
    };
    for (const auto& layer : ir) {
      if (layer.kind == NativeNodeKind::Audio || layer.clip == nullptr) {
        continue;
      }
      const int64_t startFrame = std::max<int64_t>(0, layer.clip->startFrame);
      const int64_t endFrame = std::max<int64_t>(startFrame + 1, startFrame + std::max<int64_t>(1, layer.clip->durationFrames));
      addFrame(startFrame);
      addFrame(startFrame + 1);
      addFrame(endFrame - 1);
      addFrame(endFrame);
      for (const auto& frame : layer.clip->animationFrames) {
        const int64_t keyframe = startFrame + makelab::timeline::SecondsToFrameRound(frame.time, workspace.frameRate);
        addFrame(keyframe - 1);
        addFrame(keyframe);
        addFrame(keyframe + 1);
      }
      for (const auto& effect : layer.clip->effects) {
        const int64_t activeStart = startFrame + makelab::timeline::SecondsToFrameRound(effect.activeStartSeconds, workspace.frameRate);
        addFrame(activeStart - 1);
        addFrame(activeStart);
        addFrame(activeStart + 1);
        if (effect.kind == "transformMotionBlur") {
          addFrame(activeStart + 2);
          addFrame(activeStart + 3);
          addFrame(activeStart + 4);
        }
        if (std::isfinite(effect.activeEndSeconds)) {
          const int64_t activeEnd = startFrame + makelab::timeline::SecondsToFrameRound(effect.activeEndSeconds, workspace.frameRate);
          addFrame(activeEnd - 1);
          addFrame(activeEnd);
          addFrame(activeEnd + 1);
        }
      }
    }
    std::sort(candidateFrames.begin(), candidateFrames.end());
    candidateFrames.erase(std::unique(candidateFrames.begin(), candidateFrames.end()), candidateFrames.end());
    if (maxFrames > 0 && static_cast<int>(candidateFrames.size()) > maxFrames) {
      candidateFrames.resize(static_cast<size_t>(maxFrames));
    }
    uint64_t generation = 0xE000000000000000ULL;
    for (int64_t frameIndex : candidateFrames) {
      if (shouldContinue && !shouldContinue()) {
        break;
      }
      @autoreleasepool {
        prewarmScrubVideoWindow(workspace, frameIndex, 1);
        (void)render(workspace, frameIndex, generation++, false, true);
      }
    }
  }

 private:
  id<MTLDevice> device_;
  id<MTLCommandQueue> commandQueue_;
  CVMetalTextureCacheRef textureCache_ = nullptr;
  MTKTextureLoader* textureLoader_ = nil;
  id<MTLRenderPipelineState> pipeline_ = nil;
  id<MTLRenderPipelineState> premultipliedPipeline_ = nil;
  id<MTLRenderPipelineState> shapePipeline_ = nil;
  id<MTLRenderPipelineState> additiveFloatPipeline_ = nil;
  id<MTLRenderPipelineState> motionBlurBatchPipeline_ = nil;
  id<MTLComputePipelineState> motionTilePipeline_ = nil;
  id<MTLComputePipelineState> gaussianBlurPipeline_ = nil;
  id<MTLTexture> finalTexture_ = nil;
  std::vector<id<MTLTexture>> finalTexturePool_;
  size_t finalTexturePoolCursor_ = 0;
  int finalWidth_ = 0;
  int finalHeight_ = 0;
  std::unordered_map<std::string, id<MTLTexture>> imageTextures_;
  std::unordered_map<std::string, id<MTLTexture>> generatedTextures_;
  std::unordered_map<std::string, id<MTLTexture>> temporalFXTextures_;
  std::deque<std::string> temporalFXTextureOrder_;
  std::unordered_map<std::string, std::unique_ptr<RealtimeVideoSourceProvider>> videoProviders_;
  std::string diagnostic_;

  std::unordered_map<std::string, makelab::imgui::AssetItem> assetIndex(const makelab::imgui::WorkspaceViewState& workspace) {
    std::unordered_map<std::string, makelab::imgui::AssetItem> index;
    for (const auto& asset : workspace.assets) {
      index[asset.id] = asset;
    }
    return index;
  }

  void ensureFinalTexture(int width, int height) {
    width = std::max(1, width);
    height = std::max(1, height);
    static constexpr size_t kFinalSurfacePoolSize = 3;
    if (finalTexturePool_.size() == kFinalSurfacePoolSize && finalWidth_ == width && finalHeight_ == height) {
      finalTexture_ = finalTexturePool_[finalTexturePoolCursor_ % finalTexturePool_.size()];
      finalTexturePoolCursor_ = (finalTexturePoolCursor_ + 1) % finalTexturePool_.size();
      return;
    }
    finalTexturePool_.clear();
    finalTexture_ = nil;
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModePrivate;
    for (size_t index = 0; index < kFinalSurfacePoolSize; ++index) {
      id<MTLTexture> texture = [device_ newTextureWithDescriptor:descriptor];
      if (texture == nil) {
        finalTexturePool_.clear();
        finalTexture_ = nil;
        finalWidth_ = 0;
        finalHeight_ = 0;
        return;
      }
      finalTexturePool_.push_back(texture);
    }
    finalWidth_ = width;
    finalHeight_ = height;
    finalTexturePoolCursor_ = 1;
    finalTexture_ = finalTexturePool_.front();
  }

  id<MTLTexture> makeIntermediateTexture(int width, int height) {
    width = std::max(1, width);
    height = std::max(1, height);
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite | MTLTextureUsageRenderTarget;
    descriptor.storageMode = MTLStorageModePrivate;
    return [device_ newTextureWithDescriptor:descriptor];
  }

  id<MTLTexture> makeAccumulationTexture(int width, int height) {
    width = std::max(1, width);
    height = std::max(1, height);
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA16Float
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageRenderTarget;
    descriptor.storageMode = MTLStorageModePrivate;
    return [device_ newTextureWithDescriptor:descriptor];
  }

  double normalizeMotionTileExpansion(double raw, double fallback = 1.0) const {
    if (!std::isfinite(raw) || raw <= 0.0) {
      return fallback;
    }
    const double factor = raw > 10.0 ? raw / 100.0 : (raw < 1.0 ? 1.0 + raw : raw);
    return std::clamp(factor, 1.0, 8.0);
  }

  uint32_t motionTileMode(const std::string& value) const {
    if (value == "repeat") return 1;
    if (value == "clamp") return 2;
    return 0;
  }

  std::string temporalFXCacheKey(const NativeFXPass& pass,
                                 const NativeRenderGraphNode& node,
                                 double timeSeconds,
                                 int width,
                                 int height) const {
    const auto* clip = node.frameNode.layer.clip;
    std::ostringstream key;
    key << "temporal|" << pass.id << "|" << (clip ? clip->id : "no_clip") << "|"
        << std::fixed << std::setprecision(6) << timeSeconds << "|"
        << width << "x" << height << "|"
        << node.x << "," << node.y << "," << node.width << "," << node.height << ","
        << node.rotationDegrees << "," << node.scaleX << "," << node.scaleY << ","
        << node.opacity << "|"
        << PassString(pass, "quality", "auto") << "|"
        << PassNumber(pass, "samples", -1.0) << "|"
        << PassNumber(pass, "shutterAngle", PassNumber(pass, "shutter", 1.0) * 180.0) << "|"
        << PassNumber(pass, "shutterPhase", -9999.0) << "|"
        << PassNumber(pass, "strength", PassNumber(pass, "amount", 1.0));
    return key.str();
  }

  void cacheTemporalFXTexture(const std::string& key, id<MTLTexture> texture) {
    if (key.empty() || texture == nil || temporalFXTextures_.find(key) != temporalFXTextures_.end()) {
      return;
    }
    temporalFXTextures_[key] = texture;
    temporalFXTextureOrder_.push_back(key);
    constexpr size_t kMaxTemporalFXTextures = 18;
    while (temporalFXTextureOrder_.size() > kMaxTemporalFXTextures) {
      const std::string evict = temporalFXTextureOrder_.front();
      temporalFXTextureOrder_.pop_front();
      temporalFXTextures_.erase(evict);
    }
  }

  std::vector<NativeFXPass> passesForClip(const NativeFXPassGraph& fxPassGraph, const std::string& clipId) const {
    std::vector<NativeFXPass> passes;
    for (const auto& pass : fxPassGraph.passes) {
      if (pass.clipId == clipId) {
        passes.push_back(pass);
      }
    }
    std::sort(passes.begin(), passes.end(), [](const auto& left, const auto& right) {
      return left.order < right.order;
    });
    return passes;
  }

  const NativeFXPass* transformMotionBlurPassForClip(const NativeFXPassGraph& fxPassGraph, const std::string& clipId) const {
    for (const auto& pass : fxPassGraph.passes) {
      if (pass.clipId == clipId && pass.kind == "transformMotionBlur") {
        return &pass;
      }
    }
    return nullptr;
  }

  NativeRenderGraphNode fullscreenNode(const NativeRenderGraphNode& source,
                                       const makelab::imgui::WorkspaceViewState& workspace) const {
    NativeRenderGraphNode node = source;
    node.x = 0.0;
    node.y = 0.0;
    node.width = std::max(1, workspace.width);
    node.height = std::max(1, workspace.height);
    node.anchorX = 0.0;
    node.anchorY = 0.0;
    node.opacity = 1.0;
    node.rotationDegrees = 0.0;
    node.scaleX = 1.0;
    node.scaleY = 1.0;
    node.skewXDegrees = 0.0;
    node.skewYDegrees = 0.0;
    node.cornerRadiusTopLeft = 0.0;
    node.cornerRadiusTopRight = 0.0;
    node.cornerRadiusBottomRight = 0.0;
    node.cornerRadiusBottomLeft = 0.0;
    node.borderEnabled = false;
    node.shadowEnabled = false;
    return node;
  }

  std::vector<std::pair<double, double>> layerCorners(const NativeRenderGraphNode& node) const {
    const double centerX = node.x + node.width * node.anchorX;
    const double centerY = node.y + node.height * node.anchorY;
    const double left = -node.width * node.anchorX;
    const double right = node.width * (1.0 - node.anchorX);
    const double top = -node.height * node.anchorY;
    const double bottom = node.height * (1.0 - node.anchorY);
    const double radians = node.rotationDegrees * M_PI / 180.0;
    const double skewX = std::tan(node.skewXDegrees * M_PI / 180.0);
    const double skewY = std::tan(node.skewYDegrees * M_PI / 180.0);
    const double c = std::cos(radians);
    const double s = std::sin(radians);
    auto point = [&](double localX, double localY) -> std::pair<double, double> {
      const double scaledX = localX * node.scaleX;
      const double scaledY = localY * node.scaleY;
      const double skewedX = scaledX + scaledY * skewX;
      const double skewedY = scaledY + scaledX * skewY;
      return {
          centerX + skewedX * c - skewedY * s,
          centerY + skewedX * s + skewedY * c
      };
    };
    return {
        point(left, top),
        point(right, top),
        point(right, bottom),
        point(left, bottom),
    };
  }

  bool nodeForClipAtTime(const makelab::imgui::WorkspaceViewState& workspace,
                         const std::vector<NativeIRLayer>& ir,
                         const std::string& clipId,
                         double timeSeconds,
                         NativeRenderGraphNode& out) const {
    const double safeTime = std::max(0.0, timeSeconds);
    for (const auto& layer : ir) {
      const auto* clip = layer.clip;
      if (clip == nullptr || clip->id != clipId || layer.track == nullptr || layer.track->hidden) {
        continue;
      }
      if (safeTime + 0.0001 < clip->startSeconds || safeTime >= clip->startSeconds + clip->durationSeconds) {
        return false;
      }
      NativeFrameDescriptorNode frameNode;
      frameNode.layer = layer;
      frameNode.localTime = std::max(0.0, safeTime - clip->startSeconds);
      frameNode.mediaTime = std::max(0.0, frameNode.localTime + clip->trimInSeconds);
      out = CompileRenderGraphNode(workspace, EvaluateAnimation(frameNode));
      return true;
    }
    return false;
  }

  double maxPixelDisplacement(const NativeRenderGraphNode& reference,
                              const makelab::imgui::WorkspaceViewState& workspace,
                              const std::vector<NativeIRLayer>& ir,
                              const std::vector<double>& sampleTimes) const {
    const auto referenceCorners = layerCorners(reference);
    const auto* clip = reference.frameNode.layer.clip;
    if (clip == nullptr) {
      return 0.0;
    }
    double displacement = 0.0;
    for (double sampleTime : sampleTimes) {
      NativeRenderGraphNode sample;
      if (!nodeForClipAtTime(workspace, ir, clip->id, sampleTime, sample)) {
        continue;
      }
      const auto sampleCorners = layerCorners(sample);
      const size_t count = std::min(referenceCorners.size(), sampleCorners.size());
      for (size_t index = 0; index < count; ++index) {
        displacement = std::max(displacement,
                                std::hypot(sampleCorners[index].first - referenceCorners[index].first,
                                           sampleCorners[index].second - referenceCorners[index].second));
      }
    }
    return displacement;
  }

  int requestedMotionBlurSampleCount(const NativeFXPass& pass, int fallback) const {
    const std::string quality = PassString(pass, "quality", "auto");
    if (quality == "draft") return 8;
    if (quality == "preview") return 16;
    if (quality == "high") return 48;
    if (quality == "cinematic" || quality == "best" || quality == "ultra") return 96;
    return std::max(2, static_cast<int>(std::round(PassNumber(pass, "samples", fallback))));
  }

  double motionBlurReconstructionWeight(double progress, const std::string& curve) const {
    if (curve == "uniform" || curve == "linear") {
      return 1.0;
    }
    if (curve == "centerWeighted") {
      const double distance = std::abs(progress - 0.5) * 2.0;
      return std::max(0.01, 1.0 - distance * 0.55);
    }
    const double a0 = 0.35875;
    const double a1 = 0.48829;
    const double a2 = 0.14128;
    const double a3 = 0.01168;
    const double x = 2.0 * M_PI * progress;
    return std::max(0.001, a0 - a1 * std::cos(x) + a2 * std::cos(2.0 * x) - a3 * std::cos(3.0 * x));
  }

  std::vector<NativeMotionBlurSample> createMotionBlurSamples(const NativeFXPass& pass,
                                                              const NativeRenderGraphNode& node,
                                                              const makelab::imgui::WorkspaceViewState& workspace,
                                                              const std::vector<NativeIRLayer>& ir,
                                                              double frameTime,
                                                              bool playing,
                                                              NativeRenderIntent intent) const {
    const double fps = std::max(1.0, workspace.fps);
    const double frameDuration = 1.0 / fps;
    const double shutterAngle = std::clamp(PassNumber(pass, "shutterAngle", PassNumber(pass, "shutter", 1.0) * 180.0), 0.0, 1440.0);
    const double shutterPhase = std::clamp(PassNumber(pass, "shutterPhase", -shutterAngle * 0.5), -720.0, 720.0);
    const double amount = std::clamp(PassNumber(pass, "amount", PassNumber(pass, "strength", 1.0)), 0.0, 10.0);
    const double shutterDuration = frameDuration * shutterAngle / 360.0 * amount;
    const double centerTime = frameTime + frameDuration * shutterPhase / 360.0;
    const double startTime = std::max(0.0, centerTime - shutterDuration * 0.5);
    const double endTime = std::max(startTime, centerTime + shutterDuration * 0.5);
    const std::vector<double> displacementTimes = {
        startTime,
        startTime + shutterDuration * 0.25,
        centerTime,
        startTime + shutterDuration * 0.75,
        endTime,
    };
    const double displacement = maxPixelDisplacement(node, workspace, ir, displacementTimes);
    if (displacement < 0.25 || shutterDuration <= 0.000001) {
      return {NativeMotionBlurSample{frameTime, 1.0}};
    }
    double minRotation = node.rotationDegrees;
    double maxRotation = node.rotationDegrees;
    for (double sampleTime : displacementTimes) {
      NativeRenderGraphNode sample;
      const auto* clip = node.frameNode.layer.clip;
      if (clip != nullptr && nodeForClipAtTime(workspace, ir, clip->id, sampleTime, sample)) {
        minRotation = std::min(minRotation, sample.rotationDegrees);
        maxRotation = std::max(maxRotation, sample.rotationDegrees);
      }
    }
    const double angularSweep = std::max(0.0, maxRotation - minRotation);
    const int displacementSamples = static_cast<int>(std::ceil(std::max(0.0, displacement) / 1.35));
    const int shutterSamples = static_cast<int>(std::ceil(std::max(0.0, shutterAngle * std::max(1.0, amount)) / 18.0));
    const int angularSamples = static_cast<int>(std::ceil(angularSweep / 2.0));
    const double playbackBudget = PassNumber(pass, "playbackSampleBudget", static_cast<double>(pass.sampleBudget));
    const double scrubBudget = PassNumber(pass, "scrubInteractiveSampleBudget", playbackBudget);
    const double previewBudget = PassNumber(pass, "pausedPreviewSampleBudget", static_cast<double>(pass.sampleBudget));
    const double selectedBudget = playing || intent == NativeRenderIntent::PlaybackRealtime
                                      ? playbackBudget
                                      : (intent == NativeRenderIntent::ScrubInteractive ? scrubBudget : previewBudget);
    const int runtimeBudget = std::max(2, static_cast<int>(std::llround(selectedBudget)));
    const int requested = requestedMotionBlurSampleCount(pass, std::max(16, static_cast<int>(std::round(runtimeBudget * 0.66))));
    const int selectedCount = std::clamp(std::max({2, requested, displacementSamples, shutterSamples, angularSamples}),
                                         2,
                                         std::max(2, runtimeBudget));
    const std::string curve = PassString(pass, "sampleCurve", "filmic");
    std::vector<NativeMotionBlurSample> samples;
    samples.reserve(static_cast<size_t>(selectedCount));
    double totalWeight = 0.0;
    for (int index = 0; index < selectedCount; ++index) {
      const double progress = selectedCount == 1 ? 0.5 : static_cast<double>(index) / static_cast<double>(selectedCount - 1);
      const double weight = motionBlurReconstructionWeight(progress, curve);
      samples.push_back({startTime + progress * (endTime - startTime), weight});
      totalWeight += weight;
    }
    totalWeight = std::max(0.0001, totalWeight);
    for (auto& sample : samples) {
      sample.weight /= totalWeight;
    }
    return samples;
  }

  NativeRenderGraphNode scaledNode(const NativeRenderGraphNode& node, double boundsScaleX, double boundsScaleY) const {
    if (std::abs(boundsScaleX - 1.0) <= 0.0001 && std::abs(boundsScaleY - 1.0) <= 0.0001) {
      return node;
    }
    NativeRenderGraphNode scaled = node;
    const double centerX = node.x + node.width * node.anchorX;
    const double centerY = node.y + node.height * node.anchorY;
    scaled.width = std::max(1.0, node.width * boundsScaleX);
    scaled.height = std::max(1.0, node.height * boundsScaleY);
    scaled.x = centerX - scaled.width * node.anchorX;
    scaled.y = centerY - scaled.height * node.anchorY;
    return scaled;
  }

  NativeRenderGraphNode expandedNode(const NativeRenderGraphNode& node, double expansion) const {
    if (!std::isfinite(expansion) || std::abs(expansion) <= 0.0001) {
      return node;
    }
    NativeRenderGraphNode expanded = node;
    const double centerX = node.x + node.width * node.anchorX;
    const double centerY = node.y + node.height * node.anchorY;
    expanded.width = std::max(1.0, node.width + expansion * 2.0);
    expanded.height = std::max(1.0, node.height + expansion * 2.0);
    expanded.x = centerX - expanded.width * node.anchorX;
    expanded.y = centerY - expanded.height * node.anchorY;
    expanded.cornerRadiusTopLeft = std::max(0.0, node.cornerRadiusTopLeft + expansion);
    expanded.cornerRadiusTopRight = std::max(0.0, node.cornerRadiusTopRight + expansion);
    expanded.cornerRadiusBottomRight = std::max(0.0, node.cornerRadiusBottomRight + expansion);
    expanded.cornerRadiusBottomLeft = std::max(0.0, node.cornerRadiusBottomLeft + expansion);
    return expanded;
  }

  uint32_t shapeKindValue(const NativeRenderGraphNode& node) const {
    const auto* clip = node.frameNode.layer.clip;
    if (clip == nullptr || node.frameNode.layer.kind != NativeNodeKind::Shape) return 0;
    if (clip->shapeKind == "circle" || clip->shapeKind == "ellipse") return 1;
    if (clip->shapeKind == "line") return 2;
    if (clip->shapeKind == "arrow") return 3;
    return 0;
  }

  NativeResolvedTexture applyMotionTile(id<MTLTexture> source, const NativeFXPass& pass, id<MTLCommandBuffer> commandBuffer) {
    (void)commandBuffer;
    const double fallbackExpansion = normalizeMotionTileExpansion(PassNumber(pass, "expansion", 1.0));
    const double expansionX = normalizeMotionTileExpansion(PassNumber(pass, "expansionX", PassNumber(pass, "outputWidth", fallbackExpansion)), fallbackExpansion);
    const double expansionY = normalizeMotionTileExpansion(PassNumber(pass, "expansionY", PassNumber(pass, "outputHeight", fallbackExpansion)), fallbackExpansion);
    if (expansionX <= 1.0001 && expansionY <= 1.0001) {
      return {source, 1.0, 1.0};
    }
    const double effectiveExpansionX = std::clamp(expansionX, 1.0, 8.0);
    const double effectiveExpansionY = std::clamp(expansionY, 1.0, 8.0);
    return {source,
            effectiveExpansionX,
            effectiveExpansionY,
            false,
            effectiveExpansionX,
            effectiveExpansionY,
            motionTileMode(PassString(pass, "mode", "mirror"))};
  }

  id<MTLTexture> applyGaussianBlur(id<MTLTexture> source, const NativeFXPass& pass, id<MTLCommandBuffer> commandBuffer) {
    if (!gaussianBlurPipeline_) {
      if (diagnostic_.empty()) {
        diagnostic_ = "FXPassGraph diagnostic: gaussianBlur reached native preview, but Metal gaussianBlur pipeline is not ready.";
      }
      return source;
    }
    const double radius = std::clamp(PassNumber(pass, "radius", PassNumber(pass, "blur", 0.0)), 0.0, 64.0);
    if (radius < 0.01) {
      return source;
    }
    id<MTLTexture> horizontal = makeIntermediateTexture(source.width, source.height);
    id<MTLTexture> vertical = makeIntermediateTexture(source.width, source.height);
    if (!horizontal || !vertical) {
      return source;
    }
    auto dispatch = [&](id<MTLTexture> input, id<MTLTexture> output, vector_float2 direction) {
      id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
      if (!encoder) {
        return;
      }
      MacGaussianBlurUniforms uniforms{static_cast<float>(radius), direction, 0.0f};
      [encoder setComputePipelineState:gaussianBlurPipeline_];
      [encoder setTexture:input atIndex:0];
      [encoder setTexture:output atIndex:1];
      [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
      const NSUInteger width = gaussianBlurPipeline_.threadExecutionWidth;
      const NSUInteger height = std::max<NSUInteger>(1, gaussianBlurPipeline_.maxTotalThreadsPerThreadgroup / width);
      [encoder dispatchThreads:MTLSizeMake(input.width, input.height, 1)
         threadsPerThreadgroup:MTLSizeMake(width, height, 1)];
      [encoder endEncoding];
    };
    dispatch(source, horizontal, vector_float2{1.0f, 0.0f});
    dispatch(horizontal, vertical, vector_float2{0.0f, 1.0f});
    return vertical;
  }

  NativeResolvedTexture applyFXPasses(id<MTLTexture> source,
                                      const NativeRenderGraphNode& node,
                                      const NativeFXPassGraph& fxPassGraph,
                                      id<MTLCommandBuffer> commandBuffer,
                                      bool includePreTransform = true,
                                      bool includePostTransform = true) {
    const auto* clip = node.frameNode.layer.clip;
    if (clip == nullptr) {
      return {source, 1.0, 1.0};
    }
    id<MTLTexture> current = source;
    double boundsScaleX = 1.0;
    double boundsScaleY = 1.0;
    double uvExpansionX = 1.0;
    double uvExpansionY = 1.0;
    uint32_t tileMode = 2;
    for (const auto& pass : passesForClip(fxPassGraph, clip->id)) {
      if (pass.kind == "motionTileSampler") {
        if (!includePreTransform) {
          continue;
        }
        NativeResolvedTexture resolved = applyMotionTile(current, pass, commandBuffer);
        current = resolved.texture ?: current;
        boundsScaleX *= resolved.boundsScaleX;
        boundsScaleY *= resolved.boundsScaleY;
        uvExpansionX *= resolved.uvExpansionX;
        uvExpansionY *= resolved.uvExpansionY;
        tileMode = resolved.tileMode;
      } else if (pass.kind == "gaussianBlur") {
        if (!includePostTransform) {
          continue;
        }
        current = applyGaussianBlur(current, pass, commandBuffer);
      } else if (pass.kind == "transformMotionBlur") {
        continue;
      }
    }
    return {current, boundsScaleX, boundsScaleY, false, uvExpansionX, uvExpansionY, tileMode};
  }

  id<MTLTexture> renderMotionBlurTexture(const makelab::imgui::WorkspaceViewState& workspace,
                                         const std::vector<NativeIRLayer>& ir,
                                         const NativeRenderGraphNode& node,
                                         const NativeFXPassGraph& fxPassGraph,
                                         const NativeFXPass& pass,
                                         double timeSeconds,
                                         bool playing,
                                         NativeRenderIntent intent,
                                         id<MTLCommandBuffer> commandBuffer) {
    const auto* clip = node.frameNode.layer.clip;
    if (clip == nullptr || !additiveFloatPipeline_) {
      return nil;
    }
    const bool realtimeIntent = playing ||
                                intent == NativeRenderIntent::PlaybackRealtime ||
                                intent == NativeRenderIntent::ScrubInteractive;
    const bool enableTemporalCache = !realtimeIntent;
    const std::string cacheKey = temporalFXCacheKey(pass, node, timeSeconds, workspace.width, workspace.height);
    if (enableTemporalCache) {
      auto cached = temporalFXTextures_.find(cacheKey);
      if (cached != temporalFXTextures_.end() && cached->second != nil) {
        return cached->second;
      }
    }
    id<MTLTexture> source = sourceTexture(workspace, node, realtimeIntent);
    if (!source) {
      return nil;
    }
    NativeResolvedTexture resolvedSource = applyFXPasses(source, node, fxPassGraph, commandBuffer, true, false);
    resolvedSource.texture = resolvedSource.texture ?: source;
    resolvedSource.premultiplied = false;
    const auto samples = createMotionBlurSamples(pass, node, workspace, ir, timeSeconds, playing, intent);
    if (samples.empty()) {
      return nil;
    }
    std::vector<std::pair<NativeRenderGraphNode, NativeResolvedTexture>> sampleTextures;
    sampleTextures.reserve(samples.size());
    for (const auto& sample : samples) {
      NativeRenderGraphNode sampleNode;
      if (!nodeForClipAtTime(workspace, ir, clip->id, sample.time, sampleNode)) {
        continue;
      }
      sampleNode.opacity = std::clamp(sampleNode.opacity * sample.weight, 0.0, 1.0);
      sampleTextures.emplace_back(sampleNode, resolvedSource);
    }
    if (sampleTextures.empty()) {
      return nil;
    }
    id<MTLTexture> accumulation = makeAccumulationTexture(workspace.width, workspace.height);
    if (!accumulation) {
      return nil;
    }
    MTLRenderPassDescriptor* blurPass = [MTLRenderPassDescriptor renderPassDescriptor];
    blurPass.colorAttachments[0].texture = accumulation;
    blurPass.colorAttachments[0].loadAction = MTLLoadActionClear;
    blurPass.colorAttachments[0].storeAction = MTLStoreActionStore;
    blurPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    id<MTLRenderCommandEncoder> blurEncoder = [commandBuffer renderCommandEncoderWithDescriptor:blurPass];
    if (!blurEncoder) {
      return nil;
    }
    const NativeResolvedTexture batchResolved = sampleTextures.front().second;
    if (motionBlurBatchPipeline_ && batchResolved.texture) {
      std::vector<MacMotionBlurVertex> vertices;
      vertices.reserve(sampleTextures.size() * 6);
      for (const auto& sample : sampleTextures) {
        if (!sample.second.texture) {
          continue;
        }
        const NativeRenderGraphNode drawNode = scaledNode(sample.first,
                                                          sample.second.boundsScaleX,
                                                          sample.second.boundsScaleY);
        for (const auto& vertex : quadVertices(drawNode, workspace)) {
          vertices.push_back(MacMotionBlurVertex{
              vertex.position,
              vertex.uv,
              static_cast<float>(std::clamp(drawNode.opacity, 0.0, 1.0)),
              0.0f,
          });
        }
      }
      if (!vertices.empty()) {
        const NativeRenderGraphNode uniformNode = scaledNode(node, batchResolved.boundsScaleX, batchResolved.boundsScaleY);
        MacPreviewUniforms uniforms{
            vector_float4{1.0f, 1.0f, 1.0f, 1.0f},
            cornerRadii(uniformNode),
            vector_float2{static_cast<float>(uniformNode.width), static_cast<float>(uniformNode.height)},
            vector_float2{static_cast<float>(std::max(1.0, batchResolved.uvExpansionX)),
                           static_cast<float>(std::max(1.0, batchResolved.uvExpansionY))},
            1.0f,
            0.0f,
            0,
            0,
            batchResolved.tileMode,
            0,
        };
        [blurEncoder setRenderPipelineState:motionBlurBatchPipeline_];
        [blurEncoder setVertexBytes:vertices.data() length:sizeof(MacMotionBlurVertex) * vertices.size() atIndex:0];
        [blurEncoder setFragmentTexture:batchResolved.texture atIndex:0];
        [blurEncoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
        [blurEncoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
      }
    } else {
      [blurEncoder setRenderPipelineState:additiveFloatPipeline_];
      for (const auto& sample : sampleTextures) {
        if (!sample.second.texture) {
          continue;
        }
        drawTexture(sample.second.texture,
                    scaledNode(sample.first, sample.second.boundsScaleX, sample.second.boundsScaleY),
                    workspace,
                    blurEncoder,
                    sample.second.uvExpansionX,
                    sample.second.uvExpansionY,
                    sample.second.tileMode);
      }
    }
    [blurEncoder endEncoding];
    if (enableTemporalCache) {
      cacheTemporalFXTexture(cacheKey, accumulation);
    }
    return accumulation;
  }

  NSURL* assetURL(const makelab::imgui::WorkspaceViewState& workspace, const makelab::imgui::AssetItem& asset) {
    NSString* root = [NSString stringWithUTF8String:workspace.folderPath.c_str()];
    NSString* relative = [NSString stringWithUTF8String:asset.path.c_str()];
    if (asset.path.empty()) {
      return nil;
    }
    return [[NSURL fileURLWithPath:root isDirectory:YES] URLByAppendingPathComponent:relative];
  }

  std::string fileCacheSignature(NSURL* url) {
    NSDictionary<NSFileAttributeKey, id>* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:url.path error:nil];
    if (attributes == nil) {
      return ToStdString(url.path);
    }
    const unsigned long long size = [attributes[NSFileSize] unsignedLongLongValue];
    const NSTimeInterval modified = [attributes[NSFileModificationDate] timeIntervalSince1970];
    std::ostringstream key;
    key << ToStdString(url.path) << "|" << std::fixed << modified << "|" << size;
    return key.str();
  }

  std::pair<int, int> rasterSizeForAsset(const makelab::imgui::WorkspaceViewState& workspace,
                                         const makelab::imgui::AssetItem& asset,
                                         double targetWidth,
                                         double targetHeight) const {
    const double widthSource = targetWidth > 0.0 ? targetWidth : (asset.width > 0 ? asset.width : workspace.width);
    const double heightSource = targetHeight > 0.0 ? targetHeight : (asset.height > 0 ? asset.height : workspace.height);
    const int maxTexture = 8192;
    const int width = std::clamp(static_cast<int>(std::ceil(widthSource)), 1, std::max(1, maxTexture));
    const int height = std::clamp(static_cast<int>(std::ceil(heightSource)), 1, std::max(1, maxTexture));
    return {width, height};
  }

  id<MTLTexture> textureFromRGBA8Bytes(const uint8_t* rgba,
                                       int width,
                                       int height,
                                       size_t bytesPerRow,
                                       const std::string& cacheKey) {
    if (rgba == nullptr || width <= 0 || height <= 0 || bytesPerRow < static_cast<size_t>(width) * 4) {
      return nil;
    }
    auto cached = imageTextures_.find(cacheKey);
    if (cached != imageTextures_.end()) {
      return cached->second;
    }
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                           width:width
                                                                                          height:height
                                                                                       mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModeShared;
    id<MTLTexture> texture = [device_ newTextureWithDescriptor:descriptor];
    if (texture == nil) {
      return nil;
    }
    [texture replaceRegion:MTLRegionMake2D(0, 0, width, height)
               mipmapLevel:0
                 withBytes:rgba
               bytesPerRow:bytesPerRow];
    if (imageTextures_.size() >= 256) {
      imageTextures_.clear();
    }
    imageTextures_[cacheKey] = texture;
    return texture;
  }

  id<MTLTexture> svgTexture(NSURL* url,
                            const makelab::imgui::WorkspaceViewState& workspace,
                            const makelab::imgui::AssetItem& asset,
                            double targetWidth,
                            double targetHeight) {
    const auto [width, height] = rasterSizeForAsset(workspace, asset, targetWidth, targetHeight);
    const std::string cacheKey = "svg|" + asset.id + "|" + fileCacheSignature(url) + "|" +
                                 std::to_string(width) + "x" + std::to_string(height);
    auto cached = imageTextures_.find(cacheKey);
    if (cached != imageTextures_.end()) {
      return cached->second;
    }
    std::unique_ptr<lunasvg::Document> document = lunasvg::Document::loadFromFile(ToStdString(url.path));
    if (!document) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor warning: SVG source could not be parsed for asset " + asset.id + ".";
      }
      return nil;
    }
    lunasvg::Bitmap bitmap = document->renderToBitmap(width, height, 0x00000000);
    if (bitmap.isNull() || bitmap.width() <= 0 || bitmap.height() <= 0 || bitmap.data() == nullptr) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor warning: SVG source rasterization produced no texture for asset " + asset.id + ".";
      }
      return nil;
    }
    bitmap.convertToRGBA();
    id<MTLTexture> texture = textureFromRGBA8Bytes(bitmap.data(),
                                                   bitmap.width(),
                                                   bitmap.height(),
                                                   static_cast<size_t>(bitmap.stride()),
                                                   cacheKey);
    if (!texture && diagnostic_.empty()) {
      diagnostic_ = "MacMetalRenderFrameExecutor warning: SVG raster texture upload failed for asset " + asset.id + ".";
    }
    return texture;
  }

  id<MTLTexture> imageTexture(const makelab::imgui::WorkspaceViewState& workspace,
                              const makelab::imgui::AssetItem& asset,
                              double targetWidth,
                              double targetHeight) {
    NSURL* url = assetURL(workspace, asset);
    if (!url) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor warning: asset " + asset.id + " has no accepted path.";
      }
      return nil;
    }
    if (IsSvgURL(url)) {
      return svgTexture(url, workspace, asset, targetWidth, targetHeight);
    }

    const std::string cacheKey = "image|" + asset.id + "|" + fileCacheSignature(url);
    auto cached = imageTextures_.find(cacheKey);
    if (cached != imageTextures_.end()) {
      return cached->second;
    }
    NSError* error = nil;
    id<MTLTexture> texture = [textureLoader_ newTextureWithContentsOfURL:url
                                                                 options:@{ MTKTextureLoaderOptionSRGB: @NO }
                                                                   error:&error];
    if (texture) {
      if (imageTextures_.size() >= 256) {
        imageTextures_.clear();
      }
      imageTextures_[cacheKey] = texture;
    } else if (diagnostic_.empty()) {
      diagnostic_ = "MacMetalRenderFrameExecutor warning: image source texture failed for asset " + asset.id + ".";
    }
    return texture;
  }

  id<MTLTexture> sourceTexture(const makelab::imgui::WorkspaceViewState& workspace,
                               const NativeRenderGraphNode& node,
                               bool playing) {
    const auto* clip = node.frameNode.layer.clip;
    const auto* asset = node.frameNode.layer.asset;
    switch (node.frameNode.layer.kind) {
      case NativeNodeKind::Video:
        if (clip != nullptr && asset != nullptr) {
          return videoTexture(workspace, *clip, *asset, node.frameNode.mediaTime, playing, workspace.fps);
        }
        break;
      case NativeNodeKind::Image:
        if (asset != nullptr) {
          return imageTexture(workspace, *asset, node.width, node.height);
        }
        break;
      case NativeNodeKind::Text:
        return textTexture(node);
      case NativeNodeKind::Shape:
      case NativeNodeKind::Background:
        return shapeTexture(node);
      case NativeNodeKind::Audio:
        return nil;
    }
    if (diagnostic_.empty() && clip != nullptr) {
      diagnostic_ = "RenderGraph diagnostic: node " + clip->id + " has no native source texture.";
    }
    return nil;
  }

  id<MTLTexture> textureFromCGImage(CGImageRef image, const std::string& cacheKey) {
    auto cached = generatedTextures_.find(cacheKey);
    if (cached != generatedTextures_.end()) {
      return cached->second;
    }
    if (image == nullptr) {
      return nil;
    }
    NSError* error = nil;
    id<MTLTexture> texture = [textureLoader_ newTextureWithCGImage:image
                                                           options:@{ MTKTextureLoaderOptionSRGB: @NO }
                                                             error:&error];
    if (texture) {
      if (generatedTextures_.size() >= 256) {
        generatedTextures_.clear();
      }
      generatedTextures_[cacheKey] = texture;
    } else if (diagnostic_.empty()) {
      diagnostic_ = "MacMetalRenderFrameExecutor warning: generated source texture failed.";
    }
    return texture;
  }

  id<MTLTexture> textTexture(const NativeRenderGraphNode& node) {
    const auto* clip = node.frameNode.layer.clip;
    if (clip == nullptr) {
      return nil;
    }
    const int width = std::max(1, static_cast<int>(std::ceil(node.width)));
    const int height = std::max(1, static_cast<int>(std::ceil(node.height)));
    const std::string key = "text|" + clip->id + "|" + clip->textContent + "|" + std::to_string(width) + "x" +
                            std::to_string(height) + "|" + clip->textFontFamily + "|" +
                            std::to_string(clip->textFontSize) + "|" + clip->textFontWeight + "|" + clip->textColor + "|" +
                            clip->textAlign + "|" + std::to_string(clip->textLineHeight) + "|" +
                            std::to_string(clip->textLetterSpacing) + "|" + clip->textStrokeColor + "|" +
                            std::to_string(clip->textStrokeWidth);
    auto cached = generatedTextures_.find(key);
    if (cached != generatedTextures_.end()) {
      return cached->second;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(nullptr, width, height, 8, 0, colorSpace,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (context == nullptr) {
      return nil;
    }
    CGContextClearRect(context, CGRectMake(0, 0, width, height));
    NSGraphicsContext* previous = [NSGraphicsContext currentContext];
    [NSGraphicsContext setCurrentContext:[NSGraphicsContext graphicsContextWithCGContext:context flipped:NO]];

    NSMutableParagraphStyle* paragraph = [[NSMutableParagraphStyle alloc] init];
    if (clip->textAlign == "left" || clip->textAlign == "start") {
      paragraph.alignment = NSTextAlignmentLeft;
    } else if (clip->textAlign == "right" || clip->textAlign == "end") {
      paragraph.alignment = NSTextAlignmentRight;
    } else {
      paragraph.alignment = NSTextAlignmentCenter;
    }
    const CGFloat fontSize = static_cast<CGFloat>(std::max(1.0, clip->textFontSize));
    const CGFloat lineHeight = static_cast<CGFloat>(std::max(0.1, clip->textLineHeight) * fontSize);
    paragraph.minimumLineHeight = lineHeight;
    paragraph.maximumLineHeight = lineHeight;
    NSFont* font = [NSFont fontWithName:[NSString stringWithUTF8String:clip->textFontFamily.c_str()] size:fontSize];
    if (font == nil) {
      const double weightValue = std::strtod(clip->textFontWeight.c_str(), nullptr);
      NSFontWeight weight = weightValue >= 700 ? NSFontWeightBold : (weightValue >= 500 ? NSFontWeightMedium : NSFontWeightRegular);
      font = [NSFont systemFontOfSize:fontSize weight:weight];
    }
    NSMutableDictionary* attributes = [@{
      NSFontAttributeName: font,
      NSForegroundColorAttributeName: NSColorFromHex(clip->textColor, 1.0),
      NSParagraphStyleAttributeName: paragraph
    } mutableCopy];
    if (std::abs(clip->textLetterSpacing) > 0.001) {
      attributes[NSKernAttributeName] = @(clip->textLetterSpacing);
    }
    if (clip->textStrokeWidth > 0.0) {
      attributes[NSStrokeColorAttributeName] = NSColorFromHex(clip->textStrokeColor, 1.0);
      attributes[NSStrokeWidthAttributeName] = @(-std::abs(clip->textStrokeWidth));
    }
    NSString* text = [NSString stringWithUTF8String:(clip->textContent.empty() ? "Text" : clip->textContent).c_str()];
    NSAttributedString* attributed = [[NSAttributedString alloc] initWithString:text attributes:attributes];
    NSRect measured = [attributed boundingRectWithSize:NSMakeSize(width, height)
                                               options:NSStringDrawingUsesLineFragmentOrigin | NSStringDrawingUsesFontLeading];
    const CGFloat measuredHeight = std::min<CGFloat>(height, std::ceil(measured.size.height));
    NSRect textRect = NSMakeRect(0, height * 0.5 - measuredHeight * 0.5, width, std::max<CGFloat>(measuredHeight, fontSize));
    if (textRect.origin.y < 0) {
      textRect = NSMakeRect(0, 0, width, height);
    }
    [attributed drawInRect:textRect];
    [NSGraphicsContext setCurrentContext:previous];

    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    id<MTLTexture> texture = textureFromCGImage(image, key);
    if (image != nullptr) {
      CGImageRelease(image);
    }
    return texture;
  }

  id<MTLTexture> shapeTexture(const NativeRenderGraphNode& node) {
    const auto* clip = node.frameNode.layer.clip;
    const std::string clipId = clip != nullptr ? clip->id : "background";
    const std::string kind = clip != nullptr ? clip->shapeKind : "rectangle";
    const int width = node.frameNode.layer.kind == NativeNodeKind::Background ? 1 : std::max(1, static_cast<int>(std::ceil(node.width)));
    const int height = node.frameNode.layer.kind == NativeNodeKind::Background ? 1 : std::max(1, static_cast<int>(std::ceil(node.height)));
    const std::string key = "shape|" + clipId + "|" + kind + "|" + std::to_string(width) + "x" + std::to_string(height) +
                            "|" + node.fillColor + "|" + std::to_string(node.fillOpacity) + "|" +
                            std::to_string(node.cornerRadiusTopLeft) + "|" + std::to_string(node.cornerRadiusTopRight) + "|" +
                            std::to_string(node.cornerRadiusBottomRight) + "|" + std::to_string(node.cornerRadiusBottomLeft);
    auto cached = generatedTextures_.find(key);
    if (cached != generatedTextures_.end()) {
      return cached->second;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(nullptr, width, height, 8, 0, colorSpace,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (context == nullptr) {
      return nil;
    }
    CGContextClearRect(context, CGRectMake(0, 0, width, height));
    CGContextSetFillColorWithColor(context, NSColorFromHex(node.fillColor, node.fillOpacity).CGColor);
    CGContextSetStrokeColorWithColor(context, NSColorFromHex(node.fillColor, node.fillOpacity).CGColor);
    if (kind == "circle") {
      CGContextFillEllipseInRect(context, CGRectMake(0, 0, width, height));
    } else if (kind == "line" || kind == "arrow") {
      CGContextSetLineWidth(context, std::max(2.0, node.height));
      CGContextMoveToPoint(context, 0, height * 0.5);
      CGContextAddLineToPoint(context, width, height * 0.5);
      CGContextStrokePath(context);
      if (kind == "arrow") {
        CGContextBeginPath(context);
        CGContextMoveToPoint(context, width, height * 0.5);
        CGContextAddLineToPoint(context, std::max(0, width - 18), std::max(0, height / 2 - 10));
        CGContextAddLineToPoint(context, std::max(0, width - 18), std::min(height, height / 2 + 10));
        CGContextClosePath(context);
        CGContextFillPath(context);
      }
    } else {
      CGPathRef path = CreateRoundedRectPath(CGRectMake(0, 0, width, height),
                                             node.cornerRadiusTopLeft,
                                             node.cornerRadiusTopRight,
                                             node.cornerRadiusBottomRight,
                                             node.cornerRadiusBottomLeft);
      CGContextAddPath(context, path);
      CGContextFillPath(context);
      CGPathRelease(path);
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    id<MTLTexture> texture = textureFromCGImage(image, key);
    if (image != nullptr) {
      CGImageRelease(image);
    }
    return texture;
  }

  id<MTLTexture> videoTexture(const makelab::imgui::WorkspaceViewState& workspace,
                              const makelab::imgui::ClipItem& clip,
                              const makelab::imgui::AssetItem& asset,
                              double mediaTime,
                              bool playing,
                              double fps) {
    NSURL* url = assetURL(workspace, asset);
    if (!url) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor warning: asset " + asset.id + " has no accepted path.";
      }
      return nil;
    }

    auto provider = videoProviders_.find(clip.id);
    if (provider == videoProviders_.end()) {
      provider = videoProviders_.emplace(clip.id, std::make_unique<RealtimeVideoSourceProvider>(url)).first;
    }
    provider->second->sync(mediaTime, playing, fps);
    id<MTLTexture> texture = provider->second->texture(textureCache_);
    if (!texture && diagnostic_.empty()) {
      diagnostic_ = "MacMetalRenderFrameExecutor warning: realtime video source has no decoded texture yet for clip " + clip.id + ".";
    }
    return texture;
  }

  std::array<MacPreviewVertex, 6> quadVertices(const NativeRenderGraphNode& node,
                                               const makelab::imgui::WorkspaceViewState& workspace) const {
    const float compWidth = static_cast<float>(std::max(1, workspace.width));
    const float compHeight = static_cast<float>(std::max(1, workspace.height));
    const float w = static_cast<float>(node.width);
    const float h = static_cast<float>(node.height);
    const float anchorX = static_cast<float>(node.anchorX);
    const float anchorY = static_cast<float>(node.anchorY);
    const float centerX = static_cast<float>(node.x + node.width * node.anchorX);
    const float centerY = static_cast<float>(node.y + node.height * node.anchorY);
    const float radians = static_cast<float>(node.rotationDegrees * M_PI / 180.0);
    const float skewXRadians = static_cast<float>(node.skewXDegrees * M_PI / 180.0);
    const float skewYRadians = static_cast<float>(node.skewYDegrees * M_PI / 180.0);
    const float c = std::cos(radians);
    const float s = std::sin(radians);
    const float skewX = std::tan(skewXRadians);
    const float skewY = std::tan(skewYRadians);
    auto ndc = [&](float px, float py) -> vector_float2 {
      return vector_float2{px / compWidth * 2.0f - 1.0f, 1.0f - py / compHeight * 2.0f};
    };
    auto transform = [&](float localX, float localY) -> vector_float2 {
      localX *= static_cast<float>(node.scaleX);
      localY *= static_cast<float>(node.scaleY);
      const float skewedX = localX + localY * skewX;
      const float skewedY = localY + localX * skewY;
      const float px = centerX + skewedX * c - skewedY * s;
      const float py = centerY + skewedX * s + skewedY * c;
      return ndc(px, py);
    };
    const float left = -w * anchorX;
    const float right = w * (1.0f - anchorX);
    const float top = -h * anchorY;
    const float bottom = h * (1.0f - anchorY);
    return {{
        {transform(left, bottom), vector_float2{0.0f, 1.0f}},
        {transform(right, bottom), vector_float2{1.0f, 1.0f}},
        {transform(left, top), vector_float2{0.0f, 0.0f}},
        {transform(right, bottom), vector_float2{1.0f, 1.0f}},
        {transform(right, top), vector_float2{1.0f, 0.0f}},
        {transform(left, top), vector_float2{0.0f, 0.0f}},
    }};
  }

  vector_float4 cornerRadii(const NativeRenderGraphNode& node) const {
    return vector_float4{
        static_cast<float>(std::max(0.0, node.cornerRadiusTopLeft)),
        static_cast<float>(std::max(0.0, node.cornerRadiusTopRight)),
        static_cast<float>(std::max(0.0, node.cornerRadiusBottomRight)),
        static_cast<float>(std::max(0.0, node.cornerRadiusBottomLeft)),
    };
  }

  id<MTLTexture> shadowTexture(const NativeRenderGraphNode& node) {
    if (!node.shadowEnabled || node.shadowOpacity <= 0.0) {
      return nil;
    }
    const double spread = std::max(0.0, node.shadowSpread);
    const double pad = std::max(1.0, std::ceil(node.shadowBlur * 2.0));
    const int width = std::max(1, static_cast<int>(std::ceil(node.width + (pad + spread) * 2.0)));
    const int height = std::max(1, static_cast<int>(std::ceil(node.height + (pad + spread) * 2.0)));
    const auto* clip = node.frameNode.layer.clip;
    const std::string clipId = clip != nullptr ? clip->id : "background";
    const std::string key = "shadow|" + clipId + "|" + std::to_string(width) + "x" + std::to_string(height) + "|" +
                            std::to_string(node.cornerRadiusTopLeft) + "|" + std::to_string(node.cornerRadiusTopRight) + "|" +
                            std::to_string(node.cornerRadiusBottomRight) + "|" + std::to_string(node.cornerRadiusBottomLeft) + "|" +
                            std::to_string(node.shadowBlur) + "|" + std::to_string(spread) + "|" + node.shadowColor;
    auto cached = generatedTextures_.find(key);
    if (cached != generatedTextures_.end()) {
      return cached->second;
    }

    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    CGContextRef context = CGBitmapContextCreate(nullptr, width, height, 8, 0, colorSpace, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(colorSpace);
    if (context == nullptr) {
      return nil;
    }
    CGContextClearRect(context, CGRectMake(0, 0, width, height));
    const CGFloat casterOffset = static_cast<CGFloat>(width * 2);
    const CGRect rect = CGRectMake(pad - casterOffset,
                                   pad,
                                   std::max(1.0, node.width + spread * 2.0),
                                   std::max(1.0, node.height + spread * 2.0));
    CGContextSetShadowWithColor(context,
                                CGSizeMake(casterOffset, 0.0),
                                static_cast<CGFloat>(node.shadowBlur),
                                NSColorFromHex(node.shadowColor, 1.0).CGColor);
    CGContextSetFillColorWithColor(context, NSColor.blackColor.CGColor);
    const uint32_t shapeKind = shapeKindValue(node);
    if (shapeKind == 1) {
      CGContextFillEllipseInRect(context, rect);
    } else if (shapeKind == 2) {
      CGContextSetLineWidth(context, std::max(2.0, node.height + spread * 2.0));
      CGContextMoveToPoint(context, CGRectGetMinX(rect), CGRectGetMidY(rect));
      CGContextAddLineToPoint(context, CGRectGetMaxX(rect), CGRectGetMidY(rect));
      CGContextStrokePath(context);
    } else if (shapeKind == 3) {
      CGContextBeginPath(context);
      CGContextMoveToPoint(context, CGRectGetMinX(rect), CGRectGetMidY(rect));
      CGContextAddLineToPoint(context, CGRectGetMaxX(rect), CGRectGetMidY(rect));
      CGContextAddLineToPoint(context, CGRectGetMaxX(rect) - std::min<CGFloat>(rect.size.width * 0.22, 42.0),
                              CGRectGetMidY(rect) + std::min<CGFloat>(rect.size.height * 0.42, 32.0));
      CGContextMoveToPoint(context, CGRectGetMaxX(rect), CGRectGetMidY(rect));
      CGContextAddLineToPoint(context, CGRectGetMaxX(rect) - std::min<CGFloat>(rect.size.width * 0.22, 42.0),
                              CGRectGetMidY(rect) - std::min<CGFloat>(rect.size.height * 0.42, 32.0));
      CGContextSetLineWidth(context, std::max(2.0, node.height * 0.25 + spread));
      CGContextStrokePath(context);
    } else {
      CGPathRef path = CreateRoundedRectPath(rect,
                                            node.cornerRadiusTopLeft + spread,
                                            node.cornerRadiusTopRight + spread,
                                            node.cornerRadiusBottomRight + spread,
                                            node.cornerRadiusBottomLeft + spread);
      CGContextAddPath(context, path);
      CGContextFillPath(context);
      CGPathRelease(path);
    }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    id<MTLTexture> texture = textureFromCGImage(image, key);
    if (image != nullptr) {
      CGImageRelease(image);
    }
    return texture;
  }

  void drawDropShadow(const NativeRenderGraphNode& node,
                      const makelab::imgui::WorkspaceViewState& workspace,
                      id<MTLRenderCommandEncoder> encoder) {
    if (!node.shadowEnabled || node.shadowOpacity <= 0.0 || !premultipliedPipeline_) {
      return;
    }
    id<MTLTexture> texture = shadowTexture(node);
    if (!texture) {
      return;
    }
    const double spread = std::max(0.0, node.shadowSpread);
    const double pad = std::max(1.0, std::ceil(node.shadowBlur * 2.0));
    NativeRenderGraphNode shadowNode = expandedNode(node, pad + spread);
    shadowNode.x += node.shadowX;
    shadowNode.y += node.shadowY;
    shadowNode.opacity = std::clamp(node.opacity * node.shadowOpacity, 0.0, 1.0);
    shadowNode.cornerRadiusTopLeft = 0.0;
    shadowNode.cornerRadiusTopRight = 0.0;
    shadowNode.cornerRadiusBottomRight = 0.0;
    shadowNode.cornerRadiusBottomLeft = 0.0;
    shadowNode.borderEnabled = false;
    shadowNode.shadowEnabled = false;
    [encoder setRenderPipelineState:premultipliedPipeline_];
    drawTexture(texture, shadowNode, workspace, encoder);
  }

  void drawBorder(const NativeRenderGraphNode& node,
                  const makelab::imgui::WorkspaceViewState& workspace,
                  id<MTLRenderCommandEncoder> encoder) {
    if (!node.borderEnabled || node.borderWidth <= 0.0 || node.borderOpacity <= 0.0 || !shapePipeline_) {
      return;
    }
    const double expansion = node.borderPosition == "outside"
                                 ? node.borderWidth
                                 : (node.borderPosition == "center" ? node.borderWidth * 0.5 : 0.0);
    NativeRenderGraphNode borderNode = expandedNode(node, expansion);
    const auto vertices = quadVertices(borderNode, workspace);
    MacPreviewUniforms uniforms{
        HexColor(node.borderColor, static_cast<float>(node.borderOpacity)),
        cornerRadii(borderNode),
        vector_float2{static_cast<float>(borderNode.width), static_cast<float>(borderNode.height)},
        vector_float2{1.0f, 1.0f},
        static_cast<float>(std::clamp(node.opacity, 0.0, 1.0)),
        static_cast<float>(node.borderWidth),
        1,
        shapeKindValue(node),
        2,
        0,
    };
    [encoder setRenderPipelineState:shapePipeline_];
    [encoder setVertexBytes:vertices.data() length:sizeof(MacPreviewVertex) * vertices.size() atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
  }

  void drawTexture(id<MTLTexture> texture,
                   const NativeRenderGraphNode& node,
                   const makelab::imgui::WorkspaceViewState& workspace,
                   id<MTLRenderCommandEncoder> encoder,
                   double uvExpansionX = 1.0,
                   double uvExpansionY = 1.0,
                   uint32_t tileMode = 2) {
    const auto vertices = quadVertices(node, workspace);
    MacPreviewUniforms uniforms{
        vector_float4{1.0f, 1.0f, 1.0f, 1.0f},
        cornerRadii(node),
        vector_float2{static_cast<float>(node.width), static_cast<float>(node.height)},
        vector_float2{static_cast<float>(std::max(1.0, uvExpansionX)),
                       static_cast<float>(std::max(1.0, uvExpansionY))},
        static_cast<float>(std::clamp(node.opacity, 0.0, 1.0)),
        0.0f,
        0,
        0,
        tileMode,
        0,
    };
    [encoder setVertexBytes:vertices.data() length:sizeof(MacPreviewVertex) * vertices.size() atIndex:0];
    [encoder setFragmentTexture:texture atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
  }

};

class MacNativePlaybackScheduler {
 public:
  void bindTimeline(double durationSeconds, double fps) {
    coordinator_.bind(durationSeconds, fps);
  }

  void reset() {
    coordinator_.reset();
  }

  void togglePlayback() {
    coordinator_.togglePlayback(CACurrentMediaTime());
  }

  void scrubTo(double timeSeconds) {
    coordinator_.requestScrubFrame(makelab::timeline::SecondsToFrameRound(timeSeconds, coordinator_.rate()));
  }

  void scrubToFrame(int64_t frameIndex) {
    coordinator_.requestScrubFrame(frameIndex);
  }

  int64_t requestFrameForNow() {
    return coordinator_.requestFrameForHostTime(CACurrentMediaTime());
  }

  bool acceptRequestedFrame(uint64_t requestGeneration) {
    return coordinator_.acceptRequestedFrame(requestGeneration);
  }

  bool isPlaying() const { return coordinator_.isPlaying(); }
  double fps() const { return makelab::timeline::Fps(coordinator_.rate()); }
  makelab::timeline::FrameRate frameRate() const { return coordinator_.rate(); }
  int64_t durationFrames() const { return coordinator_.durationFrames(); }
  int64_t requestedFrame() const { return coordinator_.requestedFrame(); }
  int64_t acceptedFrame() const { return coordinator_.acceptedFrame(); }
  uint64_t requestGeneration() const { return coordinator_.requestGeneration(); }
  uint64_t acceptedGeneration() const { return coordinator_.acceptedGeneration(); }

  double timeSeconds() const {
    return coordinator_.acceptedSeconds();
  }

  double requestedTimeSeconds() const {
    return coordinator_.requestedSeconds();
  }

 private:
  makelab::timeline::TimelineCoordinator coordinator_;
};

struct NativeExportResult {
  bool ok = false;
  std::string path;
  std::string message;
  std::string report;
};

struct NativeExportEncoderProof {
  bool ok = false;
  std::string backend;
  std::string codec;
  std::string pixelFormat;
  std::string diagnostic;
};

struct NativeExportOptions {
  std::string qualityLabel = "Master";
  int averageBitRate = 0;
};

using NativeExportProgressCallback = std::function<void(double progress, const std::string& phase)>;

struct NativeAudioGraphBuild {
  AVMutableComposition* composition = nil;
  int clipCount = 0;
  std::string diagnostic;
};

struct NativeAudioSourceClip {
  std::string path;
  std::string clipId;
  int64_t startFrame = 0;
  int64_t durationFrames = 0;
  double trimInSeconds = 0.0;
};

NSURL* WorkspaceAssetURL(const makelab::imgui::WorkspaceViewState& workspace,
                         const makelab::imgui::AssetItem& asset) {
  if (workspace.folderPath.empty() || asset.path.empty()) {
    return nil;
  }
  NSString* root = [NSString stringWithUTF8String:workspace.folderPath.c_str()];
  NSString* relative = [NSString stringWithUTF8String:asset.path.c_str()];
  return [[NSURL fileURLWithPath:root isDirectory:YES] URLByAppendingPathComponent:relative];
}

CMTime WorkspaceFrameTime(const makelab::imgui::WorkspaceViewState& workspace, int64_t frame) {
  return CMTimeMake(frame * workspace.frameRate.denominator,
                    static_cast<int32_t>(workspace.frameRate.numerator));
}

CMTime WorkspaceSecondsTime(double seconds) {
  return CMTimeMakeWithSeconds(std::max(0.0, seconds), 60000);
}

bool PositiveCMTime(CMTime time) {
  return CMTIME_IS_NUMERIC(time) && CMTimeCompare(time, kCMTimeZero) > 0;
}

CMTime MinCMTime(CMTime left, CMTime right) {
  if (!PositiveCMTime(left)) return right;
  if (!PositiveCMTime(right)) return left;
  return CMTimeCompare(left, right) <= 0 ? left : right;
}

NativeExportEncoderProof ProveMacHardwareEncoder(int width, int height) {
  NativeExportEncoderProof proof;
  proof.backend = "macOS VideoToolbox hardware encoder";
  proof.codec = "H.264";
  proof.pixelFormat = "BGRA8 FinalFrameSurface -> CVPixelBufferPool";
  if (width <= 0 || height <= 0) {
    proof.diagnostic = "VideoToolbox proof rejected: export dimensions must be positive.";
    return proof;
  }
  NSDictionary* encoderSpecification = @{
    (__bridge NSString*)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES
  };
  VTCompressionSessionRef session = nullptr;
  OSStatus status = VTCompressionSessionCreate(nullptr,
                                               static_cast<int32_t>(width),
                                               static_cast<int32_t>(height),
                                               kCMVideoCodecType_H264,
                                               (__bridge CFDictionaryRef)encoderSpecification,
                                               nullptr,
                                               nullptr,
                                               nullptr,
                                               nullptr,
                                               &session);
  if (status != noErr || session == nullptr) {
    proof.diagnostic = "VideoToolbox proof rejected: required hardware H.264 encoder is unavailable. status=" +
                       std::to_string(static_cast<int>(status));
    if (session != nullptr) {
      CFRelease(session);
    }
    return proof;
  }
  VTSessionSetProperty(session, kVTCompressionPropertyKey_ProfileLevel, kVTProfileLevel_H264_High_AutoLevel);
  status = VTCompressionSessionPrepareToEncodeFrames(session);
  if (status != noErr) {
    proof.diagnostic = "VideoToolbox proof rejected: hardware encoder session could not prepare. status=" +
                       std::to_string(static_cast<int>(status));
    VTCompressionSessionInvalidate(session);
    CFRelease(session);
    return proof;
  }
  CFTypeRef hardwareValue = nullptr;
  status = VTSessionCopyProperty(session,
                                 kVTCompressionPropertyKey_UsingHardwareAcceleratedVideoEncoder,
                                 nullptr,
                                 &hardwareValue);
  bool usingHardware = false;
  if (status == noErr && hardwareValue != nullptr) {
    usingHardware = CFBooleanGetValue(static_cast<CFBooleanRef>(hardwareValue));
    CFRelease(hardwareValue);
  }
  VTCompressionSessionInvalidate(session);
  CFRelease(session);
  if (!usingHardware) {
    proof.diagnostic = "VideoToolbox proof rejected: encoder did not confirm hardware acceleration.";
    return proof;
  }
  proof.ok = true;
  proof.diagnostic = "VideoToolbox proof accepted: hardware H.264 encoder confirmed.";
  return proof;
}

std::vector<NativeAudioSourceClip> DiscoverNativeAudioSources(const makelab::imgui::WorkspaceViewState& workspace,
                                                              int* skippedCount) {
  std::vector<NativeAudioSourceClip> sources;
  if (skippedCount != nullptr) {
    *skippedCount = 0;
  }
  if (!workspace.opened) {
    return sources;
  }
  std::unordered_map<std::string, const makelab::imgui::AssetItem*> assetsById;
  for (const auto& asset : workspace.assets) {
    assetsById[asset.id] = &asset;
  }
  for (const auto& track : workspace.tracks) {
    if (track.hidden || track.muted) {
      continue;
    }
    for (const auto& clip : track.clips) {
      const auto assetIt = assetsById.find(clip.assetId);
      if (assetIt == assetsById.end()) {
        continue;
      }
      const auto& asset = *assetIt->second;
      const std::string clipType = !clip.type.empty() ? clip.type : track.kind;
      const bool canCarryAudio = clipType == "audio" || clipType == "video" ||
                                 asset.type == "audio" || asset.type == "video";
      if (!canCarryAudio) {
        continue;
      }
      NSURL* sourceURL = WorkspaceAssetURL(workspace, asset);
      if (sourceURL == nil) {
        if (skippedCount != nullptr) *skippedCount += 1;
        continue;
      }
      AVURLAsset* sourceAsset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
      AVAssetTrack* sourceAudio = [[sourceAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
      if (sourceAudio == nil) {
        if (skippedCount != nullptr) *skippedCount += 1;
        continue;
      }
      NativeAudioSourceClip source;
      source.path = ToStdString(sourceURL.path);
      source.clipId = clip.id;
      source.startFrame = std::max<int64_t>(0, clip.startFrame);
      source.durationFrames = std::max<int64_t>(1, clip.durationFrames);
      source.trimInSeconds = std::max(0.0, clip.trimInSeconds);
      sources.push_back(source);
    }
  }
  return sources;
}

NativeAudioGraphBuild BuildNativeAudioGraph(const makelab::imgui::WorkspaceViewState& workspace) {
  NativeAudioGraphBuild build;
  if (!workspace.opened) {
    build.diagnostic = "AudioGraph blocked: workspace is not accepted.";
    return build;
  }
  build.composition = [AVMutableComposition composition];
  int skipped = 0;
  std::vector<NativeAudioSourceClip> sources = DiscoverNativeAudioSources(workspace, &skipped);
  for (const auto& source : sources) {
      NSURL* sourceURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:source.path.c_str()]];
      AVURLAsset* sourceAsset = [AVURLAsset URLAssetWithURL:sourceURL options:nil];
      AVAssetTrack* sourceAudio = [[sourceAsset tracksWithMediaType:AVMediaTypeAudio] firstObject];
      if (sourceAudio == nil) {
        skipped += 1;
        continue;
      }
      AVMutableCompositionTrack* destination =
          [build.composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                         preferredTrackID:kCMPersistentTrackID_Invalid];
      if (destination == nil) {
        skipped += 1;
        continue;
      }
      const CMTime timelineStart = WorkspaceFrameTime(workspace, source.startFrame);
      const CMTime timelineDuration = WorkspaceFrameTime(workspace, source.durationFrames);
      const CMTime sourceStart = WorkspaceSecondsTime(source.trimInSeconds);
      CMTime sourceAvailable = CMTimeSubtract(sourceAsset.duration, sourceStart);
      if (!PositiveCMTime(sourceAvailable)) {
        sourceAvailable = timelineDuration;
      }
      const CMTime sourceDuration = MinCMTime(timelineDuration, sourceAvailable);
      if (!PositiveCMTime(sourceDuration)) {
        skipped += 1;
        continue;
      }
      NSError* insertError = nil;
      const BOOL inserted = [destination insertTimeRange:CMTimeRangeMake(sourceStart, sourceDuration)
                                                 ofTrack:sourceAudio
                                                  atTime:timelineStart
                                                   error:&insertError];
      if (!inserted) {
        skipped += 1;
        continue;
      }
      build.clipCount += 1;
  }
  build.diagnostic = "AudioGraph accepted " + std::to_string(build.clipCount) + " source clip(s)";
  if (skipped > 0) {
    build.diagnostic += "; skipped " + std::to_string(skipped) + " clip(s) without readable audio.";
  }
  return build;
}

NativeExportResult MuxFinalFrameVideoWithAudio(const makelab::imgui::WorkspaceViewState& workspace,
                                               NSURL* videoOnlyURL,
                                               NSURL* outputURL,
                                               const NativeAudioGraphBuild& audioGraph) {
  NativeExportResult result;
  AVURLAsset* videoAsset = [AVURLAsset URLAssetWithURL:videoOnlyURL options:nil];
  AVAssetTrack* videoTrack = [[videoAsset tracksWithMediaType:AVMediaTypeVideo] firstObject];
  if (videoTrack == nil) {
    result.message = "Export rejected: FinalFrameSurface video stream is not readable for audio mux.";
    return result;
  }
  AVMutableComposition* composition = [AVMutableComposition composition];
  AVMutableCompositionTrack* destinationVideo =
      [composition addMutableTrackWithMediaType:AVMediaTypeVideo
                               preferredTrackID:kCMPersistentTrackID_Invalid];
  NSError* videoInsertError = nil;
  if (![destinationVideo insertTimeRange:CMTimeRangeMake(kCMTimeZero, videoAsset.duration)
                                 ofTrack:videoTrack
                                  atTime:kCMTimeZero
                                   error:&videoInsertError]) {
    result.message = "Export rejected: FinalFrameSurface video stream could not be muxed.";
    return result;
  }

  for (AVAssetTrack* audioTrack in [audioGraph.composition tracksWithMediaType:AVMediaTypeAudio]) {
    AVMutableCompositionTrack* destinationAudio =
        [composition addMutableTrackWithMediaType:AVMediaTypeAudio
                                 preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError* audioInsertError = nil;
    const CMTimeRange audioRange = CMTimeRangeMake(kCMTimeZero, WorkspaceFrameTime(workspace, workspace.durationFrames));
    if (![destinationAudio insertTimeRange:audioRange
                                   ofTrack:audioTrack
                                    atTime:kCMTimeZero
                                     error:&audioInsertError]) {
      result.message = "Export rejected: AudioGraph source could not be muxed into the FinalFrameSurface export.";
      return result;
    }
  }

  [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
  AVAssetExportSession* exportSession =
      [[AVAssetExportSession alloc] initWithAsset:composition presetName:AVAssetExportPresetPassthrough];
  if (exportSession == nil) {
    result.message = "Export rejected: AVAssetExportSession passthrough mux could not be created.";
    return result;
  }
  exportSession.outputURL = outputURL;
  exportSession.outputFileType = AVFileTypeMPEG4;
  dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
  [exportSession exportAsynchronouslyWithCompletionHandler:^{
    dispatch_semaphore_signal(semaphore);
  }];
  dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
  if (exportSession.status != AVAssetExportSessionStatusCompleted) {
    result.message = "Export rejected: audio mux did not complete.";
    if (exportSession.error != nil && exportSession.error.localizedDescription != nil) {
      result.message += " ";
      result.message += ToStdString(exportSession.error.localizedDescription);
    }
    return result;
  }
  result.ok = true;
  result.path = ToStdString(outputURL.path);
  result.message = "Export completed from FinalFrameSurface + AudioPCM mux: " + result.path +
                   " (" + audioGraph.diagnostic + ").";
  return result;
}

class NativeAudioPreviewEngine {
 public:
  ~NativeAudioPreviewEngine() {
    stop();
  }

  void stop() {
    if (engine_ != nil) {
      for (AVAudioPlayerNode* node in nodes_) {
        [node stop];
      }
      [engine_ stop];
    }
    engine_ = nil;
    nodes_ = nil;
    files_ = nil;
    diagnostic_.clear();
  }

  bool play(const makelab::imgui::WorkspaceViewState& workspace, int64_t startFrame) {
    stop();
    int skipped = 0;
    std::vector<NativeAudioSourceClip> sources = DiscoverNativeAudioSources(workspace, &skipped);
    if (sources.empty()) {
      diagnostic_ = "Audio preview has no accepted audio sources.";
      return false;
    }

    engine_ = [[AVAudioEngine alloc] init];
    nodes_ = [NSMutableArray array];
    files_ = [NSMutableArray array];
    const double timelineStartSeconds =
        makelab::timeline::FrameToSeconds({std::clamp<int64_t>(startFrame, 0, workspace.durationFrames)}, workspace.frameRate);
    int scheduled = 0;
    for (const auto& source : sources) {
      const double clipStartSeconds = makelab::timeline::FrameToSeconds({source.startFrame}, workspace.frameRate);
      const double clipDurationSeconds = makelab::timeline::FrameToSeconds({source.durationFrames}, workspace.frameRate);
      const double clipEndSeconds = clipStartSeconds + clipDurationSeconds;
      if (clipEndSeconds <= timelineStartSeconds + 0.0001) {
        continue;
      }

      NSURL* sourceURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:source.path.c_str()]];
      NSError* fileError = nil;
      AVAudioFile* file = [[AVAudioFile alloc] initForReading:sourceURL error:&fileError];
      if (file == nil) {
        skipped += 1;
        continue;
      }
      AVAudioFormat* format = file.processingFormat;
      const double sampleRate = std::max(1.0, format.sampleRate);
      const double audibleStartSeconds = std::max(timelineStartSeconds, clipStartSeconds);
      const double sourceOffsetSeconds = source.trimInSeconds + std::max(0.0, audibleStartSeconds - clipStartSeconds);
      const double audibleDurationSeconds = std::max(0.0, clipEndSeconds - audibleStartSeconds);
      const AVAudioFramePosition fileStart = std::max<AVAudioFramePosition>(0, static_cast<AVAudioFramePosition>(std::llround(sourceOffsetSeconds * sampleRate)));
      AVAudioFrameCount frameCount = static_cast<AVAudioFrameCount>(std::max<int64_t>(0, static_cast<int64_t>(std::llround(audibleDurationSeconds * sampleRate))));
      if (file.length > 0 && fileStart < file.length) {
        frameCount = static_cast<AVAudioFrameCount>(std::min<int64_t>(frameCount, file.length - fileStart));
      }
      if (frameCount == 0) {
        continue;
      }

      AVAudioPlayerNode* node = [[AVAudioPlayerNode alloc] init];
      [engine_ attachNode:node];
      [engine_ connect:node to:engine_.mainMixerNode format:format];
      const double delaySeconds = std::max(0.0, clipStartSeconds - timelineStartSeconds);
      AVAudioTime* when = delaySeconds > 0.0001
                              ? [[AVAudioTime alloc] initWithSampleTime:static_cast<AVAudioFramePosition>(std::llround(delaySeconds * sampleRate))
                                                                  atRate:sampleRate]
                              : nil;
      [files_ addObject:file];
      [nodes_ addObject:node];
      [node scheduleSegment:file
              startingFrame:fileStart
                 frameCount:frameCount
                     atTime:when
          completionHandler:nil];
      scheduled += 1;
    }

    if (scheduled <= 0) {
      stop();
      diagnostic_ = "Audio preview blocked: no readable PCM segments at the requested frame.";
      return false;
    }

    NSError* startError = nil;
    [engine_ prepare];
    if (![engine_ startAndReturnError:&startError]) {
      stop();
      diagnostic_ = "Audio preview blocked: AVAudioEngine could not start.";
      if (startError != nil && startError.localizedDescription != nil) {
        diagnostic_ += " ";
        diagnostic_ += ToStdString(startError.localizedDescription);
      }
      return false;
    }
    for (AVAudioPlayerNode* node in nodes_) {
      [node play];
    }
    diagnostic_ = "Audio preview started from accepted AudioGraph PCM segments: " + std::to_string(scheduled) + " source(s).";
    if (skipped > 0) {
      diagnostic_ += " skipped=" + std::to_string(skipped) + ".";
    }
    return true;
  }

  const std::string& diagnostic() const {
    return diagnostic_;
  }

 private:
  AVAudioEngine* engine_ = nil;
  NSMutableArray<AVAudioPlayerNode*>* nodes_ = nil;
  NSMutableArray<AVAudioFile*>* files_ = nil;
  std::string diagnostic_;
};

class NativeFinalFrameSurfaceExporter {
 public:
  static NativeExportResult ExportMp4(const makelab::imgui::WorkspaceViewState& workspace,
                                      MacMetalRenderFrameExecutor& executor,
                                      NSURL* outputURL,
                                      const NativeExportOptions& options = {},
                                      NativeExportProgressCallback progress = {}) {
    NativeExportResult exportResult;
    if (progress) {
      progress(0.0, "Export gate: validating accepted workspace.");
    }
    if (!workspace.opened) {
      exportResult.message = "Export rejected: workspace is not accepted by UnitedGate.";
      return exportResult;
    }
    if (workspace.durationFrames <= 0 || workspace.width <= 0 || workspace.height <= 0) {
      exportResult.message = "Export rejected: composition durationFrames, width, and height must be positive.";
      return exportResult;
    }

    if (progress) {
      progress(0.02, "Export gate: proving native hardware encoder.");
    }
    NativeExportEncoderProof encoderProof = ProveMacHardwareEncoder(workspace.width, workspace.height);
    if (!encoderProof.ok) {
      exportResult.message = "Export rejected: " + encoderProof.diagnostic;
      exportResult.report = encoderProof.backend + " | codec=" + encoderProof.codec +
                            " | pixelFormat=" + encoderProof.pixelFormat +
                            " | hardwareRequired=true";
      return exportResult;
    }

    if (progress) {
      progress(0.05, "AudioGraph: collecting accepted audio sources.");
    }
    NativeAudioGraphBuild audioGraph = BuildNativeAudioGraph(workspace);
    NSString* tempVideoPath = [outputURL.path stringByAppendingString:@".video-only.tmp.mp4"];
    NSURL* tempVideoURL = [NSURL fileURLWithPath:tempVideoPath];
    NSError* removeError = nil;
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:&removeError];
    [[NSFileManager defaultManager] removeItemAtURL:tempVideoURL error:nil];
    NSError* writerError = nil;
    AVAssetWriter* writer = [[AVAssetWriter alloc] initWithURL:tempVideoURL fileType:AVFileTypeMPEG4 error:&writerError];
    if (!writer) {
      exportResult.message = "Export rejected: AVAssetWriter could not be created.";
      if (writerError != nil && writerError.localizedDescription != nil) {
        exportResult.message += " ";
        exportResult.message += ToStdString(writerError.localizedDescription);
      }
      return exportResult;
    }

    NSDictionary* outputSettings = @{
      AVVideoCodecKey: AVVideoCodecTypeH264,
      AVVideoWidthKey: @(workspace.width),
      AVVideoHeightKey: @(workspace.height),
      AVVideoEncoderSpecificationKey: @{
        (__bridge NSString*)kVTVideoEncoderSpecification_RequireHardwareAcceleratedVideoEncoder: @YES
      },
      AVVideoCompressionPropertiesKey: @{
        AVVideoAverageBitRateKey: @(options.averageBitRate > 0
                                      ? options.averageBitRate
                                      : std::max(4000000, workspace.width * workspace.height * 3)),
        AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel
      }
    };
    AVAssetWriterInput* input = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo
                                                                    outputSettings:outputSettings];
    input.expectsMediaDataInRealTime = NO;
    NSDictionary* pixelBufferAttributes = @{
      (NSString*)kCVPixelBufferPixelFormatTypeKey: @(kCVPixelFormatType_32BGRA),
      (NSString*)kCVPixelBufferWidthKey: @(workspace.width),
      (NSString*)kCVPixelBufferHeightKey: @(workspace.height),
      (NSString*)kCVPixelBufferMetalCompatibilityKey: @YES,
      (NSString*)kCVPixelBufferCGImageCompatibilityKey: @YES,
      (NSString*)kCVPixelBufferCGBitmapContextCompatibilityKey: @YES
    };
    AVAssetWriterInputPixelBufferAdaptor* adaptor =
        [AVAssetWriterInputPixelBufferAdaptor assetWriterInputPixelBufferAdaptorWithAssetWriterInput:input
                                                                         sourcePixelBufferAttributes:pixelBufferAttributes];
    if (![writer canAddInput:input]) {
      exportResult.message = "Export rejected: AVAssetWriter cannot accept the native FinalFrameSurface video input.";
      return exportResult;
    }
    [writer addInput:input];
    if (![writer startWriting]) {
      exportResult.message = "Export rejected: AVAssetWriter failed to start.";
      if (writer.error != nil && writer.error.localizedDescription != nil) {
        exportResult.message += " ";
        exportResult.message += ToStdString(writer.error.localizedDescription);
      }
      return exportResult;
    }
    [writer startSessionAtSourceTime:kCMTimeZero];

    const uint64_t exportGeneration = 0xE000000000000000ULL;
    for (int64_t frameIndex = 0; frameIndex < workspace.durationFrames; ++frameIndex) {
      @autoreleasepool {
        if (progress && (frameIndex == 0 || frameIndex % 6 == 0 || frameIndex + 1 == workspace.durationFrames)) {
          const double frameProgress = static_cast<double>(frameIndex) / static_cast<double>(std::max<int64_t>(1, workspace.durationFrames));
          progress(0.08 + frameProgress * 0.84,
                   "FinalFrameSurface: rendering frame " + std::to_string(frameIndex + 1) +
                       " / " + std::to_string(workspace.durationFrames) + ".");
        }
        FinalFrameSurfaceResult frame = executor.render(workspace, frameIndex, exportGeneration + static_cast<uint64_t>(frameIndex), false, true);
        if (!frame.accepted()) {
          [input markAsFinished];
          [writer cancelWriting];
          exportResult.message = "Export rejected: FinalFrameSurface frame " + std::to_string(frameIndex) + " was not accepted.";
          if (!frame.diagnostic.empty()) {
            exportResult.message += " " + frame.diagnostic;
          }
          return exportResult;
        }
        size_t bytesPerRow = 0;
        std::vector<uint8_t> bgra;
        if (!executor.copyTextureBGRA8(frame.texture, bgra, bytesPerRow)) {
          [input markAsFinished];
          [writer cancelWriting];
          exportResult.message = "Export rejected: FinalFrameSurface readback failed.";
          if (!executor.diagnostic().empty()) {
            exportResult.message += " " + executor.diagnostic();
          }
          return exportResult;
        }

        CVPixelBufferRef pixelBuffer = nullptr;
        CVReturn created = CVPixelBufferPoolCreatePixelBuffer(nullptr, adaptor.pixelBufferPool, &pixelBuffer);
        if (created != kCVReturnSuccess || pixelBuffer == nullptr) {
          [input markAsFinished];
          [writer cancelWriting];
          exportResult.message = "Export rejected: CVPixelBufferPool could not allocate an export frame.";
          return exportResult;
        }
        CVPixelBufferLockBaseAddress(pixelBuffer, 0);
        uint8_t* destination = static_cast<uint8_t*>(CVPixelBufferGetBaseAddress(pixelBuffer));
        const size_t destinationRowBytes = CVPixelBufferGetBytesPerRow(pixelBuffer);
        for (int y = 0; y < workspace.height; ++y) {
          std::memcpy(destination + static_cast<size_t>(y) * destinationRowBytes,
                      bgra.data() + static_cast<size_t>(y) * bytesPerRow,
                      bytesPerRow);
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, 0);

        while (!input.readyForMoreMediaData) {
          [NSThread sleepForTimeInterval:0.002];
        }
        const CMTime presentationTime = CMTimeMake(frameIndex * workspace.frameRate.denominator,
                                                  static_cast<int32_t>(workspace.frameRate.numerator));
        if (![adaptor appendPixelBuffer:pixelBuffer withPresentationTime:presentationTime]) {
          CFRelease(pixelBuffer);
          [input markAsFinished];
          [writer cancelWriting];
          exportResult.message = "Export rejected: AVAssetWriter refused FinalFrameSurface frame " + std::to_string(frameIndex) + ".";
          return exportResult;
        }
        CFRelease(pixelBuffer);
      }
    }

    if (progress) {
      progress(0.93, "VideoToolbox: finalizing hardware encoded video stream.");
    }
    [input markAsFinished];
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [writer finishWritingWithCompletionHandler:^{
      dispatch_semaphore_signal(semaphore);
    }];
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    if (writer.status != AVAssetWriterStatusCompleted) {
      exportResult.message = "Export rejected: AVAssetWriter did not complete.";
      if (writer.error != nil && writer.error.localizedDescription != nil) {
        exportResult.message += " ";
        exportResult.message += ToStdString(writer.error.localizedDescription);
      }
      return exportResult;
    }

    if (audioGraph.clipCount > 0) {
      if (progress) {
        progress(0.96, "AudioGraph: muxing accepted audio with FinalFrameSurface video.");
      }
      NativeExportResult muxResult = MuxFinalFrameVideoWithAudio(workspace, tempVideoURL, outputURL, audioGraph);
      [[NSFileManager defaultManager] removeItemAtURL:tempVideoURL error:nil];
      if (muxResult.ok) {
        muxResult.report = encoderProof.backend + " | codec=" + encoderProof.codec +
                           " | pixelFormat=" + encoderProof.pixelFormat +
                           " | hardwareRequired=true | quality=" + options.qualityLabel +
                           " | audioMux=AudioGraph passthrough";
        muxResult.message += " | " + muxResult.report;
        if (progress) {
          progress(1.0, "Export complete: FinalFrameSurface MP4 with AudioGraph mux.");
        }
      }
      return muxResult;
    }

    NSError* moveError = nil;
    if (![[NSFileManager defaultManager] moveItemAtURL:tempVideoURL toURL:outputURL error:&moveError]) {
      exportResult.message = "Export rejected: video-only FinalFrameSurface output could not be moved into place.";
      if (moveError != nil && moveError.localizedDescription != nil) {
        exportResult.message += " ";
        exportResult.message += ToStdString(moveError.localizedDescription);
      }
      return exportResult;
    }
    exportResult.ok = true;
    exportResult.path = ToStdString(outputURL.path);
    exportResult.report = encoderProof.backend + " | codec=" + encoderProof.codec +
                          " | pixelFormat=" + encoderProof.pixelFormat +
                          " | hardwareRequired=true | quality=" + options.qualityLabel +
                          " | audioMux=none";
    exportResult.message = "Export completed from FinalFrameSurface: " + exportResult.path +
                           " (" + audioGraph.diagnostic + "). | " + exportResult.report;
    if (progress) {
      progress(1.0, "Export complete: FinalFrameSurface MP4.");
    }
    return exportResult;
  }
};

void EnsureMinimumWorkspace(NSURL* folder) {
  EnsureDirectory([folder URLByAppendingPathComponent:@"assets/originals" isDirectory:YES]);
  EnsureDirectory([folder URLByAppendingPathComponent:@"native-scenes/main" isDirectory:YES]);
  EnsureDirectory([folder URLByAppendingPathComponent:@"renders" isDirectory:YES]);

  EnsureFile([folder URLByAppendingPathComponent:@"project.json"], [NSString stringWithFormat:
      @"{\n  \"id\": \"%@\",\n  \"name\": \"%@\",\n  \"createdAt\": \"%@\"\n}\n",
      MakeId(@"project"), folder.lastPathComponent ?: @"Makelab Project", NowIsoString()]);

  EnsureFile([folder URLByAppendingPathComponent:@"composition.json"],
      @"{\n  \"width\": 1080,\n  \"height\": 1920,\n  \"fps\": 30,\n  \"durationSeconds\": 13.26\n}\n");

  EnsureFile([folder URLByAppendingPathComponent:@"assets/assets.json"], [NSString stringWithFormat:
      @"{\n  \"version\": 1,\n  \"updatedAt\": \"%@\",\n  \"assets\": []\n}\n", NowIsoString()]);

  EnsureFile([folder URLByAppendingPathComponent:@"timeline.json"], [NSString stringWithFormat:
      @"{\n"
       "  \"version\": 1,\n"
       "  \"fps\": 30,\n"
       "  \"durationSeconds\": 13.26,\n"
       "  \"timebase\": {\n"
       "    \"fps\": 30,\n"
       "    \"timelineTimeUnit\": \"seconds\",\n"
       "    \"clipStartTimeMode\": \"absolute-timeline-seconds\",\n"
       "    \"clipDurationMode\": \"seconds\",\n"
       "    \"keyframeTimeMode\": \"clip-local-seconds\",\n"
       "    \"animationTimeOrigin\": \"clip-start\"\n"
       "  },\n"
       "  \"agentContract\": {\n"
       "    \"version\": 1,\n"
       "    \"summary\": \"All visible, renderable, selectable, and exportable changes must be represented in timeline.json/assets/assets.json/composition.json and ingested by UnitedGate.\",\n"
       "    \"effectPath\": \"clip.style.effects.<effectName>\",\n"
       "    \"sourceOfTruth\": [\"composition.json\", \"timeline.json\", \"assets/assets.json\"]\n"
       "  },\n"
       "  \"updatedAt\": \"%@\",\n"
       "  \"tracks\": []\n"
       "}\n", NowIsoString()]);

  EnsureFile([folder URLByAppendingPathComponent:@"native-scenes/main/index.html"],
      @"<main class=\"scene\" data-scene=\"main\">\n"
       "  <canvas class=\"scene-canvas\" data-remake-export width=\"1080\" height=\"1920\"></canvas>\n"
       "</main>\n");
  EnsureFile([folder URLByAppendingPathComponent:@"native-scenes/main/scene.css"],
      @"html, body { margin: 0; width: 100%; height: 100%; overflow: hidden; background: transparent; }\n"
       ".scene { width: 1080px; height: 1920px; overflow: hidden; }\n"
       ".scene-canvas { display: block; width: 100%; height: 100%; }\n");
  EnsureFile([folder URLByAppendingPathComponent:@"native-scenes/main/scene.js"],
      @"(() => {\n"
       "  const canvas = document.querySelector('[data-remake-export]');\n"
       "  const ctx = canvas.getContext('2d');\n"
       "  const duration = 13.26;\n"
       "  function seek(time) { ctx.clearRect(0, 0, canvas.width, canvas.height); }\n"
       "  window.__remake = { duration, seek, playFrom: seek, pause() {}, getExportCanvas: () => canvas };\n"
       "  seek(0);\n"
       "})();\n");
}

makelab::imgui::WorkspaceViewState LoadWorkspaceState(NSURL* folder) {
  EnsureMinimumWorkspace(folder);

  makelab::imgui::WorkspaceViewState state;
  state.opened = true;
  state.folderName = ToStdString(folder.lastPathComponent);
  state.folderPath = ToStdString(folder.path);

  NSDictionary* project = ReadDictionary([folder URLByAppendingPathComponent:@"project.json"]);
  NSDictionary* composition = ReadDictionary([folder URLByAppendingPathComponent:@"composition.json"]);
  NSDictionary* assetManifest = ReadDictionary([folder URLByAppendingPathComponent:@"assets/assets.json"]);
  NSDictionary* timeline = ReadDictionary([folder URLByAppendingPathComponent:@"timeline.json"]);

  if (project == nil || composition == nil || assetManifest == nil || timeline == nil) {
    state.opened = false;
    state.diagnostics.push_back(
        "UnitedGate blocked project reload: project.json, composition.json, timeline.json, and assets/assets.json must contain valid JSON objects.");
    return state;
  }

  state.projectName = project ? StringValue(project, @"name", state.folderName.c_str()) : state.folderName;
  state.width = composition ? IntValue(composition, @"width", 1080) : 1080;
  state.height = composition ? IntValue(composition, @"height", 1920) : 1920;
  state.fps = composition ? DoubleValue(composition, @"fps", 30.0) : 30.0;
  state.durationSeconds = composition ? DoubleValue(composition, @"durationSeconds", 13.26) : 13.26;
  state.frameRate = makelab::timeline::FrameRateFromFps(state.fps);
  NSDictionary* timebase = DictionaryValue(timeline, @"timebase");
  NSDictionary* rate = DictionaryValue(timebase, @"rate");
  const int64_t rateNumerator = static_cast<int64_t>(std::llround(DoubleValue(rate, @"numerator", 0.0)));
  const int64_t rateDenominator = static_cast<int64_t>(std::llround(DoubleValue(rate, @"denominator", 0.0)));
  if (rateNumerator > 0 && rateDenominator > 0) {
    state.frameRate = makelab::timeline::NormalizeRate({rateNumerator, rateDenominator});
  }
  state.fps = makelab::timeline::Fps(state.frameRate);
  const int64_t timelineDurationFrames = static_cast<int64_t>(std::llround(DoubleValue(timeline, @"durationFrames", 0.0)));
  state.durationFrames = timelineDurationFrames > 0
                             ? timelineDurationFrames
                             : std::max<int64_t>(1, makelab::timeline::SecondsToFrameRound(state.durationSeconds, state.frameRate));
  state.durationSeconds = makelab::timeline::FrameToSeconds({state.durationFrames}, state.frameRate);

  if (state.width <= 0 || state.height <= 0 || state.fps <= 0 || state.durationSeconds <= 0) {
    state.diagnostics.push_back("UnitedGate blocked: composition.json width, height, fps, and durationSeconds must be positive.");
    state.opened = false;
  }

  for (id item in ArrayValue(assetManifest ?: @{}, @"assets")) {
    if (![item isKindOfClass:NSDictionary.class]) {
      continue;
    }
    NSDictionary* asset = item;
    makelab::imgui::AssetItem next;
    next.id = StringValue(asset, @"id");
    next.name = StringValue(asset, @"name", next.id.c_str());
    next.type = StringValue(asset, @"type", "unknown");
    next.path = StringValue(asset, @"path");
    next.width = IntValue(asset, @"width", 0);
    next.height = IntValue(asset, @"height", 0);
    next.durationSeconds = DoubleValue(asset, @"duration", 0.0);
    state.assets.push_back(next);
  }

  for (id item in ArrayValue(timeline ?: @{}, @"tracks")) {
    if (![item isKindOfClass:NSDictionary.class]) {
      continue;
    }
    NSDictionary* track = item;
    makelab::imgui::TrackItem nextTrack;
    nextTrack.id = StringValue(track, @"id");
    nextTrack.name = StringValue(track, @"name", nextTrack.id.c_str());
    nextTrack.kind = StringValue(track, @"kind", "shape");
    nextTrack.hidden = BoolValue(track, @"isHidden", false);
    nextTrack.muted = BoolValue(track, @"isMuted", false);

    for (id clipItem in ArrayValue(track, @"clips")) {
      if (![clipItem isKindOfClass:NSDictionary.class]) {
        continue;
      }
      NSDictionary* clip = clipItem;
      makelab::imgui::ClipItem nextClip;
      nextClip.id = StringValue(clip, @"id");
      nextClip.name = StringValue(clip, @"name", nextClip.id.c_str());
      nextClip.type = StringValue(clip, @"type", nextTrack.kind.c_str());
      nextClip.trackId = StringValue(clip, @"trackId", nextTrack.id.c_str());
      nextClip.assetId = StringValue(clip, @"assetId");
      const int64_t canonicalStartFrame = static_cast<int64_t>(std::llround(DoubleValue(clip, @"startFrame", -1.0)));
      const int64_t canonicalDurationFrames = static_cast<int64_t>(std::llround(DoubleValue(clip, @"durationFrames", -1.0)));
      const int64_t canonicalTrimInFrame = static_cast<int64_t>(std::llround(DoubleValue(clip, @"trimInFrame", -1.0)));
      if (canonicalStartFrame >= 0 && canonicalDurationFrames > 0) {
        nextClip.startFrame = canonicalStartFrame;
        nextClip.durationFrames = canonicalDurationFrames;
        nextClip.trimInSeconds = canonicalTrimInFrame >= 0
                                     ? makelab::timeline::FrameToSeconds({canonicalTrimInFrame}, state.frameRate)
                                     : DoubleValue(clip, @"trimIn", 0.0);
        nextClip.startSeconds = makelab::timeline::FrameToSeconds({nextClip.startFrame}, state.frameRate);
        nextClip.durationSeconds = makelab::timeline::FrameToSeconds({nextClip.durationFrames}, state.frameRate);
      } else {
        if (canonicalStartFrame >= 0 || canonicalDurationFrames >= 0) {
          state.diagnostics.push_back("UnitedGate blocked invalid canonical timing for clip " + nextClip.id + ": startFrame and durationFrames must both be present and durationFrames must be positive.");
        }
        nextClip.startSeconds = DoubleValue(clip, @"start", 0.0);
        const double legacyDuration = DoubleValue(clip, @"duration", std::numeric_limits<double>::quiet_NaN());
        nextClip.durationSeconds = legacyDuration;
        nextClip.trimInSeconds = DoubleValue(clip, @"trimIn", 0.0);
        if (!std::isfinite(nextClip.startSeconds) || nextClip.startSeconds < 0.0 ||
            !std::isfinite(nextClip.durationSeconds) || nextClip.durationSeconds <= 0.0) {
          state.diagnostics.push_back("UnitedGate blocked invalid legacy timing for clip " + nextClip.id + ": start must be non-negative and duration must be positive.");
          nextClip.startFrame = -1;
          nextClip.durationFrames = 0;
        } else {
          const auto frameRange = makelab::timeline::RangeFromLegacySeconds(nextClip.startSeconds, nextClip.durationSeconds, state.frameRate);
          nextClip.startFrame = frameRange.startFrame;
          nextClip.durationFrames = std::max<int64_t>(1, frameRange.endFrame - frameRange.startFrame);
        }
      }
      NSDictionary* style = DictionaryValue(clip, @"style");
      nextClip.x = DoubleValue(style, @"x", 0.0);
      nextClip.y = DoubleValue(style, @"y", 0.0);
      nextClip.width = DoubleValue(style, @"width", 0.0);
      nextClip.height = DoubleValue(style, @"height", 0.0);
      nextClip.anchorX = DoubleValue(style, @"anchorX", 0.5);
      nextClip.anchorY = DoubleValue(style, @"anchorY", 0.5);
      nextClip.opacity = DoubleValue(style, @"opacity", 1.0);
      nextClip.rotationDegrees = DoubleValue(style, @"rotation", 0.0);
      nextClip.scaleX = DoubleValue(style, @"scaleX", 1.0);
      nextClip.scaleY = DoubleValue(style, @"scaleY", 1.0);
      nextClip.skewXDegrees = DoubleValue(style, @"skewX", 0.0);
      nextClip.skewYDegrees = DoubleValue(style, @"skewY", 0.0);
      nextClip.cornerRadius = DoubleValue(style, @"cornerRadius", 0.0);
      nextClip.cornerRadiusTopLeft = DoubleValue(style, @"cornerRadiusTopLeft", nextClip.cornerRadius);
      nextClip.cornerRadiusTopRight = DoubleValue(style, @"cornerRadiusTopRight", nextClip.cornerRadius);
      nextClip.cornerRadiusBottomRight = DoubleValue(style, @"cornerRadiusBottomRight", nextClip.cornerRadius);
      nextClip.cornerRadiusBottomLeft = DoubleValue(style, @"cornerRadiusBottomLeft", nextClip.cornerRadius);
      nextClip.fit = OptionalStringValue(style, @"fit", "cover");
      NSDictionary* fill = DictionaryValue(style, @"fill");
      nextClip.fillEnabled = BoolValue(fill, @"enabled", HasObjectEntries(fill));
      nextClip.fillColor = OptionalStringValue(fill, @"color", "#FFFFFF");
      nextClip.fillOpacity = DoubleValue(fill, @"opacity", 1.0);
      NSDictionary* border = DictionaryValue(style, @"border");
      nextClip.borderEnabled = BoolValue(border, @"enabled", HasObjectEntries(border));
      nextClip.borderWidth = DoubleValue(border, @"width", 0.0);
      nextClip.borderColor = OptionalStringValue(border, @"color", "#FFFFFF");
      nextClip.borderOpacity = DoubleValue(border, @"opacity", 1.0);
      nextClip.borderPosition = OptionalStringValue(border, @"position", OptionalStringValue(border, @"align", "inside"));
      NSDictionary* shadow = DictionaryValue(style, @"shadow");
      nextClip.shadowEnabled = BoolValue(shadow, @"enabled", HasObjectEntries(shadow));
      nextClip.shadowX = DoubleValue(shadow, @"offsetX", DoubleValue(shadow, @"x", 0.0));
      nextClip.shadowY = DoubleValue(shadow, @"offsetY", DoubleValue(shadow, @"y", 0.0));
      nextClip.shadowBlur = DoubleValue(shadow, @"blur", DoubleValue(shadow, @"radius", 0.0));
      nextClip.shadowSpread = DoubleValue(shadow, @"spread", 0.0);
      nextClip.shadowColor = OptionalStringValue(shadow, @"color", "#000000");
      nextClip.shadowOpacity = DoubleValue(shadow, @"opacity", 1.0);
      nextClip.hasEffects = HasObjectEntries(DictionaryValue(style, @"effects"));
      NSDictionary* text = DictionaryValue(clip, @"text");
      nextClip.textContent = OptionalStringValue(text, @"content", nextClip.name.empty() ? "Text" : nextClip.name);
      nextClip.textFontFamily = OptionalStringValue(text, @"fontFamily", "SF Pro Display");
      nextClip.textFontSize = DoubleValue(text, @"fontSize", 48.0);
      nextClip.textFontWeight = OptionalStringValue(text, @"fontWeight", "400");
      nextClip.textColor = OptionalStringValue(text, @"color", nextClip.fillEnabled ? nextClip.fillColor : "#FFFFFF");
      nextClip.textAlign = OptionalStringValue(text, @"align", "center");
      nextClip.textLineHeight = DoubleValue(text, @"lineHeight", 1.0);
      nextClip.textLetterSpacing = DoubleValue(text, @"letterSpacing", 0.0);
      nextClip.textStrokeColor = OptionalStringValue(text, @"strokeColor", "#000000");
      nextClip.textStrokeWidth = DoubleValue(text, @"strokeWidth", 0.0);
      NSDictionary* shape = DictionaryValue(clip, @"shape");
      nextClip.shapeKind = OptionalStringValue(shape, @"kind", "rectangle");
      ParseClipAnimations(nextClip, clip, style);
      ParseClipEffects(nextClip, style);
      nextTrack.clips.push_back(nextClip);
    }

    if (!nextTrack.hidden && (!nextTrack.clips.empty() || nextTrack.kind != "native-scene")) {
      state.tracks.push_back(nextTrack);
    }
  }

  std::unordered_set<std::string> assetIds;
  for (const auto& asset : state.assets) {
    if (asset.id.empty()) {
      state.diagnostics.push_back("UnitedGate blocked: every asset entry must have a stable id.");
      continue;
    }
    assetIds.insert(asset.id);
  }
  for (const auto& track : state.tracks) {
    if (track.id.empty()) {
      state.diagnostics.push_back("UnitedGate blocked: every accepted track must have a stable id.");
    }
    for (const auto& clip : track.clips) {
      const std::string clipLabel = clip.id.empty() ? "<missing-id>" : clip.id;
      if (clip.id.empty()) {
        state.diagnostics.push_back("UnitedGate blocked: every accepted clip must have a stable id.");
      }
      if (clip.trackId != track.id) {
        state.diagnostics.push_back("UnitedGate blocked clip " + clipLabel + ": clip.trackId must match the owning track id.");
      }
      if (clip.startFrame < 0) {
        state.diagnostics.push_back("UnitedGate blocked clip " + clipLabel + ": startFrame must be non-negative.");
      }
      if (clip.durationFrames <= 0) {
        state.diagnostics.push_back("UnitedGate blocked clip " + clipLabel + ": durationFrames must be positive.");
      }
      if (clip.startFrame >= 0 && clip.durationFrames > 0 && clip.startFrame + clip.durationFrames > state.durationFrames) {
        state.diagnostics.push_back("UnitedGate blocked clip " + clipLabel + ": frame range exceeds composition durationFrames.");
      }
      const bool requiresAsset = clip.type == "video" || clip.type == "image" || clip.type == "audio";
      if (requiresAsset && (clip.assetId.empty() || assetIds.find(clip.assetId) == assetIds.end())) {
        state.diagnostics.push_back("UnitedGate blocked clip " + clipLabel + ": media clips must reference an accepted asset id.");
      }
    }
  }

  AppendMotionQualityDiagnostics(state);

  const bool hasBlockingDiagnostic = std::any_of(state.diagnostics.begin(), state.diagnostics.end(), [](const std::string& message) {
    return message.rfind("UnitedGate blocked", 0) == 0;
  });
  if (hasBlockingDiagnostic) {
    state.opened = false;
  }

  if (state.tracks.empty()) {
    state.diagnostics.push_back("Workspace opened. timeline.json has no accepted editable clips yet.");
  }

  return state;
}

}  // namespace

@interface MakelabMetalView : MTKView
@end

@implementation MakelabMetalView
- (BOOL)acceptsFirstResponder {
  return YES;
}
- (void)requestInteractiveRedraw {
  [self setNeedsDisplay:YES];
}
- (void)mouseDown:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super mouseDown:event];
}
- (void)mouseUp:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super mouseUp:event];
}
- (void)mouseDragged:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super mouseDragged:event];
}
- (void)mouseMoved:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super mouseMoved:event];
}
- (void)rightMouseDown:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super rightMouseDown:event];
}
- (void)scrollWheel:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super scrollWheel:event];
}
- (void)keyDown:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super keyDown:event];
}
- (void)keyUp:(NSEvent*)event {
  [self requestInteractiveRedraw];
  [super keyUp:event];
}
@end

@interface AppDelegate : NSObject <NSApplicationDelegate, MTKViewDelegate>
@property(nonatomic, strong) NSWindow* window;
@property(nonatomic, strong) MakelabMetalView* view;
@property(nonatomic, strong) id<MTLDevice> device;
@property(nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property(nonatomic) BOOL designFixture;
@property(nonatomic) CFTimeInterval startTime;
@property(nonatomic) BOOL playingDesignFixture;
@property(nonatomic, copy) NSString* initialWorkspacePath;
- (void)workspaceFilesDidChange;
@end

static void WorkspaceFSEventsCallback(ConstFSEventStreamRef stream,
                                      void* clientInfo,
                                      size_t eventCount,
                                      void* eventPaths,
                                      const FSEventStreamEventFlags eventFlags[],
                                      const FSEventStreamEventId eventIds[]) {
  (void)stream;
  (void)eventCount;
  (void)eventPaths;
  (void)eventFlags;
  (void)eventIds;
  AppDelegate* delegate = (__bridge AppDelegate*)clientInfo;
  [delegate workspaceFilesDidChange];
}

struct CachedFinalFrameSurface {
  id<MTLTexture> texture = nil;
  uint64_t sessionGeneration = 0;
  int64_t frameIndex = -1;
  int width = 0;
  int height = 0;
};

struct NativeRealtimeResourceScheduler {
  std::atomic<uint64_t> sessionGeneration{1};
  std::atomic<uint64_t> backgroundGeneration{1};
  std::atomic<bool> exportMode{false};
  int64_t latestRequestedFrame = -1;

  uint64_t beginProjectMutation() {
    backgroundGeneration.fetch_add(1);
    const uint64_t next = sessionGeneration.fetch_add(1) + 1;
    latestRequestedFrame = -1;
    return next;
  }

  uint64_t cancelBackgroundWork() {
    return backgroundGeneration.fetch_add(1) + 1;
  }

  bool beginExportMode() {
    bool expected = false;
    if (!exportMode.compare_exchange_strong(expected, true)) {
      return false;
    }
    cancelBackgroundWork();
    return true;
  }

  void endExportMode() {
    exportMode.store(false);
    cancelBackgroundWork();
  }

  bool isExporting() const {
    return exportMode.load();
  }

  uint64_t captureBackgroundGeneration() const {
    return backgroundGeneration.load();
  }

  bool acceptsSession(uint64_t generation) const {
    return generation == sessionGeneration.load();
  }

  bool acceptsBackground(uint64_t generation) const {
    return generation == backgroundGeneration.load();
  }

  void noteFrameRequest(int64_t frameIndex) {
    latestRequestedFrame = frameIndex;
  }

  bool canRunBackgroundWarmup(bool playing, bool renderInFlight, bool liveScopeInFlight) const {
    return !isExporting() && !playing && !renderInFlight && !liveScopeInFlight;
  }

  int videoWarmupFrameBudget(const makelab::imgui::WorkspaceViewState& workspace) const {
    const int64_t oneSecond = std::max<int64_t>(12, makelab::timeline::SecondsToFrameRound(1.0, workspace.frameRate));
    return static_cast<int>(std::min<int64_t>(240, std::max<int64_t>(48, oneSecond * 3)));
  }

  int activationWarmupFrameBudget(const makelab::imgui::WorkspaceViewState& workspace) const {
    const int64_t halfSecond = std::max<int64_t>(6, makelab::timeline::SecondsToFrameRound(0.5, workspace.frameRate));
    return static_cast<int>(std::min<int64_t>(24, halfSecond));
  }
};

@implementation AppDelegate {
  makelab::imgui::WorkspaceViewState _workspace;
  makelab::imgui::LibrarySection _librarySection;
  std::string _status;
  ImFont* _iconFont;
  makelab::authoring::ProjectAuthoringService _authoringService;
  MacMetalRenderFrameExecutor* _renderExecutor;
  MacNativePlaybackScheduler _playbackScheduler;
  id<MTLTexture> _finalFrameSurface;
  makelab::imgui::EditorShellConfig::LiveScopeSnapshot _liveScope;
  int64_t _lastLiveScopeFrameIndex;
  BOOL _liveScopeReadbackInFlight;
  double _lastLiveScopeRequestHostTime;
  double _lastRenderedTimelineTimeSeconds;
  int64_t _lastRenderedFrameIndex;
  int _lastRenderedWidth;
  int _lastRenderedHeight;
  double _lastRenderSubmitMs;
  double _lastLiveScopeReadbackMs;
  BOOL _needsFinalFrameRender;
  BOOL _openProjectPanelInFlight;
  FSEventStreamRef _workspaceEventStream;
  std::string _workspaceSourceSignature;
  uint64_t _workspaceReloadGeneration;
  NativeRealtimeResourceScheduler _resourceScheduler;
  dispatch_queue_t _renderQueue;
  BOOL _renderInFlight;
  BOOL _renderRequestPending;
  BOOL _pendingScrubPrewarm;
  uint64_t _renderSessionGeneration;
  BOOL _exportPanelInFlight;
  BOOL _exportInFlight;
  double _exportProgress;
  std::string _exportPhase;
  std::string _exportDestination;
  NativeAudioPreviewEngine* _audioPreviewEngine;
  std::string _audioPreviewSignature;
  int _audioPreviewClipCount;
	  std::unordered_map<int64_t, CachedFinalFrameSurface> _finalFrameSurfaceCache;
	  std::deque<int64_t> _finalFrameSurfaceCacheOrder;
	  BOOL _finalFrameCacheWarmInFlight;
	  BOOL _videoTextureWarmInFlight;
	}

- (instancetype)initWithDesignFixture:(BOOL)designFixture initialWorkspacePath:(NSString*)initialWorkspacePath {
  self = [super init];
  if (self) {
    _designFixture = designFixture;
    _initialWorkspacePath = [initialWorkspacePath copy];
    _status = "Choose Open Folder to bind a live MakeLab workspace.";
    _librarySection = makelab::imgui::LibrarySection::Media;
    _lastLiveScopeFrameIndex = -1;
    _liveScopeReadbackInFlight = NO;
    _lastLiveScopeRequestHostTime = -1.0;
    _lastRenderedTimelineTimeSeconds = -1.0;
    _lastRenderedFrameIndex = -1;
    _lastRenderedWidth = 0;
    _lastRenderedHeight = 0;
    _lastRenderSubmitMs = 0.0;
    _lastLiveScopeReadbackMs = 0.0;
    _needsFinalFrameRender = YES;
    _openProjectPanelInFlight = NO;
    _workspaceReloadGeneration = 0;
    _renderQueue = dispatch_queue_create("com.makelab.imgui-professional.final-frame-render", DISPATCH_QUEUE_SERIAL);
	    _renderInFlight = NO;
	    _renderRequestPending = NO;
	    _pendingScrubPrewarm = NO;
	    _videoTextureWarmInFlight = NO;
    _renderSessionGeneration = 1;
    _exportPanelInFlight = NO;
    _exportInFlight = NO;
    _exportProgress = 0.0;
    _exportPhase.clear();
    _exportDestination.clear();
    _audioPreviewEngine = new NativeAudioPreviewEngine();
    _audioPreviewClipCount = 0;
    _finalFrameCacheWarmInFlight = NO;
  }
  return self;
}

- (void)applicationDidFinishLaunching:(NSNotification*)notification {
  (void)notification;

  self.device = MTLCreateSystemDefaultDevice();
  self.commandQueue = [self.device newCommandQueue];
  _renderExecutor = new MacMetalRenderFrameExecutor(self.device, self.commandQueue);
  self.startTime = CACurrentMediaTime();

  NSRect frame = NSMakeRect(0, 0, 1680, 912);
  self.window = [[NSWindow alloc] initWithContentRect:frame
                                            styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable |
                                                      NSWindowStyleMaskResizable | NSWindowStyleMaskMiniaturizable
                                              backing:NSBackingStoreBuffered
                                                defer:NO];
  self.window.title = @"Makelab IMGUI Professional";
  [self.window center];

  self.view = [[MakelabMetalView alloc] initWithFrame:frame device:self.device];
  self.view.delegate = self;
  self.view.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
  self.view.depthStencilPixelFormat = MTLPixelFormatInvalid;
  self.view.clearColor = MTLClearColorMake(0.027, 0.043, 0.047, 1.0);
  self.view.enableSetNeedsDisplay = YES;
  self.view.paused = YES;
  self.view.preferredFramesPerSecond = 30;
  self.window.contentView = self.view;
  [self.window makeKeyAndOrderFront:nil];
  [self.view.window makeFirstResponder:self.view];
  [self.view setNeedsDisplay:YES];

  IMGUI_CHECKVERSION();
  ImGui::CreateContext();
  ImGuiIO& io = ImGui::GetIO();
  io.ConfigFlags |= ImGuiConfigFlags_NavEnableKeyboard;
  io.IniFilename = nullptr;
  NSString* uiFontPath = [[NSBundle mainBundle] pathForResource:@"Inter-Regular"
                                                        ofType:@"ttf"
                                                   inDirectory:@"fonts"];
  if (uiFontPath != nil) {
    ImFontConfig uiFontConfig;
    uiFontConfig.OversampleH = 2;
    uiFontConfig.OversampleV = 2;
    uiFontConfig.PixelSnapH = true;
    io.FontDefault = io.Fonts->AddFontFromFileTTF(uiFontPath.UTF8String, 13.0f, &uiFontConfig);
  }
  NSString* iconFontPath = [[NSBundle mainBundle] pathForResource:@"fa-solid-900"
                                                          ofType:@"otf"
                                                     inDirectory:@"fonts"];
  if (iconFontPath != nil) {
    ImFontConfig iconFontConfig;
    iconFontConfig.OversampleH = 2;
    iconFontConfig.OversampleV = 2;
    iconFontConfig.PixelSnapH = true;
    static const ImWchar iconRanges[] = {
        0x002B, 0x002B,
        0xE131, 0xE131,
        0xF001, 0xF001,
        0xF00E, 0xF010,
        0xF019, 0xF019,
        0xF028, 0xF028,
        0xF031, 0xF031,
        0xF036, 0xF038,
        0xF03D, 0xF03E,
        0xF048, 0xF048,
        0xF04B, 0xF04B,
        0xF051, 0xF051,
        0xF06E, 0xF06E,
        0xF074, 0xF074,
        0xF07C, 0xF07E,
        0xF0C4, 0xF0C9,
        0xF1DE, 0xF1DE,
        0xF1F8, 0xF1F8,
        0xF245, 0xF245,
        0xF256, 0xF256,
        0xF2EA, 0xF2EA,
        0xF2F9, 0xF2F9,
        0xF302, 0xF302,
        0xF53F, 0xF53F,
        0xF58E, 0xF58E,
        0xF5FD, 0xF5FD,
        0xF61F, 0xF61F,
        0xF83E, 0xF83E,
        0,
    };
    _iconFont = io.Fonts->AddFontFromFileTTF(iconFontPath.UTF8String, 14.0f, &iconFontConfig, iconRanges);
  }
  if (io.FontDefault == nullptr) {
    _status = "Inter Regular native UI font failed to load.";
  }
  if (_iconFont == nullptr) {
    _iconFont = nullptr;
    _status = "Native editor icon font failed validation.";
  }
  ImGui::StyleColorsDark();
  ImGui_ImplOSX_Init(self.view);
  ImGui_ImplMetal_Init(self.device);

  if (self.initialWorkspacePath.length > 0) {
    NSURL* url = [NSURL fileURLWithPath:self.initialWorkspacePath isDirectory:YES];
    _workspace = LoadWorkspaceState(url);
    _finalFrameSurface = nil;
    _liveScope.ready = false;
    _lastLiveScopeFrameIndex = -1;
    _liveScopeReadbackInFlight = NO;
    _lastLiveScopeRequestHostTime = -1.0;
    _lastRenderedFrameIndex = -1;
    self.designFixture = NO;
    _playbackScheduler.bindTimeline(_workspace.durationSeconds, _workspace.fps);
    if (_renderExecutor != nullptr) {
      _renderExecutor->invalidateProjectResources();
      _renderExecutor->prewarmStaticImageTextures(_workspace);
      _renderExecutor->prewarmGeneratedVisualTextures(_workspace);
    }
    [self applyWorkspaceFrameRate];
    [self renderAcceptedFrame];
    if (_finalFrameSurface) {
      _status = "Workspace opened: " + _workspace.folderName + " | FinalFrameSurface ready at frame 0.";
    } else {
      _status = "Workspace opened: " + _workspace.folderName + " | RequestPreviewFrame(0) blocked.";
    }
    for (const std::string& diagnostic : _workspace.diagnostics) {
      _status += " | " + diagnostic;
    }
	    [self startWorkspaceWatcher:url];
	    [self scheduleBackgroundVideoTextureWarmup];
	    [self.view setNeedsDisplay:YES];
	  }
	}

- (void)dealloc {
  [self stopWorkspaceWatcher];
  if (_audioPreviewEngine != nullptr) {
    delete _audioPreviewEngine;
    _audioPreviewEngine = nullptr;
  }
  delete _renderExecutor;
  _renderExecutor = nullptr;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

- (void)clearFinalFrameSurfaceCache {
  _finalFrameSurfaceCache.clear();
  _finalFrameSurfaceCacheOrder.clear();
}

- (void)storeCachedFinalFrameSurface:(const FinalFrameSurfaceResult&)result
                   sessionGeneration:(uint64_t)sessionGeneration {
  if (!result.accepted()) {
    return;
  }
  id<MTLTexture> copy = CloneMetalTexture(self.device, self.commandQueue, result.texture);
  if (copy == nil) {
    return;
  }
  static constexpr size_t kMaxCachedFinalFrameSurfaces = 32;
  const int64_t frameIndex = result.surfaceFrame;
  if (_finalFrameSurfaceCache.find(frameIndex) == _finalFrameSurfaceCache.end()) {
    _finalFrameSurfaceCacheOrder.push_back(frameIndex);
  }
  _finalFrameSurfaceCache[frameIndex] = CachedFinalFrameSurface{
      copy,
      sessionGeneration,
      frameIndex,
      result.width,
      result.height,
  };
  while (_finalFrameSurfaceCacheOrder.size() > kMaxCachedFinalFrameSurfaces) {
    const int64_t oldest = _finalFrameSurfaceCacheOrder.front();
    _finalFrameSurfaceCacheOrder.pop_front();
    _finalFrameSurfaceCache.erase(oldest);
  }
}

- (void)insertCachedFinalFrameSurface:(const CachedFinalFrameSurface&)surface {
  if (surface.texture == nil || surface.frameIndex < 0 ||
      surface.sessionGeneration != _renderSessionGeneration ||
      surface.width != _workspace.width ||
      surface.height != _workspace.height) {
    return;
  }
  static constexpr size_t kMaxCachedFinalFrameSurfaces = 32;
  if (_finalFrameSurfaceCache.find(surface.frameIndex) == _finalFrameSurfaceCache.end()) {
    _finalFrameSurfaceCacheOrder.push_back(surface.frameIndex);
  }
  _finalFrameSurfaceCache[surface.frameIndex] = surface;
  while (_finalFrameSurfaceCacheOrder.size() > kMaxCachedFinalFrameSurfaces) {
    const int64_t oldest = _finalFrameSurfaceCacheOrder.front();
    _finalFrameSurfaceCacheOrder.pop_front();
    _finalFrameSurfaceCache.erase(oldest);
  }
}

- (int)cachedFinalFrameSurfaceCountAheadFromFrame:(int64_t)frameIndex limit:(int)limit {
  if (_workspace.durationFrames <= 0) {
    return 0;
  }
  int count = 0;
  for (int offset = 1; offset <= limit; ++offset) {
    const int64_t frame = (frameIndex + offset) % _workspace.durationFrames;
    auto cached = _finalFrameSurfaceCache.find(frame);
    if (cached != _finalFrameSurfaceCache.end() &&
        cached->second.texture != nil &&
        cached->second.sessionGeneration == _renderSessionGeneration &&
        cached->second.width == _workspace.width &&
        cached->second.height == _workspace.height) {
      count += 1;
    }
  }
  return count;
}

- (BOOL)applyCachedFinalFrameSurfaceForRequestedFrame:(int64_t)frameIndex {
  auto cached = _finalFrameSurfaceCache.find(frameIndex);
  if (cached == _finalFrameSurfaceCache.end()) {
    return NO;
  }
  const CachedFinalFrameSurface& surface = cached->second;
  if (surface.texture == nil ||
      surface.sessionGeneration != _renderSessionGeneration ||
      surface.width != _workspace.width ||
      surface.height != _workspace.height) {
    _finalFrameSurfaceCache.erase(cached);
    return NO;
  }
  if (!_playbackScheduler.acceptRequestedFrame(_playbackScheduler.requestGeneration())) {
    return NO;
  }
  _finalFrameSurface = surface.texture;
  _lastRenderSubmitMs = 0.0;
  _lastRenderedTimelineTimeSeconds = _playbackScheduler.timeSeconds();
  _lastRenderedFrameIndex = _playbackScheduler.acceptedFrame();
  _lastRenderedWidth = _workspace.width;
  _lastRenderedHeight = _workspace.height;
  [self updateLiveScopeFromAcceptedSurface];
  _needsFinalFrameRender = NO;
  return YES;
}

- (void)scheduleRollingFinalFrameCacheFromFrame:(int64_t)frameIndex {
  if (!_workspace.opened || !_playbackScheduler.isPlaying() || _renderExecutor == nullptr || _renderQueue == nil) {
    return;
  }
  if (_renderInFlight || _finalFrameCacheWarmInFlight) {
    return;
  }
  static constexpr int kTargetAhead = 10;
  static constexpr int kWarmChunk = 6;
  if ([self cachedFinalFrameSurfaceCountAheadFromFrame:frameIndex limit:kTargetAhead] >= kTargetAhead / 2) {
    return;
  }

  _finalFrameCacheWarmInFlight = YES;
  const makelab::imgui::WorkspaceViewState workspace = _workspace;
  const uint64_t sessionGeneration = _renderSessionGeneration;
  MacMetalRenderFrameExecutor* executor = _renderExecutor;
  AppDelegate* delegate = self;
  std::vector<int64_t> frames;
  for (int offset = 1; offset <= kTargetAhead && static_cast<int>(frames.size()) < kWarmChunk; ++offset) {
    const int64_t frame = (frameIndex + offset) % std::max<int64_t>(1, workspace.durationFrames);
    if (_finalFrameSurfaceCache.find(frame) == _finalFrameSurfaceCache.end()) {
      frames.push_back(frame);
    }
  }
  if (frames.empty()) {
    _finalFrameCacheWarmInFlight = NO;
    return;
  }

  auto warmedSurfaces = std::make_shared<std::vector<CachedFinalFrameSurface>>();
  dispatch_async(_renderQueue, ^{
    @autoreleasepool {
      for (int64_t frame : frames) {
        const uint64_t cacheGeneration = 0xD000000000000000ULL + static_cast<uint64_t>(frame);
        FinalFrameSurfaceResult warmed = executor->render(workspace, frame, cacheGeneration, true, true);
        if (!warmed.accepted()) {
          continue;
        }
        id<MTLTexture> copy = CloneMetalTexture(delegate.device, delegate.commandQueue, warmed.texture);
        if (copy == nil) {
          continue;
        }
        warmedSurfaces->push_back(CachedFinalFrameSurface{
            copy,
            sessionGeneration,
            warmed.surfaceFrame,
            warmed.width,
            warmed.height,
        });
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (sessionGeneration == delegate->_renderSessionGeneration) {
          for (const auto& surface : *warmedSurfaces) {
            [delegate insertCachedFinalFrameSurface:surface];
          }
        }
        delegate->_finalFrameCacheWarmInFlight = NO;
        [delegate.view setNeedsDisplay:YES];
      });
    }
  });
}

- (void)acceptFinalFrameSurfaceResult:(const FinalFrameSurfaceResult&)result elapsedMs:(double)elapsedMs {
  _lastRenderSubmitMs = elapsedMs;
  if (result.accepted() && _playbackScheduler.acceptRequestedFrame(result.requestGeneration)) {
    _finalFrameSurface = result.texture;
    _lastRenderedTimelineTimeSeconds = _playbackScheduler.timeSeconds();
    _lastRenderedFrameIndex = _playbackScheduler.acceptedFrame();
    _lastRenderedWidth = _workspace.width;
    _lastRenderedHeight = _workspace.height;
    [self updateLiveScopeFromAcceptedSurface];
    if (!_playbackScheduler.isPlaying()) {
      [self scheduleBackgroundVideoTextureWarmup];
    }
  }
  _needsFinalFrameRender = NO;
}

- (void)renderAcceptedFrame {
  if (!_workspace.opened || _renderExecutor == nullptr || _renderQueue == nil) {
    return;
  }

  const int64_t requestedFrame = _playbackScheduler.requestFrameForNow();
  const uint64_t requestGeneration = _playbackScheduler.requestGeneration();
  const bool playing = _playbackScheduler.isPlaying();
  const makelab::imgui::WorkspaceViewState workspace = _workspace;
  MacMetalRenderFrameExecutor* executor = _renderExecutor;
  __block FinalFrameSurfaceResult result;
  __block double elapsedMs = 0.0;
  dispatch_sync(_renderQueue, ^{
    @autoreleasepool {
      const double renderStart = CACurrentMediaTime();
      result = executor->render(workspace, requestedFrame, requestGeneration, playing, true);
      elapsedMs = (CACurrentMediaTime() - renderStart) * 1000.0;
    }
  });
  [self acceptFinalFrameSurfaceResult:result elapsedMs:elapsedMs];
}

- (void)prewarmPlaybackFinalFrameSurfacesFromFrame:(int64_t)frameIndex {
  if (!_workspace.opened || _renderExecutor == nullptr || _renderQueue == nil) {
    return;
  }
  [self clearFinalFrameSurfaceCache];
  const makelab::imgui::WorkspaceViewState workspace = _workspace;
  const int64_t startFrame = std::clamp<int64_t>(frameIndex, 0, std::max<int64_t>(0, workspace.durationFrames - 1));
  const uint64_t sessionGeneration = _renderSessionGeneration;
  const uint64_t currentRequestGeneration = _playbackScheduler.requestGeneration();
  const int64_t durationFrames = std::max<int64_t>(1, workspace.durationFrames);
  const int warmCount = static_cast<int>(std::min<int64_t>(
      32,
      std::max<int64_t>(8, makelab::timeline::SecondsToFrameRound(1.0, workspace.frameRate))));
  MacMetalRenderFrameExecutor* executor = _renderExecutor;
  __block FinalFrameSurfaceResult currentResult;
  __block double currentElapsedMs = 0.0;

  dispatch_sync(_renderQueue, ^{
    @autoreleasepool {
      executor->prewarmScrubVideoWindow(workspace, startFrame);
      for (int offset = 1; offset <= warmCount && offset < durationFrames; ++offset) {
        const int64_t frame = (startFrame + offset) % durationFrames;
        const uint64_t cacheGeneration = 0xC000000000000000ULL + static_cast<uint64_t>(frame);
        FinalFrameSurfaceResult warmed = executor->render(workspace, frame, cacheGeneration, true, true);
        [self storeCachedFinalFrameSurface:warmed sessionGeneration:sessionGeneration];
      }
      const double renderStart = CACurrentMediaTime();
      currentResult = executor->render(workspace, startFrame, currentRequestGeneration, false, true);
      currentElapsedMs = (CACurrentMediaTime() - renderStart) * 1000.0;
    }
  });
  [self acceptFinalFrameSurfaceResult:currentResult elapsedMs:currentElapsedMs];
}

- (void)drainRenderQueueBeforeProjectMutation {
  _renderSessionGeneration += 1;
  _resourceScheduler.beginProjectMutation();
  [self clearFinalFrameSurfaceCache];
  if (_audioPreviewEngine != nullptr) {
    _audioPreviewEngine->stop();
  }
  _audioPreviewSignature.clear();
  _audioPreviewClipCount = 0;
  if (_renderQueue != nil) {
    dispatch_sync(_renderQueue, ^{});
  }
	  _renderInFlight = NO;
	  _renderRequestPending = NO;
	  _pendingScrubPrewarm = NO;
	  _finalFrameCacheWarmInFlight = NO;
	  _videoTextureWarmInFlight = NO;
	}

- (void)scheduleFinalFrameRenderWithScrubPrewarm:(BOOL)scrubPrewarm {
  if (!_workspace.opened || _renderExecutor == nullptr || _renderQueue == nil) {
    return;
  }
  _pendingScrubPrewarm = _pendingScrubPrewarm || scrubPrewarm;
  if (_renderInFlight) {
    _renderRequestPending = YES;
    return;
  }

  _renderInFlight = YES;
  _renderRequestPending = NO;
  const BOOL shouldPrewarmScrub = _pendingScrubPrewarm;
  _pendingScrubPrewarm = NO;
	  const makelab::imgui::WorkspaceViewState workspace = _workspace;
	  const bool playing = _playbackScheduler.isPlaying();
	  const int64_t requestedFrame = playing ? _playbackScheduler.requestFrameForNow() : _playbackScheduler.requestedFrame();
	  const uint64_t requestGeneration = _playbackScheduler.requestGeneration();
	  _resourceScheduler.noteFrameRequest(requestedFrame);
	  if (playing || scrubPrewarm) {
	    _resourceScheduler.cancelBackgroundWork();
	  }
	  const NativeRenderIntent renderIntent = playing
	                                             ? NativeRenderIntent::PlaybackRealtime
	                                             : (shouldPrewarmScrub ? NativeRenderIntent::ScrubInteractive
	                                                                  : NativeRenderIntent::PausedPreview);
	  const bool realtimeTexturePath = playing || shouldPrewarmScrub;
	  const uint64_t renderSessionGeneration = _renderSessionGeneration;
	  MacMetalRenderFrameExecutor* executor = _renderExecutor;
	  AppDelegate* delegate = self;

  dispatch_async(_renderQueue, ^{
    @autoreleasepool {
	      if (shouldPrewarmScrub && renderIntent == NativeRenderIntent::PausedPreview) {
	        executor->prewarmScrubVideoWindow(workspace, requestedFrame);
	      }
      const double renderStart = CACurrentMediaTime();
      auto finishOnMain = ^(FinalFrameSurfaceResult result, double elapsedMs) {
        dispatch_async(dispatch_get_main_queue(), ^{
          if (renderSessionGeneration != delegate->_renderSessionGeneration) {
            return;
          }
          delegate->_renderInFlight = NO;
          [delegate acceptFinalFrameSurfaceResult:result elapsedMs:elapsedMs];
          if (delegate->_renderRequestPending || delegate->_playbackScheduler.isPlaying()) {
            BOOL nextScrubPrewarm = delegate->_pendingScrubPrewarm;
            delegate->_renderRequestPending = NO;
            [delegate scheduleFinalFrameRenderWithScrubPrewarm:nextScrubPrewarm];
          }
          [delegate.view setNeedsDisplay:YES];
        });
      };
	      if (playing || shouldPrewarmScrub) {
	        FinalFrameSurfaceResult scheduled = executor->render(workspace,
	                                                             requestedFrame,
	                                                             requestGeneration,
	                                                             realtimeTexturePath,
	                                                             false,
	                                                             ^(FinalFrameSurfaceResult completed) {
	          const double elapsedMs = (CACurrentMediaTime() - renderStart) * 1000.0;
	          finishOnMain(completed, elapsedMs);
	        },
	                                                             renderIntent);
	        if (!scheduled.accepted()) {
	          const double elapsedMs = (CACurrentMediaTime() - renderStart) * 1000.0;
	          finishOnMain(scheduled, elapsedMs);
	        }
	      } else {
	        FinalFrameSurfaceResult result = executor->render(workspace,
	                                                          requestedFrame,
	                                                          requestGeneration,
	                                                          playing,
	                                                          true,
	                                                          nil,
	                                                          renderIntent);
        const double elapsedMs = (CACurrentMediaTime() - renderStart) * 1000.0;
        finishOnMain(result, elapsedMs);
      }
    }
  });
}

- (void)updateLiveScopeFromAcceptedSurface {
  if (_finalFrameSurface == nil || !_workspace.opened) {
    _liveScope.ready = false;
    return;
  }
  const int64_t frameIndex = _playbackScheduler.acceptedFrame();
  if (frameIndex == _lastLiveScopeFrameIndex) {
    return;
  }
  if (_liveScopeReadbackInFlight) {
    return;
  }
  const double frameBudgetMs = 1000.0 / std::max(1.0, makelab::timeline::Fps(_workspace.frameRate));
  if (_playbackScheduler.isPlaying() && _lastRenderSubmitMs > frameBudgetMs * 0.55) {
    return;
  }
  const double now = CACurrentMediaTime();
  const double minInterval = _playbackScheduler.isPlaying() ? (1.0 / 12.0) : (1.0 / 24.0);
  if (_lastLiveScopeRequestHostTime >= 0.0 && now - _lastLiveScopeRequestHostTime < minInterval) {
    return;
  }
  const int width = static_cast<int>(_finalFrameSurface.width);
  const int height = static_cast<int>(_finalFrameSurface.height);
  if (width <= 0 || height <= 0) {
    _liveScope.ready = false;
    return;
  }
  const size_t bytesPerRow = static_cast<size_t>(width) * 4;
  const size_t alignedRowBytes = ((bytesPerRow + 255) / 256) * 256;
  id<MTLBuffer> readback = [self.device newBufferWithLength:alignedRowBytes * static_cast<size_t>(height)
                                                    options:MTLResourceStorageModeShared];
  id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
  id<MTLBlitCommandEncoder> blit = [commandBuffer blitCommandEncoder];
  if (readback == nil || commandBuffer == nil || blit == nil) {
    _liveScope.ready = false;
    return;
  }
  _liveScopeReadbackInFlight = YES;
  _lastLiveScopeRequestHostTime = now;
  const double scopeStart = now;
  id<MTLTexture> surface = _finalFrameSurface;
  [blit copyFromTexture:surface
            sourceSlice:0
            sourceLevel:0
           sourceOrigin:MTLOriginMake(0, 0, 0)
             sourceSize:MTLSizeMake(width, height, 1)
               toBuffer:readback
      destinationOffset:0
 destinationBytesPerRow:alignedRowBytes
destinationBytesPerImage:alignedRowBytes * static_cast<size_t>(height)];
  [blit endEncoding];
  AppDelegate* delegate = self;
  [commandBuffer addCompletedHandler:^(id<MTLCommandBuffer> completed) {
    makelab::imgui::EditorShellConfig::LiveScopeSnapshot next;
    if (completed.status == MTLCommandBufferStatusCompleted) {
      next.ready = true;
      next.frameIndex = frameIndex;
      next.lumaMin = 1.0f;
      next.lumaMax = 0.0f;
      const int stepX = std::max(1, width / 180);
      const int stepY = std::max(1, height / 180);
      const uint8_t* pixels = static_cast<const uint8_t*>(readback.contents);
      double sumR = 0.0;
      double sumG = 0.0;
      double sumB = 0.0;
      int sampleCount = 0;
      for (int y = 0; y < height; y += stepY) {
        const uint8_t* row = pixels + static_cast<size_t>(y) * alignedRowBytes;
        for (int x = 0; x < width; x += stepX) {
          const uint8_t* pixel = row + static_cast<size_t>(x) * 4;
          const float b = static_cast<float>(pixel[0]) / 255.0f;
          const float g = static_cast<float>(pixel[1]) / 255.0f;
          const float r = static_cast<float>(pixel[2]) / 255.0f;
          const float luma = std::clamp(0.2126f * r + 0.7152f * g + 0.0722f * b, 0.0f, 1.0f);
          const int bucket = std::clamp(static_cast<int>(luma * static_cast<float>(next.lumaBuckets.size() - 1)),
                                        0,
                                        static_cast<int>(next.lumaBuckets.size() - 1));
          next.lumaBuckets[bucket] += 1.0f;
          next.lumaMin = std::min(next.lumaMin, luma);
          next.lumaMax = std::max(next.lumaMax, luma);
          sumR += r;
          sumG += g;
          sumB += b;
          sampleCount += 1;
        }
      }
      if (sampleCount > 0) {
        const float inv = 1.0f / static_cast<float>(sampleCount);
        next.averageR = static_cast<float>(sumR) * inv;
        next.averageG = static_cast<float>(sumG) * inv;
        next.averageB = static_cast<float>(sumB) * inv;
        for (float& value : next.lumaBuckets) {
          value *= inv;
        }
      }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      delegate->_liveScopeReadbackInFlight = NO;
      delegate->_lastLiveScopeReadbackMs = (CACurrentMediaTime() - scopeStart) * 1000.0;
      if (next.ready) {
        delegate->_liveScope = next;
        delegate->_lastLiveScopeFrameIndex = frameIndex;
        [delegate.view setNeedsDisplay:YES];
      }
    });
  }];
  [commandBuffer commit];
}

- (void)stopWorkspaceWatcher {
  _workspaceReloadGeneration += 1;
  if (_workspaceEventStream == nullptr) {
    return;
  }
  FSEventStreamStop(_workspaceEventStream);
  FSEventStreamInvalidate(_workspaceEventStream);
  FSEventStreamRelease(_workspaceEventStream);
  _workspaceEventStream = nullptr;
}

- (void)startWorkspaceWatcher:(NSURL*)folder {
  [self stopWorkspaceWatcher];
  if (folder == nil || !_workspace.opened) {
    _workspaceSourceSignature.clear();
    return;
  }
  _workspaceSourceSignature = WorkspaceSourceSignature(folder);
  FSEventStreamContext context{};
  context.info = (__bridge void*)self;
  CFArrayRef paths = (__bridge CFArrayRef)@[folder.path];
  _workspaceEventStream = FSEventStreamCreate(
      nullptr,
      &WorkspaceFSEventsCallback,
      &context,
      paths,
      kFSEventStreamEventIdSinceNow,
      0.12,
      kFSEventStreamCreateFlagFileEvents | kFSEventStreamCreateFlagWatchRoot | kFSEventStreamCreateFlagUseCFTypes);
  if (_workspaceEventStream == nullptr) {
    _status = "Native project watcher blocked: FSEventStream could not be created.";
    return;
  }
  FSEventStreamSetDispatchQueue(_workspaceEventStream, dispatch_get_main_queue());
  if (!FSEventStreamStart(_workspaceEventStream)) {
    FSEventStreamInvalidate(_workspaceEventStream);
    FSEventStreamRelease(_workspaceEventStream);
    _workspaceEventStream = nullptr;
    _status = "Native project watcher blocked: FSEventStream could not start.";
    return;
  }
  NSLog(@"Native project watcher active: %@", folder.path);
}

- (BOOL)reloadAcceptedWorkspaceFromDisk:(NSString*)reason {
  if (!_workspace.opened || _workspace.folderPath.empty()) {
    _status = "Project reload blocked: Open Folder first.";
    [self.view setNeedsDisplay:YES];
    return NO;
  }
  [self drainRenderQueueBeforeProjectMutation];
  const int64_t acceptedFrame = _playbackScheduler.acceptedFrame();
  NSURL* folder = [NSURL fileURLWithPath:[NSString stringWithUTF8String:_workspace.folderPath.c_str()] isDirectory:YES];
  makelab::imgui::WorkspaceViewState candidate = LoadWorkspaceState(folder);
  if (!candidate.opened) {
    _status = "UnitedGate preserved the previous accepted project state.";
    for (const std::string& diagnostic : candidate.diagnostics) {
      _status += " | " + diagnostic;
    }
    NSLog(@"%s", _status.c_str());
    [self.view setNeedsDisplay:YES];
    return NO;
  }
  _workspace = std::move(candidate);
  _workspaceSourceSignature = WorkspaceSourceSignature(folder);
  _finalFrameSurface = nil;
  _liveScope.ready = false;
  _lastLiveScopeFrameIndex = -1;
  _liveScopeReadbackInFlight = NO;
  _lastLiveScopeRequestHostTime = -1.0;
  _lastRenderedFrameIndex = -1;
  _playbackScheduler.bindTimeline(_workspace.durationSeconds, _workspace.fps);
  _playbackScheduler.scrubToFrame(std::min<int64_t>(acceptedFrame, std::max<int64_t>(0, _workspace.durationFrames - 1)));
  if (_renderExecutor != nullptr) {
    _renderExecutor->invalidateProjectResources();
    _renderExecutor->prewarmStaticImageTextures(_workspace);
    _renderExecutor->prewarmGeneratedVisualTextures(_workspace);
  }
  _needsFinalFrameRender = YES;
  [self applyWorkspaceFrameRate];
  [self renderAcceptedFrame];
  _status = ToStdString(reason);
  for (const std::string& diagnostic : _workspace.diagnostics) {
    _status += " | " + diagnostic;
  }
  if (_renderExecutor != nullptr && !_renderExecutor->diagnostic().empty()) {
    _status += " | " + _renderExecutor->diagnostic();
	  }
	  NSLog(@"%s", _status.c_str());
	  [self scheduleBackgroundVideoTextureWarmup];
	  self.view.paused = YES;
	  [self.view setNeedsDisplay:YES];
	  return YES;
}

- (void)workspaceFilesDidChange {
  if (!_workspace.opened || _workspace.folderPath.empty()) {
    return;
  }
  const uint64_t generation = ++_workspaceReloadGeneration;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(0.18 * NSEC_PER_SEC)),
                 dispatch_get_main_queue(), ^{
    if (generation != self->_workspaceReloadGeneration || !self->_workspace.opened) {
      return;
    }
    NSURL* folder = [NSURL fileURLWithPath:[NSString stringWithUTF8String:self->_workspace.folderPath.c_str()] isDirectory:YES];
    const std::string signature = WorkspaceSourceSignature(folder);
    if (signature.empty() || signature == self->_workspaceSourceSignature) {
      return;
    }
    [self reloadAcceptedWorkspaceFromDisk:@"Project files changed: accepted state reloaded and FinalFrameSurface refreshed."];
  });
}

- (void)applyWorkspaceFrameRate {
  if (!_workspace.opened || self.view == nil) {
    return;
  }
  const double maxPreviewFPS = 120.0;
  int fps = static_cast<int>(std::round(std::clamp(makelab::timeline::Fps(_workspace.frameRate), 1.0, maxPreviewFPS)));
  self.view.preferredFramesPerSecond = std::max(1, fps);
}

- (void)scheduleBackgroundVideoTextureWarmup {
  if (!_workspace.opened || _renderExecutor == nullptr || _renderQueue == nil || _videoTextureWarmInFlight) {
    return;
  }
  if (!_resourceScheduler.canRunBackgroundWarmup(_playbackScheduler.isPlaying(), _renderInFlight, _liveScopeReadbackInFlight)) {
    return;
  }
  _videoTextureWarmInFlight = YES;
  const makelab::imgui::WorkspaceViewState workspace = _workspace;
  const uint64_t sessionGeneration = _renderSessionGeneration;
  const uint64_t backgroundGeneration = _resourceScheduler.captureBackgroundGeneration();
  MacMetalRenderFrameExecutor* executor = _renderExecutor;
  AppDelegate* delegate = self;
  const int framesToWarm = _resourceScheduler.videoWarmupFrameBudget(workspace);
  const int activationFramesToWarm = _resourceScheduler.activationWarmupFrameBudget(workspace);
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, static_cast<int64_t>(0.18 * NSEC_PER_SEC)), _renderQueue, ^{
    @autoreleasepool {
      auto shouldContinue = [delegate, backgroundGeneration]() {
        return delegate->_resourceScheduler.acceptsBackground(backgroundGeneration) &&
               delegate->_resourceScheduler.canRunBackgroundWarmup(delegate->_playbackScheduler.isPlaying(),
                                                                   delegate->_renderInFlight,
                                                                   delegate->_liveScopeReadbackInFlight);
      };
      if (shouldContinue()) {
        executor->prewarmVideoTextures(workspace, framesToWarm, shouldContinue);
      }
      if (shouldContinue()) {
        executor->prewarmLayerActivationFrames(workspace, activationFramesToWarm, shouldContinue);
      }
      dispatch_async(dispatch_get_main_queue(), ^{
        if (sessionGeneration == delegate->_renderSessionGeneration &&
            delegate->_resourceScheduler.acceptsBackground(backgroundGeneration)) {
          delegate->_status += " | Realtime resource warmup ready.";
        }
        delegate->_videoTextureWarmInFlight = NO;
        [delegate.view setNeedsDisplay:YES];
      });
    }
  });
}

- (void)completeOpenProjectFolder:(NSURL*)folderURL {
  if (folderURL == nil) {
    return;
  }
  @try {
    [self drainRenderQueueBeforeProjectMutation];
    _workspace = LoadWorkspaceState(folderURL);
    _finalFrameSurface = nil;
    _liveScope.ready = false;
    _lastLiveScopeFrameIndex = -1;
    _liveScopeReadbackInFlight = NO;
    _lastLiveScopeRequestHostTime = -1.0;
    _lastRenderedFrameIndex = -1;
    self.designFixture = NO;
    self.playingDesignFixture = NO;
    _playbackScheduler.bindTimeline(_workspace.durationSeconds, _workspace.fps);
    _needsFinalFrameRender = YES;
    if (_renderExecutor != nullptr) {
      _renderExecutor->invalidateProjectResources();
      _renderExecutor->prewarmStaticImageTextures(_workspace);
      _renderExecutor->prewarmGeneratedVisualTextures(_workspace);
    }
    [self applyWorkspaceFrameRate];
    [self renderAcceptedFrame];
    if (_finalFrameSurface) {
      _status = "Workspace opened: " + _workspace.folderName + " | FinalFrameSurface ready at frame 0.";
    } else {
      _status = "Workspace opened: " + _workspace.folderName + " | RequestPreviewFrame(0) blocked.";
    }
    if (_renderExecutor != nullptr && !_renderExecutor->diagnostic().empty()) {
      _status += " | " + _renderExecutor->diagnostic();
    }
    for (const std::string& diagnostic : _workspace.diagnostics) {
      _status += " | " + diagnostic;
    }
	    [self startWorkspaceWatcher:folderURL];
	    [self scheduleBackgroundVideoTextureWarmup];
	    self.view.paused = YES;
	    [self.view setNeedsDisplay:YES];
  } @catch (NSException* exception) {
    _workspace = {};
    _status = "Open Folder failed: " + ToStdString(exception.reason ?: @"unknown error");
  }
}

- (NSURL*)defaultOpenProjectDirectoryURL {
  if (_workspace.opened && !_workspace.folderPath.empty()) {
    return [NSURL fileURLWithPath:[NSString stringWithUTF8String:_workspace.folderPath.c_str()] isDirectory:YES];
  }
  NSArray<NSURL*>* documentURLs =
      [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
  return documentURLs.firstObject ?: [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
}

- (void)openProjectFolder {
  if (_openProjectPanelInFlight) {
    _status = "Open Folder already waiting for native folder picker.";
    [self.view setNeedsDisplay:YES];
    return;
  }

  _openProjectPanelInFlight = YES;
  _status = "Opening native folder picker...";
  [self.view setNeedsDisplay:YES];

  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.canCreateDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.resolvesAliases = YES;
  panel.directoryURL = [self defaultOpenProjectDirectoryURL];
  panel.prompt = @"Open Folder";
  panel.message = @"Choose an existing MakeLab project folder or create a new empty folder.";

  __weak AppDelegate* weakSelf = self;
  void (^completion)(NSModalResponse) = ^(NSModalResponse response) {
    AppDelegate* strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    strongSelf->_openProjectPanelInFlight = NO;
    if (response != NSModalResponseOK || panel.URL == nil) {
      strongSelf->_status = "Open Folder cancelled.";
      [strongSelf.view setNeedsDisplay:YES];
      return;
    }
    [strongSelf completeOpenProjectFolder:panel.URL];
  };

  if (self.window != nil) {
    [panel beginSheetModalForWindow:self.window completionHandler:completion];
  } else {
    [panel beginWithCompletionHandler:completion];
  }
}

- (void)reloadAcceptedWorkspaceAfterAuthoring:(const makelab::authoring::AuthoringResult&)result {
  if (!_workspace.opened || _workspace.folderPath.empty()) {
    _status = "Authoring command blocked: Open Folder first.";
    return;
  }
  if (!result.accepted) {
    _status = result.message;
    for (const std::string& diagnostic : result.diagnostics) {
      _status += " | " + diagnostic;
    }
    [self.view setNeedsDisplay:YES];
    return;
  }
  [self reloadAcceptedWorkspaceFromDisk:[NSString stringWithUTF8String:result.message.c_str()]];
}

- (makelab::authoring::ImportedAssetMetadata)metadataForImportedURL:(NSURL*)url requestedType:(NSString*)requestedType {
  makelab::authoring::ImportedAssetMetadata metadata;
  const std::string extension = ToStdString(url.pathExtension.lowercaseString);
  const bool audioRequested = [requestedType isEqualToString:@"audio"];
  static const std::unordered_map<std::string, std::string> mediaTypes{
      {"mp4", "video"}, {"mov", "video"}, {"m4v", "video"}, {"webm", "video"},
      {"png", "image"}, {"jpg", "image"}, {"jpeg", "image"}, {"heic", "image"}, {"tif", "image"}, {"tiff", "image"}, {"svg", "image"},
      {"wav", "audio"}, {"mp3", "audio"}, {"m4a", "audio"}, {"aac", "audio"}, {"aiff", "audio"}, {"flac", "audio"},
  };
  const auto type = mediaTypes.find(extension);
  metadata.type = audioRequested ? "audio" : (type == mediaTypes.end() ? "" : type->second);
  if (metadata.type == "image") {
    if (extension == "svg") {
      std::unique_ptr<lunasvg::Document> document = lunasvg::Document::loadFromFile(ToStdString(url.path));
      if (document) {
        metadata.width = static_cast<int>(std::round(document->width()));
        metadata.height = static_cast<int>(std::round(document->height()));
      }
    } else {
      NSImage* image = [[NSImage alloc] initWithContentsOfURL:url];
      if (image != nil) {
        metadata.width = static_cast<int>(std::round(image.size.width));
        metadata.height = static_cast<int>(std::round(image.size.height));
      }
    }
    return metadata;
  }
  if (metadata.type == "video" || metadata.type == "audio") {
    AVURLAsset* asset = [AVURLAsset URLAssetWithURL:url options:nil];
    metadata.durationSeconds = CMTimeGetSeconds(asset.duration);
    if (metadata.type == "video") {
      AVAssetTrack* track = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
      if (track != nil) {
        const CGSize size = CGSizeApplyAffineTransform(track.naturalSize, track.preferredTransform);
        metadata.width = static_cast<int>(std::round(std::abs(size.width)));
        metadata.height = static_cast<int>(std::round(std::abs(size.height)));
        metadata.fps = track.nominalFrameRate;
      }
    }
  }
  return metadata;
}

- (void)importAssetOfType:(NSString*)requestedType {
  if (!_workspace.opened) {
    _status = "ImportAsset blocked: Open Folder first.";
    [self.view setNeedsDisplay:YES];
    return;
  }
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = YES;
  panel.canChooseDirectories = NO;
  panel.allowsMultipleSelection = YES;
  panel.prompt = [requestedType isEqualToString:@"audio"] ? @"Import Audio" : @"Import Media";
  panel.message = @"Imported files are copied into assets/originals and accepted through UnitedGate.";
  NSArray<NSString*>* extensions = [requestedType isEqualToString:@"audio"]
                                        ? @[@"wav", @"mp3", @"m4a", @"aac", @"aiff", @"flac"]
                                        : @[@"mp4", @"mov", @"m4v", @"webm", @"png", @"jpg", @"jpeg", @"heic", @"tif", @"tiff", @"svg"];
  NSMutableArray<UTType*>* contentTypes = [NSMutableArray arrayWithCapacity:extensions.count];
  for (NSString* extension in extensions) {
    UTType* type = [UTType typeWithFilenameExtension:extension];
    if (type != nil) {
      [contentTypes addObject:type];
    }
  }
  panel.allowedContentTypes = contentTypes;
  if ([panel runModal] != NSModalResponseOK) {
    return;
  }
  makelab::authoring::AuthoringResult lastResult;
  for (NSURL* url in panel.URLs) {
    const auto metadata = [self metadataForImportedURL:url requestedType:requestedType];
    lastResult = _authoringService.importAsset(_workspace.folderPath, ToStdString(url.path), metadata);
    if (!lastResult.accepted) {
      break;
    }
  }
  [self reloadAcceptedWorkspaceAfterAuthoring:lastResult];
}

- (NSURL*)defaultExportDirectoryURL {
  if (_workspace.opened && !_workspace.folderPath.empty()) {
    NSURL* workspaceURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:_workspace.folderPath.c_str()] isDirectory:YES];
    NSURL* rendersURL = [workspaceURL URLByAppendingPathComponent:@"renders" isDirectory:YES];
    EnsureDirectory(rendersURL);
    return rendersURL;
  }
  NSArray<NSURL*>* documentURLs =
      [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask];
  return documentURLs.firstObject ?: [NSURL fileURLWithPath:NSHomeDirectory() isDirectory:YES];
}

- (NativeExportOptions)exportOptionsForQualityIndex:(NSInteger)index {
  NativeExportOptions options;
  const int pixels = std::max(1, _workspace.width * _workspace.height);
  switch (index) {
    case 0:
      options.qualityLabel = "Master";
      options.averageBitRate = std::max(8000000, pixels * 5);
      break;
    case 1:
      options.qualityLabel = "High";
      options.averageBitRate = std::max(5000000, pixels * 4);
      break;
    case 2:
      options.qualityLabel = "Review";
      options.averageBitRate = std::max(3000000, pixels * 2);
      break;
    default:
      options.qualityLabel = "Master";
      options.averageBitRate = std::max(8000000, pixels * 5);
      break;
  }
  return options;
}

- (NSURL*)normalizedMp4ExportURL:(NSURL*)url {
  if (url == nil) {
    return nil;
  }
  const std::string extension = LowercaseAscii(ToStdString(url.pathExtension));
  if (extension == "mp4") {
    return url;
  }
  NSURL* withoutExtension = [url URLByDeletingPathExtension];
  return [withoutExtension URLByAppendingPathExtension:@"mp4"];
}

- (void)revealCompletedExportIfPresent:(NSURL*)outputURL result:(NativeExportResult&)result {
  if (!result.ok || outputURL == nil) {
    return;
  }
  NSError* attributesError = nil;
  NSDictionary<NSFileAttributeKey, id>* attributes =
      [[NSFileManager defaultManager] attributesOfItemAtPath:outputURL.path error:&attributesError];
  const unsigned long long fileSize = [attributes[NSFileSize] unsignedLongLongValue];
  if (attributes == nil || fileSize == 0) {
    result.ok = false;
    result.message = "Export rejected after completion: MP4 was not found at selected save path.";
    if (attributesError != nil && attributesError.localizedDescription != nil) {
      result.message += " ";
      result.message += ToStdString(attributesError.localizedDescription);
    }
    result.message += " path=" + ToStdString(outputURL.path);
    return;
  }
  result.path = ToStdString(outputURL.path);
  result.message += " | verifiedOutputBytes=" + std::to_string(fileSize);
  [[NSWorkspace sharedWorkspace] activateFileViewerSelectingURLs:@[ outputURL ]];
}

- (void)beginFinalFrameExportToURL:(NSURL*)requestedOutputURL options:(NativeExportOptions)options {
  NSURL* outputURL = [self normalizedMp4ExportURL:requestedOutputURL];
  if (!_workspace.opened || _renderExecutor == nullptr) {
    _status = "Open Folder before Export.";
    [self.view setNeedsDisplay:YES];
    return;
  }
  if (_exportInFlight || !_resourceScheduler.beginExportMode()) {
    _status = "Export blocked: NativeRealtimeResourceScheduler is already running an exclusive export.";
    [self.view setNeedsDisplay:YES];
    return;
  }

  if (_playbackScheduler.isPlaying()) {
    _playbackScheduler.togglePlayback();
    if (_audioPreviewEngine != nullptr) {
      _audioPreviewEngine->stop();
    }
    self.view.paused = YES;
  }

  [self drainRenderQueueBeforeProjectMutation];
  EnsureDirectory(outputURL.URLByDeletingLastPathComponent);
  const BOOL securityAccess = [outputURL startAccessingSecurityScopedResource];
  _exportInFlight = YES;
  _exportProgress = 0.0;
  _exportDestination = ToStdString(outputURL.path);
  _exportPhase = "ExportMode: reserved exclusive FinalFrameSurface path.";
  _status = "Export started: choose path accepted; exclusive NativeRealtimeResourceScheduler ExportMode is active.";
  [self.view setNeedsDisplay:YES];

  const makelab::imgui::WorkspaceViewState workspace = _workspace;
  MacMetalRenderFrameExecutor* executor = _renderExecutor;
  AppDelegate* delegate = self;
  dispatch_async(_renderQueue, ^{
    @autoreleasepool {
      NativeExportProgressCallback progress = [delegate](double value, const std::string& phase) {
        dispatch_async(dispatch_get_main_queue(), ^{
          delegate->_exportProgress = std::clamp(value, 0.0, 1.0);
          delegate->_exportPhase = phase;
          std::ostringstream status;
          status << "Export " << static_cast<int>(std::round(delegate->_exportProgress * 100.0))
                 << "%: " << phase;
          delegate->_status = status.str();
          [delegate.view setNeedsDisplay:YES];
        });
      };
      NativeExportResult exportResult =
          NativeFinalFrameSurfaceExporter::ExportMp4(workspace, *executor, outputURL, options, progress);
      dispatch_async(dispatch_get_main_queue(), ^{
        NativeExportResult finalResult = exportResult;
        [delegate revealCompletedExportIfPresent:outputURL result:finalResult];
        delegate->_status = finalResult.message;
        if (securityAccess) {
          [outputURL stopAccessingSecurityScopedResource];
        }
        delegate->_resourceScheduler.endExportMode();
        delegate->_exportInFlight = NO;
        delegate->_exportProgress = finalResult.ok ? 1.0 : 0.0;
        delegate->_exportPhase = finalResult.ok ? "Export complete." : "Export failed.";
        if (finalResult.ok) {
          delegate->_needsFinalFrameRender = YES;
          [delegate renderAcceptedFrame];
        }
        [delegate.view setNeedsDisplay:YES];
      });
    }
  });
}

- (void)openExportPanel {
  if (!_workspace.opened || _renderExecutor == nullptr) {
    _status = "Open Folder before Export.";
    [self.view setNeedsDisplay:YES];
    return;
  }
  if (_exportPanelInFlight || _exportInFlight) {
    _status = _exportInFlight ? "Export is already running." : "Export settings are already open.";
    [self.view setNeedsDisplay:YES];
    return;
  }

  _exportPanelInFlight = YES;
  _status = "Opening native Export settings...";
  [self.view setNeedsDisplay:YES];

  NSSavePanel* panel = [NSSavePanel savePanel];
  panel.canCreateDirectories = YES;
  panel.directoryURL = [self defaultExportDirectoryURL];
  panel.nameFieldStringValue = [NSString stringWithFormat:@"%@.mp4", MakeId(@"final_frame_surface_export")];
  panel.prompt = @"Export";
  panel.message = @"Export uses Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph -> FinalFrameSurface.";
  if (@available(macOS 11.0, *)) {
    panel.allowedContentTypes = @[ UTTypeMPEG4Movie ];
  } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    panel.allowedFileTypes = @[ @"mp4" ];
#pragma clang diagnostic pop
  }

  NSView* accessory = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 450, 78)];
  NSTextField* qualityLabel = [NSTextField labelWithString:@"Quality"];
  qualityLabel.frame = NSMakeRect(0, 48, 82, 22);
  NSPopUpButton* qualityPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(92, 44, 230, 28) pullsDown:NO];
  [qualityPopup addItemWithTitle:@"Master - hardware H.264"];
  [qualityPopup addItemWithTitle:@"High - hardware H.264"];
  [qualityPopup addItemWithTitle:@"Review - hardware H.264"];
  [qualityPopup selectItemAtIndex:0];

  NSTextField* resolutionLabel = [NSTextField labelWithString:@"Resolution"];
  resolutionLabel.frame = NSMakeRect(0, 12, 82, 22);
  NSPopUpButton* resolutionPopup = [[NSPopUpButton alloc] initWithFrame:NSMakeRect(92, 8, 230, 28) pullsDown:NO];
  [resolutionPopup addItemWithTitle:[NSString stringWithFormat:@"Composition %dx%d", _workspace.width, _workspace.height]];
  resolutionPopup.enabled = NO;
  NSTextField* truthLabel = [NSTextField labelWithString:@"FinalFrameSurface truth"];
  truthLabel.frame = NSMakeRect(330, 12, 120, 22);
  truthLabel.textColor = NSColor.secondaryLabelColor;
  truthLabel.font = [NSFont systemFontOfSize:10.0 weight:NSFontWeightRegular];

  [accessory addSubview:qualityLabel];
  [accessory addSubview:qualityPopup];
  [accessory addSubview:resolutionLabel];
  [accessory addSubview:resolutionPopup];
  [accessory addSubview:truthLabel];
  panel.accessoryView = accessory;

  __weak AppDelegate* weakSelf = self;
  void (^completion)(NSModalResponse) = ^(NSModalResponse response) {
    AppDelegate* strongSelf = weakSelf;
    if (strongSelf == nil) {
      return;
    }
    strongSelf->_exportPanelInFlight = NO;
    if (response != NSModalResponseOK || panel.URL == nil) {
      strongSelf->_status = "Export cancelled.";
      [strongSelf.view setNeedsDisplay:YES];
      return;
    }
    NativeExportOptions options = [strongSelf exportOptionsForQualityIndex:qualityPopup.indexOfSelectedItem];
    [strongSelf beginFinalFrameExportToURL:panel.URL options:options];
  };

  if (self.window != nil) {
    [panel beginSheetModalForWindow:self.window completionHandler:completion];
  } else {
    [panel beginWithCompletionHandler:completion];
  }
}

- (void)handleEditorCommand:(NSString*)command
                    payload:(NSString*)payload
         timelineFrameIndex:(int64_t)timelineFrameIndex {
  if ([command isEqualToString:@"OpenProject"]) {
    [self openProjectFolder];
    return;
  }
  if ([command isEqualToString:@"SelectLibrarySection"]) {
    const std::string section = ToStdString(payload);
    if (section == "media") _librarySection = makelab::imgui::LibrarySection::Media;
    if (section == "text") _librarySection = makelab::imgui::LibrarySection::Text;
    if (section == "audio") _librarySection = makelab::imgui::LibrarySection::Audio;
    if (section == "background") _librarySection = makelab::imgui::LibrarySection::Background;
    if (section == "shapes") _librarySection = makelab::imgui::LibrarySection::Shapes;
    [self.view setNeedsDisplay:YES];
    return;
  }
  if ([command isEqualToString:@"ImportMedia"]) {
    [self importAssetOfType:@"media"];
    return;
  }
  if ([command isEqualToString:@"ImportAudio"]) {
    [self importAssetOfType:@"audio"];
    return;
  }
  if (!_workspace.opened &&
      ([command isEqualToString:@"AddAssetClip"] || [command isEqualToString:@"AddTextLayer"] ||
       [command isEqualToString:@"AddBackgroundLayer"] || [command isEqualToString:@"AddShapeLayer"])) {
    _status = "Authoring command blocked: Open Folder first.";
    [self.view setNeedsDisplay:YES];
    return;
  }
  if ([command isEqualToString:@"AddAssetClip"]) {
    const auto result = _authoringService.addAssetClip(_workspace.folderPath, ToStdString(payload), _playbackScheduler.acceptedFrame());
    [self reloadAcceptedWorkspaceAfterAuthoring:result];
    return;
  }
  if ([command isEqualToString:@"AddTextLayer"]) {
    const auto result = _authoringService.addTextLayer(_workspace.folderPath, ToStdString(payload), _playbackScheduler.acceptedFrame());
    [self reloadAcceptedWorkspaceAfterAuthoring:result];
    return;
  }
  if ([command isEqualToString:@"AddBackgroundLayer"]) {
    const auto result = _authoringService.addBackgroundLayer(_workspace.folderPath, ToStdString(payload), _playbackScheduler.acceptedFrame());
    [self reloadAcceptedWorkspaceAfterAuthoring:result];
    return;
  }
  if ([command isEqualToString:@"AddShapeLayer"]) {
    const auto result = _authoringService.addShapeLayer(_workspace.folderPath, ToStdString(payload), _playbackScheduler.acceptedFrame());
    [self reloadAcceptedWorkspaceAfterAuthoring:result];
    return;
  }
  if ([command isEqualToString:@"ScrubTimeline"]) {
    if (!_workspace.opened) {
      _status = "Open Folder before live scrub.";
      return;
    }
    _playbackScheduler.scrubToFrame(timelineFrameIndex);
    if (_audioPreviewEngine != nullptr) {
      _audioPreviewEngine->stop();
    }
    _needsFinalFrameRender = YES;
    [self scheduleFinalFrameRenderWithScrubPrewarm:YES];
    _status = "Live scrub queued: native scheduler requested frame " + std::to_string(timelineFrameIndex) + ".";
    self.view.paused = YES;
    [self.view setNeedsDisplay:YES];
    return;
  }
  if ([command isEqualToString:@"BeginPlayback"]) {
    if (self.designFixture) {
      self.playingDesignFixture = !self.playingDesignFixture;
      self.startTime = CACurrentMediaTime();
      _status = self.playingDesignFixture ? "Design fixture playback started for UI parity only." : "Design fixture playback paused.";
      self.view.paused = !self.playingDesignFixture;
      [self.view setNeedsDisplay:YES];
      return;
    }
    if (!_workspace.opened) {
      _status = "Open Folder before playback.";
      return;
    }
    if (!_finalFrameSurface) {
      _playbackScheduler.reset();
      _needsFinalFrameRender = YES;
      [self scheduleFinalFrameRenderWithScrubPrewarm:NO];
      _status = "Playback queued: waiting for first accepted FinalFrameSurface.";
      if (_renderExecutor != nullptr && !_renderExecutor->diagnostic().empty()) {
        _status += " " + _renderExecutor->diagnostic();
      }
      return;
    }
    _playbackScheduler.togglePlayback();
    if (_audioPreviewEngine != nullptr) {
      if (_playbackScheduler.isPlaying()) {
        _audioPreviewEngine->play(_workspace, _playbackScheduler.acceptedFrame());
      } else {
        _audioPreviewEngine->stop();
      }
    }
    _needsFinalFrameRender = YES;
    self.view.paused = !_playbackScheduler.isPlaying();
    [self.view setNeedsDisplay:YES];
    _status = _playbackScheduler.isPlaying()
                  ? "Playback started: native scheduler driving FinalFrameSurface."
                  : "Playback paused: FinalFrameSurface retained at current timeline time.";
    if (_audioPreviewEngine != nullptr && !_audioPreviewEngine->diagnostic().empty()) {
      _status += " " + _audioPreviewEngine->diagnostic();
    }
    return;
  }
  if ([command isEqualToString:@"RequestRender"]) {
    [self reloadAcceptedWorkspaceFromDisk:@"Render refreshed accepted project files and requested a new FinalFrameSurface."];
    return;
  }
  if ([command isEqualToString:@"RequestExport"]) {
    [self openExportPanel];
    return;
  }
}

- (void)drawInMTKView:(MTKView*)view {
  @autoreleasepool {
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor* renderPassDescriptor = view.currentRenderPassDescriptor;
    if (drawable == nil || renderPassDescriptor == nil) {
      return;
    }

    ImGui_ImplMetal_NewFrame(renderPassDescriptor);
    ImGui_ImplOSX_NewFrame(view);
    ImGui::NewFrame();

    if (_workspace.opened) {
      const bool playing = _playbackScheduler.isPlaying();
      const int64_t requestedFrame = (playing && _renderInFlight)
                                         ? _playbackScheduler.requestedFrame()
                                         : _playbackScheduler.requestFrameForNow();
      const bool frameChanged = requestedFrame != _lastRenderedFrameIndex;
      const bool sizeChanged = _workspace.width != _lastRenderedWidth || _workspace.height != _lastRenderedHeight;
      const bool shouldRenderFinalFrame = _needsFinalFrameRender ||
                                          _finalFrameSurface == nil ||
                                          playing ||
                                          frameChanged ||
                                          sizeChanged;
      if (shouldRenderFinalFrame) {
        [self scheduleFinalFrameRenderWithScrubPrewarm:NO];
      }
      if (_finalFrameSurface) {
        std::string diagnostic = _renderExecutor != nullptr ? _renderExecutor->diagnostic() : "";
        if (diagnostic.rfind("MacMetalRenderFrameExecutor preserved", 0) == 0) {
          _status = diagnostic;
        } else {
          _status = diagnostic.empty()
                        ? "FinalFrameSurface ready: MacMetalRenderFrameExecutor."
                        : "FinalFrameSurface ready: MacMetalRenderFrameExecutor. " + diagnostic;
        }
      } else if (_renderExecutor != nullptr && !_renderExecutor->diagnostic().empty()) {
        _status = _renderExecutor->diagnostic();
      }
    }

    makelab::imgui::EditorShellConfig config;
    config.designFixture = self.designFixture;
    config.finalFrameSurfaceReady = _finalFrameSurface != nil;
    config.finalFrameSurfaceTexture = (__bridge void*)_finalFrameSurface;
    config.iconFont = _iconFont;
    config.finalFrameSurfaceWidth = _workspace.opened ? _workspace.width : 0;
    config.finalFrameSurfaceHeight = _workspace.opened ? _workspace.height : 0;
    config.requestedFrameIndex = _workspace.opened ? _playbackScheduler.requestedFrame() : 0;
    config.acceptedFrameIndex = _workspace.opened ? _playbackScheduler.acceptedFrame() : 0;
    config.durationFrames = _workspace.opened ? _playbackScheduler.durationFrames() : 0;
    config.frameRate = _workspace.opened ? _playbackScheduler.frameRate() : makelab::timeline::FrameRateFromFps(30.0);
    config.librarySection = _librarySection;
    config.playbackTimeSeconds = _workspace.opened
                                     ? _playbackScheduler.timeSeconds()
                                     : ((self.designFixture && self.playingDesignFixture) ? fmod(CACurrentMediaTime() - self.startTime, 13.87) : 0.0);
    config.durationSeconds = _workspace.opened ? _workspace.durationSeconds : (self.designFixture ? 13.87 : 0.0);
    config.liveScope = _liveScope;
    config.telemetry.ready = _workspace.opened;
    config.telemetry.renderSubmitMs = _lastRenderSubmitMs;
    config.telemetry.liveScopeReadbackMs = _lastLiveScopeReadbackMs;
    config.telemetry.frameBudgetMs = _workspace.opened ? (1000.0 / std::max(1.0, _workspace.fps)) : 0.0;
    config.telemetry.finalSurfaceMegabytes = _finalFrameSurface == nil
                                                 ? 0.0
                                                 : (static_cast<double>(_finalFrameSurface.width) *
                                                    static_cast<double>(_finalFrameSurface.height) * 4.0 / 1048576.0);
    config.telemetry.requestedFrameIndex = _workspace.opened ? _playbackScheduler.requestedFrame() : 0;
    config.telemetry.acceptedFrameIndex = _workspace.opened ? _playbackScheduler.acceptedFrame() : 0;
    config.telemetry.requestGeneration = _workspace.opened ? _playbackScheduler.requestGeneration() : 0;
    config.exportProgress.inFlight = _exportInFlight;
    config.exportProgress.progress = _exportProgress;
    config.exportProgress.phase = _exportPhase.c_str();
    config.exportProgress.destination = _exportDestination.c_str();
    config.diagnostic = _status.empty()
                            ? "Preview blocked: waiting for FinalFrameSurface from Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph."
                            : _status.c_str();
    config.workspace = &_workspace;
    makelab::imgui::EditorShellResult result = makelab::imgui::DrawEditorShell(config);
    if (!result.command.empty()) {
      NSString* command = [NSString stringWithUTF8String:result.command.c_str()];
      NSString* payload = [NSString stringWithUTF8String:result.payload.c_str()];
      int64_t timelineFrameIndex = result.timelineFrameIndex;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self handleEditorCommand:command payload:payload timelineFrameIndex:timelineFrameIndex];
      });
    }

    ImGui::Render();

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
    ImGui_ImplMetal_RenderDrawData(ImGui::GetDrawData(), commandBuffer, renderEncoder);
    [renderEncoder endEncoding];
    [commandBuffer presentDrawable:drawable];
    [commandBuffer commit];
  }
}

- (void)mtkView:(MTKView*)view drawableSizeWillChange:(CGSize)size {
  (void)view;
  (void)size;
}

@end

struct PixelParitySmokeResult {
  bool ok = false;
  int64_t frameIndex = -1;
  uint64_t previewHash = 0;
  uint64_t exportHash = 0;
  std::string message;
};

struct PerformanceSmokeResult {
  bool ok = false;
  int acceptedFrames = 0;
  double averageRenderMs = 0.0;
  double maxRenderMs = 0.0;
  double frameBudgetMs = 0.0;
  int64_t maxFrameIndex = -1;
  std::string message;
};

uint64_t HashBGRA8Pixels(const std::vector<uint8_t>& pixels) {
  uint64_t hash = 1469598103934665603ULL;
  for (uint8_t byte : pixels) {
    hash ^= byte;
    hash *= 1099511628211ULL;
  }
  return hash;
}

PixelParitySmokeResult RunPixelParitySmoke(NSString* workspacePath, int64_t requestedFrame) {
  PixelParitySmokeResult smoke;
  if (workspacePath.length == 0) {
    smoke.message = "Pixel parity smoke rejected: workspace path is required.";
    return smoke;
  }
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  id<MTLCommandQueue> commandQueue = [device newCommandQueue];
  if (device == nil || commandQueue == nil) {
    smoke.message = "Pixel parity smoke rejected: Metal device or command queue is unavailable.";
    return smoke;
  }

  NSURL* workspaceURL = [NSURL fileURLWithPath:workspacePath isDirectory:YES];
  makelab::imgui::WorkspaceViewState workspace = LoadWorkspaceState(workspaceURL);
  if (!workspace.opened) {
    smoke.message = "Pixel parity smoke rejected: UnitedGate did not accept the workspace.";
    for (const std::string& diagnostic : workspace.diagnostics) {
      smoke.message += " " + diagnostic;
    }
    return smoke;
  }

  MacMetalRenderFrameExecutor executor(device, commandQueue);
  executor.prewarmStaticImageTextures(workspace);
  executor.prewarmGeneratedVisualTextures(workspace);
  executor.prewarmVideoTextures(workspace);
  executor.prewarmLayerActivationFrames(workspace);
  const int64_t startFrame = requestedFrame >= 0
                                 ? makelab::timeline::ClampFrame(requestedFrame, workspace.durationFrames)
                                 : 0;
  const int64_t searchLimit = requestedFrame >= 0
                                  ? startFrame + 1
                                  : std::min<int64_t>(workspace.durationFrames, 180);
  for (int64_t frameIndex = startFrame; frameIndex < searchLimit; ++frameIndex) {
    @autoreleasepool {
      FinalFrameSurfaceResult preview = executor.render(workspace, frameIndex, 0xA000000000000000ULL + static_cast<uint64_t>(frameIndex), false, true);
      if (!preview.accepted()) {
        continue;
      }
      size_t previewBytesPerRow = 0;
      std::vector<uint8_t> previewPixels;
      if (!executor.copyTextureBGRA8(preview.texture, previewPixels, previewBytesPerRow)) {
        smoke.message = "Pixel parity smoke rejected: preview FinalFrameSurface readback failed. " + executor.diagnostic();
        return smoke;
      }

      FinalFrameSurfaceResult exportFrame = executor.render(workspace, frameIndex, 0xB000000000000000ULL + static_cast<uint64_t>(frameIndex), false, true);
      if (!exportFrame.accepted()) {
        smoke.message = "Pixel parity smoke rejected: export FinalFrameSurface frame was not accepted.";
        if (!exportFrame.diagnostic.empty()) {
          smoke.message += " " + exportFrame.diagnostic;
        }
        return smoke;
      }
      size_t exportBytesPerRow = 0;
      std::vector<uint8_t> exportPixels;
      if (!executor.copyTextureBGRA8(exportFrame.texture, exportPixels, exportBytesPerRow)) {
        smoke.message = "Pixel parity smoke rejected: export FinalFrameSurface readback failed. " + executor.diagnostic();
        return smoke;
      }
      if (previewBytesPerRow != exportBytesPerRow || previewPixels.size() != exportPixels.size()) {
        smoke.message = "Pixel parity smoke rejected: preview/export FinalFrameSurface readback dimensions differ.";
        return smoke;
      }
      smoke.previewHash = HashBGRA8Pixels(previewPixels);
      smoke.exportHash = HashBGRA8Pixels(exportPixels);
      smoke.frameIndex = frameIndex;
      smoke.ok = smoke.previewHash == smoke.exportHash;
      smoke.message = smoke.ok
                          ? "Pixel parity smoke passed: preview/export FinalFrameSurface pixels match."
                          : "Pixel parity smoke rejected: preview/export FinalFrameSurface pixel hashes differ.";
      return smoke;
    }
  }

  smoke.message = "Pixel parity smoke rejected: no accepted FinalFrameSurface frame was found in the searched range.";
  return smoke;
}

PerformanceSmokeResult RunPerformanceSmoke(NSString* workspacePath, int requestedFrames, int64_t requestedStartFrame = 0) {
  PerformanceSmokeResult smoke;
  if (workspacePath.length == 0) {
    smoke.message = "Performance smoke rejected: workspace path is required.";
    return smoke;
  }
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  id<MTLCommandQueue> commandQueue = [device newCommandQueue];
  if (device == nil || commandQueue == nil) {
    smoke.message = "Performance smoke rejected: Metal device or command queue is unavailable.";
    return smoke;
  }

  NSURL* workspaceURL = [NSURL fileURLWithPath:workspacePath isDirectory:YES];
  makelab::imgui::WorkspaceViewState workspace = LoadWorkspaceState(workspaceURL);
  if (!workspace.opened) {
    smoke.message = "Performance smoke rejected: UnitedGate did not accept the workspace.";
    for (const std::string& diagnostic : workspace.diagnostics) {
      smoke.message += " " + diagnostic;
    }
    return smoke;
  }

  const int64_t durationFrames = std::max<int64_t>(1, workspace.durationFrames);
  const int64_t startFrame = makelab::timeline::ClampFrame(requestedStartFrame, durationFrames);
  const int64_t availableFrames = std::max<int64_t>(1, durationFrames - startFrame);
  const int frameCount = std::max(1, std::min<int>(requestedFrames, static_cast<int>(std::min<int64_t>(availableFrames, 240))));
  const double fps = std::max(1.0, workspace.fps);
  smoke.frameBudgetMs = 1000.0 / fps;

  MacMetalRenderFrameExecutor executor(device, commandQueue);
  executor.prewarmStaticImageTextures(workspace);
  executor.prewarmGeneratedVisualTextures(workspace);
  executor.prewarmVideoTextures(workspace);
  executor.prewarmLayerActivationFrames(workspace);
  double totalRenderMs = 0.0;
  for (int sample = 0; sample < frameCount; ++sample) {
    @autoreleasepool {
      const int64_t frameIndex = makelab::timeline::ClampFrame(startFrame + static_cast<int64_t>(sample), durationFrames);
      const double start = CACurrentMediaTime();
      FinalFrameSurfaceResult frame = executor.render(workspace,
                                                      frameIndex,
                                                      0xC000000000000000ULL + static_cast<uint64_t>(sample),
                                                      false,
                                                      true);
      const double elapsedMs = (CACurrentMediaTime() - start) * 1000.0;
      if (!frame.accepted()) {
        smoke.message = "Performance smoke rejected: FinalFrameSurface frame was not accepted.";
        if (!frame.diagnostic.empty()) {
          smoke.message += " " + frame.diagnostic;
        }
        return smoke;
      }
      totalRenderMs += elapsedMs;
      if (elapsedMs > smoke.maxRenderMs) {
        smoke.maxRenderMs = elapsedMs;
        smoke.maxFrameIndex = frameIndex;
      }
      ++smoke.acceptedFrames;
    }
  }

  smoke.averageRenderMs = smoke.acceptedFrames > 0 ? totalRenderMs / static_cast<double>(smoke.acceptedFrames) : 0.0;
  const double averageLimitMs = smoke.frameBudgetMs * 2.0;
  const double maxLimitMs = smoke.frameBudgetMs * 8.0;
  smoke.ok = smoke.acceptedFrames == frameCount &&
             smoke.averageRenderMs <= averageLimitMs &&
             smoke.maxRenderMs <= maxLimitMs;
  smoke.message = smoke.ok
                      ? "Performance smoke passed: FinalFrameSurface render timing is inside native budget guard."
                      : "Performance smoke rejected: FinalFrameSurface render timing exceeded native budget guard.";
  return smoke;
}

PerformanceSmokeResult RunScrubPerformanceSmoke(NSString* workspacePath, int requestedFrames) {
  PerformanceSmokeResult smoke;
  if (workspacePath.length == 0) {
    smoke.message = "Scrub performance smoke rejected: workspace path is required.";
    return smoke;
  }
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  id<MTLCommandQueue> commandQueue = [device newCommandQueue];
  if (device == nil || commandQueue == nil) {
    smoke.message = "Scrub performance smoke rejected: Metal device or command queue is unavailable.";
    return smoke;
  }

  NSURL* workspaceURL = [NSURL fileURLWithPath:workspacePath isDirectory:YES];
  makelab::imgui::WorkspaceViewState workspace = LoadWorkspaceState(workspaceURL);
  if (!workspace.opened) {
    smoke.message = "Scrub performance smoke rejected: UnitedGate did not accept the workspace.";
    for (const std::string& diagnostic : workspace.diagnostics) {
      smoke.message += " " + diagnostic;
    }
    return smoke;
  }

  const int64_t durationFrames = std::max<int64_t>(1, workspace.durationFrames);
  const int frameCount = std::max(2, std::min<int>(requestedFrames, static_cast<int>(std::min<int64_t>(durationFrames, 120))));
  const double fps = std::max(1.0, workspace.fps);
  smoke.frameBudgetMs = 1000.0 / fps;

  MacMetalRenderFrameExecutor executor(device, commandQueue);
  executor.prewarmStaticImageTextures(workspace);
  executor.prewarmGeneratedVisualTextures(workspace);
  executor.prewarmVideoTextures(workspace);
  executor.prewarmLayerActivationFrames(workspace);

  std::vector<int64_t> scrubFrames;
  scrubFrames.reserve(static_cast<size_t>(frameCount) * 2);
  const int64_t startFrame = durationFrames > 1 ? durationFrames / 4 : 0;
  const int64_t endFrame = durationFrames > 1 ? (durationFrames * 3) / 4 : 0;
  for (int sample = 0; sample < frameCount; ++sample) {
    const double t = frameCount == 1 ? 0.0 : static_cast<double>(sample) / static_cast<double>(frameCount - 1);
    scrubFrames.push_back(makelab::timeline::ClampFrame(
        static_cast<int64_t>(std::llround(static_cast<double>(startFrame) +
                                          static_cast<double>(endFrame - startFrame) * t)),
        durationFrames));
  }
  for (int sample = frameCount - 1; sample >= 0; --sample) {
    scrubFrames.push_back(scrubFrames[static_cast<size_t>(sample)]);
  }

  double totalRenderMs = 0.0;
  uint64_t generation = 0xD000000000000000ULL;
  for (int64_t frameIndex : scrubFrames) {
    @autoreleasepool {
      const double start = CACurrentMediaTime();
      FinalFrameSurfaceResult frame = executor.render(workspace,
                                                      frameIndex,
                                                      generation++,
                                                      true,
                                                      true,
                                                      nil,
                                                      NativeRenderIntent::ScrubInteractive);
      const double elapsedMs = (CACurrentMediaTime() - start) * 1000.0;
      if (!frame.accepted()) {
        smoke.message = "Scrub performance smoke rejected: FinalFrameSurface frame was not accepted.";
        if (!frame.diagnostic.empty()) {
          smoke.message += " " + frame.diagnostic;
        }
        return smoke;
      }
      totalRenderMs += elapsedMs;
      if (elapsedMs > smoke.maxRenderMs) {
        smoke.maxRenderMs = elapsedMs;
        smoke.maxFrameIndex = frameIndex;
      }
      ++smoke.acceptedFrames;
    }
  }

  smoke.averageRenderMs = smoke.acceptedFrames > 0 ? totalRenderMs / static_cast<double>(smoke.acceptedFrames) : 0.0;
  const double averageLimitMs = smoke.frameBudgetMs * 2.5;
  const double maxLimitMs = smoke.frameBudgetMs * 8.0;
  smoke.ok = smoke.acceptedFrames == static_cast<int>(scrubFrames.size()) &&
             smoke.averageRenderMs <= averageLimitMs &&
             smoke.maxRenderMs <= maxLimitMs;
  smoke.message = smoke.ok
                      ? "Scrub performance smoke passed: forward/reverse FinalFrameSurface scrub timing is inside native budget guard."
                      : "Scrub performance smoke rejected: forward/reverse FinalFrameSurface scrub timing exceeded native budget guard.";
  return smoke;
}

struct ExportSmokeResult {
  bool ok = false;
  std::string message;
  std::string outputPath;
  int audioTrackCount = 0;
};

ExportSmokeResult RunExportSmoke(NSString* workspacePath, NSString* outputPath) {
  ExportSmokeResult smoke;
  NSURL* workspaceURL = [NSURL fileURLWithPath:workspacePath isDirectory:YES];
  makelab::imgui::WorkspaceViewState workspace = LoadWorkspaceState(workspaceURL);
  id<MTLDevice> device = MTLCreateSystemDefaultDevice();
  id<MTLCommandQueue> commandQueue = [device newCommandQueue];
  if (device == nil || commandQueue == nil) {
    smoke.message = "Export smoke rejected: Metal device or command queue is unavailable.";
    return smoke;
  }
  MacMetalRenderFrameExecutor executor(device, commandQueue);
  NSURL* outputURL = [NSURL fileURLWithPath:outputPath];
  NativeExportResult exportResult = NativeFinalFrameSurfaceExporter::ExportMp4(workspace, executor, outputURL);
  smoke.outputPath = ToStdString(outputURL.path);
  if (!exportResult.ok) {
    smoke.message = exportResult.message;
    return smoke;
  }
  AVURLAsset* exportedAsset = [AVURLAsset URLAssetWithURL:outputURL options:nil];
  smoke.audioTrackCount = static_cast<int>([[exportedAsset tracksWithMediaType:AVMediaTypeAudio] count]);
  smoke.ok = smoke.audioTrackCount > 0;
  smoke.message = smoke.ok
                      ? "Export smoke passed: FinalFrameSurface MP4 contains accepted AudioGraph track(s)."
                      : "Export smoke rejected: exported MP4 has no audio tracks.";
  return smoke;
}

int main(int argc, char** argv) {
  @autoreleasepool {
    BOOL designFixture = NO;
    NSString* initialWorkspacePath = nil;
    NSString* pixelParityWorkspacePath = nil;
    NSString* performanceWorkspacePath = nil;
    NSString* scrubPerformanceWorkspacePath = nil;
    NSString* exportSmokeWorkspacePath = nil;
    NSString* exportSmokeOutputPath = nil;
    int64_t pixelParityFrame = -1;
    int64_t performanceStartFrame = 0;
    int performanceFrames = 30;
    for (int i = 1; i < argc; ++i) {
      if (std::string(argv[i]) == "--design-fixture") {
        designFixture = YES;
      } else if (std::string(argv[i]) == "--open-workspace" && i + 1 < argc) {
        initialWorkspacePath = [NSString stringWithUTF8String:argv[++i]];
      } else if (std::string(argv[i]) == "--pixel-parity-smoke" && i + 1 < argc) {
        pixelParityWorkspacePath = [NSString stringWithUTF8String:argv[++i]];
      } else if (std::string(argv[i]) == "--performance-smoke" && i + 1 < argc) {
        performanceWorkspacePath = [NSString stringWithUTF8String:argv[++i]];
      } else if (std::string(argv[i]) == "--scrub-performance-smoke" && i + 1 < argc) {
        scrubPerformanceWorkspacePath = [NSString stringWithUTF8String:argv[++i]];
      } else if (std::string(argv[i]) == "--export-smoke" && i + 1 < argc) {
        exportSmokeWorkspacePath = [NSString stringWithUTF8String:argv[++i]];
      } else if (std::string(argv[i]) == "--output" && i + 1 < argc) {
        exportSmokeOutputPath = [NSString stringWithUTF8String:argv[++i]];
      } else if (std::string(argv[i]) == "--frame" && i + 1 < argc) {
        pixelParityFrame = std::max<int64_t>(0, std::strtoll(argv[++i], nullptr, 10));
      } else if (std::string(argv[i]) == "--start-frame" && i + 1 < argc) {
        performanceStartFrame = std::max<int64_t>(0, std::strtoll(argv[++i], nullptr, 10));
      } else if (std::string(argv[i]) == "--frames" && i + 1 < argc) {
        performanceFrames = std::max(1, static_cast<int>(std::strtol(argv[++i], nullptr, 10)));
      }
    }

    if (pixelParityWorkspacePath.length > 0) {
      const PixelParitySmokeResult smoke = RunPixelParitySmoke(pixelParityWorkspacePath, pixelParityFrame);
      std::fprintf(stdout,
                   "%s frame=%lld previewHash=%llu exportHash=%llu\n",
                   smoke.message.c_str(),
                   static_cast<long long>(smoke.frameIndex),
                   static_cast<unsigned long long>(smoke.previewHash),
                   static_cast<unsigned long long>(smoke.exportHash));
      return smoke.ok ? 0 : 2;
    }

    if (performanceWorkspacePath.length > 0) {
      const PerformanceSmokeResult smoke = RunPerformanceSmoke(performanceWorkspacePath, performanceFrames, performanceStartFrame);
      std::fprintf(stdout,
                   "%s frames=%d avgMs=%.3f maxMs=%.3f maxFrame=%lld budgetMs=%.3f\n",
                   smoke.message.c_str(),
                   smoke.acceptedFrames,
                   smoke.averageRenderMs,
                   smoke.maxRenderMs,
                   static_cast<long long>(smoke.maxFrameIndex),
                   smoke.frameBudgetMs);
      return smoke.ok ? 0 : 3;
    }

    if (scrubPerformanceWorkspacePath.length > 0) {
      const PerformanceSmokeResult smoke = RunScrubPerformanceSmoke(scrubPerformanceWorkspacePath, performanceFrames);
      std::fprintf(stdout,
                   "%s frames=%d avgMs=%.3f maxMs=%.3f maxFrame=%lld budgetMs=%.3f\n",
                   smoke.message.c_str(),
                   smoke.acceptedFrames,
                   smoke.averageRenderMs,
                   smoke.maxRenderMs,
                   static_cast<long long>(smoke.maxFrameIndex),
                   smoke.frameBudgetMs);
      return smoke.ok ? 0 : 4;
    }

    if (exportSmokeWorkspacePath.length > 0) {
      NSString* outputPath = exportSmokeOutputPath.length > 0
                                 ? exportSmokeOutputPath
                                 : [NSTemporaryDirectory() stringByAppendingPathComponent:@"makelab-imgui-export-smoke.mp4"];
      const ExportSmokeResult smoke = RunExportSmoke(exportSmokeWorkspacePath, outputPath);
      std::fprintf(stdout,
                   "%s audioTracks=%d output=%s\n",
                   smoke.message.c_str(),
                   smoke.audioTrackCount,
                   smoke.outputPath.c_str());
      return smoke.ok ? 0 : 5;
    }

    NSApplication* app = [NSApplication sharedApplication];
    AppDelegate* delegate = [[AppDelegate alloc] initWithDesignFixture:designFixture initialWorkspacePath:initialWorkspacePath];
    app.delegate = delegate;
    [app setActivationPolicy:NSApplicationActivationPolicyRegular];
    [app activateIgnoringOtherApps:YES];
    [app run];
  }
  return 0;
}
