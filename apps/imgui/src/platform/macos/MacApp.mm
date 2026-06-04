#import <Cocoa/Cocoa.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreVideo/CoreVideo.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>

#include "imgui.h"
#include "imgui_impl_metal.h"
#include "imgui_impl_osx.h"
#include "ui/EditorShell.hpp"

#include <algorithm>
#include <array>
#include <cmath>
#include <cstdlib>
#include <deque>
#include <limits>
#include <memory>
#include <unordered_map>
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

struct MacPreviewUniforms {
  vector_float4 tint;
  vector_float4 cornerRadii;
  vector_float2 size;
  float opacity;
  float borderWidth;
  uint32_t mode;
  uint32_t shapeKind;
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

struct MacPreviewUniforms {
    float4 tint;
    float4 cornerRadii;
    float2 size;
    float opacity;
    float borderWidth;
    uint mode;
    uint shapeKind;
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
};

vertex VertexOut mac_preview_vertex(const device MacPreviewVertex *vertices [[buffer(0)]], uint vid [[vertex_id]]) {
    VertexOut out;
    out.position = float4(vertices[vid].position, 0.0, 1.0);
    out.uv = vertices[vid].uv;
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

fragment float4 mac_preview_texture_fragment(VertexOut in [[stage_in]],
                                             texture2d<float> texture [[texture(0)]],
                                             constant MacPreviewUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = texture.sample(s, in.uv) * u.tint;
    float coverage = mac_rounded_rect_alpha(in.uv, u.size, u.cornerRadii) * u.opacity;
    color.a *= coverage;
    color.rgb *= color.a;
    return color;
}

fragment float4 mac_preview_premultiplied_fragment(VertexOut in [[stage_in]],
                                                   texture2d<float> texture [[texture(0)]],
                                                   constant MacPreviewUniforms &u [[buffer(0)]]) {
    constexpr sampler s(address::clamp_to_edge, filter::linear);
    float4 color = texture.sample(s, in.uv) * u.tint;
    float coverage = mac_rounded_rect_alpha(in.uv, u.size, u.cornerRadii) * u.opacity;
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

  id<MTLTexture> texture(CVMetalTextureCacheRef textureCache) {
    const double target = std::max(0.0, requestedMediaTime_);
    const int requestedFrame = frameIndexForTime(target);
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
      return lastTexture_ ? CVMetalTextureGetTexture(lastTexture_) : nil;
    }
    if (lastTexture_ != nullptr && std::abs(currentSampleTime_ - lastTextureSampleTime_) <= 0.001) {
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
      return CVMetalTextureGetTexture(lastTexture_);
    }
    return lastTexture_ ? CVMetalTextureGetTexture(lastTexture_) : nil;
  }

 private:
  NSURL* url_ = nil;
  AVAssetReader* reader_ = nil;
  AVAssetReaderTrackOutput* output_ = nil;
  CVMetalTextureRef lastTexture_ = nullptr;
  std::unordered_map<int, CVMetalTextureRef> cachedTextures_;
  std::deque<int> cachedFrameOrder_;
  CMSampleBufferRef currentSample_ = nullptr;
  double currentSampleTime_ = -1.0;
  double lastTextureMediaTime_ = -1.0;
  double lastTextureSampleTime_ = -1.0;
  double readerStartTime_ = -1.0;
  double requestedMediaTime_ = 0.0;
  double fps_ = 30.0;
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
    cachedFrameOrder_.clear();
  }

  int frameIndexForTime(double timeSeconds) const {
    return std::max(0, static_cast<int>(std::llround(std::max(0.0, timeSeconds) * fps_)));
  }

  id<MTLTexture> cachedTexture(int frameIndex) {
    auto found = cachedTextures_.find(frameIndex);
    if (found == cachedTextures_.end() || found->second == nullptr) {
      return nil;
    }
    releaseLastTexture();
    CFRetain(found->second);
    lastTexture_ = found->second;
    lastTextureMediaTime_ = static_cast<double>(frameIndex) / fps_;
    lastTextureSampleTime_ = lastTextureMediaTime_;
    return CVMetalTextureGetTexture(lastTexture_);
  }

  void cacheTexture(int frameIndex, CVMetalTextureRef texture) {
    if (texture == nullptr || cachedTextures_.find(frameIndex) != cachedTextures_.end()) {
      return;
    }
    CFRetain(texture);
    cachedTextures_[frameIndex] = texture;
    cachedFrameOrder_.push_back(frameIndex);
    constexpr size_t kMaxCachedFrames = 24;
    while (cachedFrameOrder_.size() > kMaxCachedFrames) {
      const int evict = cachedFrameOrder_.front();
      cachedFrameOrder_.pop_front();
      auto found = cachedTextures_.find(evict);
      if (found != cachedTextures_.end()) {
        if (found->second != nullptr) {
          CFRelease(found->second);
        }
        cachedTextures_.erase(found);
      }
    }
  }

  void cacheCurrentSampleTexture(CVMetalTextureCacheRef textureCache) {
    if (currentSample_ == nullptr || currentSampleTime_ < 0.0) {
      return;
    }
    const int frameIndex = frameIndexForTime(currentSampleTime_);
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
    const double halfFrame = 1.0 / 60.0;

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

double EasedProgress(double value, const std::string& easing) {
  const double t = Clamp01(value, 0.0);
  if (easing == "linear") return t;
  if (easing == "easeIn") return t * t * t;
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

NativeFrameDescriptorNode EvaluateAnimation(const NativeFrameDescriptorNode& input) {
  NativeFrameDescriptorNode node = input;
  const auto* clip = node.layer.clip;
  if (clip == nullptr) return node;
  const auto tracks = CompileAnimationTracks(*clip);
  auto evaluate = [&](const std::string& property, double fallback) {
    auto found = tracks.find(property);
    return found == tracks.end() ? fallback : EvaluateAnimationTrack(found->second, node.localTime, fallback);
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

std::vector<NativeRenderGraphNode> CompileRenderGraph(const makelab::imgui::WorkspaceViewState& workspace,
                                                      const std::vector<NativeFrameDescriptorNode>& descriptor) {
  std::vector<NativeRenderGraphNode> graph;
  for (const auto& frameNode : descriptor) {
    if (frameNode.layer.clip == nullptr) {
      continue;
    }
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
    graph.push_back(node);
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
    const auto motionTile = std::find_if(clip->effects.begin(), clip->effects.end(), [](const auto& effect) {
      return effect.enabled && effect.kind == "motionTile";
    });
    if (motionTile != clip->effects.end()) {
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

  id<MTLTexture> render(const makelab::imgui::WorkspaceViewState& workspace, double timeSeconds, bool playing) {
    diagnostic_.clear();
    if (!pipeline_ || !shapePipeline_ || !textureCache_) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor blocked: Metal pipeline or CVMetalTextureCache is not ready.";
      }
      return nil;
    }
    if (!workspace.opened) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: workspace is not opened.";
      return nil;
    }
    ensureFinalTexture(workspace.width, workspace.height);
    if (!finalTexture_) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: FinalFrameSurface texture allocation failed.";
      return nil;
    }

    id<MTLCommandBuffer> commandBuffer = [commandQueue_ commandBuffer];
    const auto ir = BuildHyperFrameIR(workspace);
    const auto descriptor = EvaluateFrameDescriptor(workspace, ir, timeSeconds);
    const auto graph = CompileRenderGraph(workspace, descriptor);
    const auto fxPassGraph = CompileFXPassGraph(graph);

    std::vector<NativeCompositeNode> resolvedNodes;
    int audioNodeCount = 0;
    for (const auto& node : graph) {
      if (node.frameNode.layer.kind == NativeNodeKind::Audio) {
        audioNodeCount += 1;
        continue;
      }
      const auto* clip = node.frameNode.layer.clip;
      if (clip != nullptr) {
        if (const auto* motionBlurPass = transformMotionBlurPassForClip(fxPassGraph, clip->id)) {
          id<MTLTexture> motionBlurTexture = renderMotionBlurTexture(workspace, ir, node, fxPassGraph, *motionBlurPass, timeSeconds, playing, commandBuffer);
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
      id<MTLTexture> source = sourceTexture(workspace, node, playing);
      if (!source) {
        continue;
      }
      NativeResolvedTexture resolved = applyFXPasses(source, node, fxPassGraph, commandBuffer);
      resolvedNodes.push_back({node, node, resolved.texture ? resolved : NativeResolvedTexture{source, 1.0, 1.0}});
    }

    MTLRenderPassDescriptor* pass = [MTLRenderPassDescriptor renderPassDescriptor];
    pass.colorAttachments[0].texture = finalTexture_;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) {
      diagnostic_ = "MacMetalRenderFrameExecutor blocked: render encoder creation failed.";
      return nil;
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
                  encoder);
      drawBorder(composite.styleNode, workspace, encoder);
      drawnNodeCount += 1;
    }

    [encoder endEncoding];
    [commandBuffer commit];
    if (drawnNodeCount == 0) {
      if (diagnostic_.empty()) {
        diagnostic_ = audioNodeCount > 0
                          ? "MacMetalRenderFrameExecutor ready: only audio nodes are active at this frame; FinalFrameSurface has no visual node."
                          : "MacMetalRenderFrameExecutor blocked: RenderGraph has no drawable visual node at this frame.";
      }
      return nil;
    }
    if (!fxPassGraph.diagnostics.empty()) {
      diagnostic_ = fxPassGraph.diagnostics.front();
      for (size_t i = 1; i < fxPassGraph.diagnostics.size() && i < 3; ++i) {
        diagnostic_ += " | " + fxPassGraph.diagnostics[i];
      }
    }
    return finalTexture_;
  }

  const std::string& diagnostic() const { return diagnostic_; }

 private:
  id<MTLDevice> device_;
  id<MTLCommandQueue> commandQueue_;
  CVMetalTextureCacheRef textureCache_ = nullptr;
  MTKTextureLoader* textureLoader_ = nil;
  id<MTLRenderPipelineState> pipeline_ = nil;
  id<MTLRenderPipelineState> premultipliedPipeline_ = nil;
  id<MTLRenderPipelineState> shapePipeline_ = nil;
  id<MTLRenderPipelineState> additiveFloatPipeline_ = nil;
  id<MTLComputePipelineState> motionTilePipeline_ = nil;
  id<MTLComputePipelineState> gaussianBlurPipeline_ = nil;
  id<MTLTexture> finalTexture_ = nil;
  int finalWidth_ = 0;
  int finalHeight_ = 0;
  std::unordered_map<std::string, id<MTLTexture>> imageTextures_;
  std::unordered_map<std::string, id<MTLTexture>> generatedTextures_;
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
    if (finalTexture_ && finalWidth_ == width && finalHeight_ == height) {
      return;
    }
    MTLTextureDescriptor* descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    descriptor.storageMode = MTLStorageModePrivate;
    finalTexture_ = [device_ newTextureWithDescriptor:descriptor];
    finalWidth_ = width;
    finalHeight_ = height;
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
    const auto descriptor = EvaluateFrameDescriptor(workspace, ir, std::max(0.0, timeSeconds));
    const auto graph = CompileRenderGraph(workspace, descriptor);
    for (const auto& node : graph) {
      const auto* clip = node.frameNode.layer.clip;
      if (clip != nullptr && clip->id == clipId) {
        out = node;
        return true;
      }
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
                                                              bool playing) const {
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
    const int angularSamples = static_cast<int>(std::ceil(angularSweep / (playing ? 4.0 : 2.0)));
    const int runtimeBudget = std::min(pass.sampleBudget, playing ? 24 : 64);
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
    if (!motionTilePipeline_) {
      if (diagnostic_.empty()) {
        diagnostic_ = "FXPassGraph diagnostic: motionTileSampler reached native preview, but Metal motionTile pipeline is not ready.";
      }
      return {source, 1.0, 1.0};
    }
    const double fallbackExpansion = normalizeMotionTileExpansion(PassNumber(pass, "expansion", 1.0));
    const double expansionX = normalizeMotionTileExpansion(PassNumber(pass, "expansionX", PassNumber(pass, "outputWidth", fallbackExpansion)), fallbackExpansion);
    const double expansionY = normalizeMotionTileExpansion(PassNumber(pass, "expansionY", PassNumber(pass, "outputHeight", fallbackExpansion)), fallbackExpansion);
    if (expansionX <= 1.0001 && expansionY <= 1.0001) {
      return {source, 1.0, 1.0};
    }
    const int maxTextureDimension = 16'384;
    const int outputWidth = std::clamp(static_cast<int>(std::ceil(static_cast<double>(source.width) * expansionX)), 1, maxTextureDimension);
    const int outputHeight = std::clamp(static_cast<int>(std::ceil(static_cast<double>(source.height) * expansionY)), 1, maxTextureDimension);
    id<MTLTexture> output = makeIntermediateTexture(outputWidth, outputHeight);
    id<MTLComputeCommandEncoder> encoder = [commandBuffer computeCommandEncoder];
    if (!output || !encoder) {
      return {source, 1.0, 1.0};
    }
    const double effectiveExpansionX = std::max(1.0, static_cast<double>(output.width) / std::max<double>(1.0, source.width));
    const double effectiveExpansionY = std::max(1.0, static_cast<double>(output.height) / std::max<double>(1.0, source.height));
    MacMotionTileUniforms uniforms{
        vector_float2{static_cast<float>(effectiveExpansionX), static_cast<float>(effectiveExpansionY)},
        motionTileMode(PassString(pass, "mode", "mirror")),
        0
    };
    [encoder setComputePipelineState:motionTilePipeline_];
    [encoder setTexture:source atIndex:0];
    [encoder setTexture:output atIndex:1];
    [encoder setBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    const NSUInteger width = motionTilePipeline_.threadExecutionWidth;
    const NSUInteger height = std::max<NSUInteger>(1, motionTilePipeline_.maxTotalThreadsPerThreadgroup / width);
    [encoder dispatchThreads:MTLSizeMake(output.width, output.height, 1)
       threadsPerThreadgroup:MTLSizeMake(width, height, 1)];
    [encoder endEncoding];
    return {output, effectiveExpansionX, effectiveExpansionY};
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
    for (const auto& pass : passesForClip(fxPassGraph, clip->id)) {
      if (pass.kind == "motionTileSampler") {
        if (!includePreTransform) {
          continue;
        }
        NativeResolvedTexture resolved = applyMotionTile(current, pass, commandBuffer);
        current = resolved.texture ?: current;
        boundsScaleX *= resolved.boundsScaleX;
        boundsScaleY *= resolved.boundsScaleY;
      } else if (pass.kind == "gaussianBlur") {
        if (!includePostTransform) {
          continue;
        }
        current = applyGaussianBlur(current, pass, commandBuffer);
      } else if (pass.kind == "transformMotionBlur") {
        continue;
      }
    }
    return {current, boundsScaleX, boundsScaleY, false};
  }

  id<MTLTexture> renderMotionBlurTexture(const makelab::imgui::WorkspaceViewState& workspace,
                                         const std::vector<NativeIRLayer>& ir,
                                         const NativeRenderGraphNode& node,
                                         const NativeFXPassGraph& fxPassGraph,
                                         const NativeFXPass& pass,
                                         double timeSeconds,
                                         bool playing,
                                         id<MTLCommandBuffer> commandBuffer) {
    const auto* clip = node.frameNode.layer.clip;
    if (clip == nullptr || !additiveFloatPipeline_) {
      return nil;
    }
    id<MTLTexture> source = sourceTexture(workspace, node, playing);
    if (!source) {
      return nil;
    }
    NativeResolvedTexture resolvedSource = applyFXPasses(source, node, fxPassGraph, commandBuffer, true, false);
    resolvedSource.texture = resolvedSource.texture ?: source;
    resolvedSource.premultiplied = false;
    const auto samples = createMotionBlurSamples(pass, node, workspace, ir, timeSeconds, playing);
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
    [blurEncoder setRenderPipelineState:additiveFloatPipeline_];
    for (const auto& sample : sampleTextures) {
      if (!sample.second.texture) {
        continue;
      }
      drawTexture(sample.second.texture,
                  scaledNode(sample.first, sample.second.boundsScaleX, sample.second.boundsScaleY),
                  workspace,
                  blurEncoder);
    }
    [blurEncoder endEncoding];
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

  id<MTLTexture> imageTexture(const makelab::imgui::WorkspaceViewState& workspace, const makelab::imgui::AssetItem& asset) {
    auto cached = imageTextures_.find(asset.id);
    if (cached != imageTextures_.end()) {
      return cached->second;
    }
    NSError* error = nil;
    NSURL* url = assetURL(workspace, asset);
    if (!url) {
      if (diagnostic_.empty()) {
        diagnostic_ = "MacMetalRenderFrameExecutor warning: asset " + asset.id + " has no accepted path.";
      }
      return nil;
    }
    id<MTLTexture> texture = [textureLoader_ newTextureWithContentsOfURL:url
                                                                 options:@{ MTKTextureLoaderOptionSRGB: @NO }
                                                                   error:&error];
    if (texture) {
      imageTextures_[asset.id] = texture;
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
          return imageTexture(workspace, *asset);
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
        static_cast<float>(std::clamp(node.opacity, 0.0, 1.0)),
        static_cast<float>(node.borderWidth),
        1,
        shapeKindValue(node),
    };
    [encoder setRenderPipelineState:shapePipeline_];
    [encoder setVertexBytes:vertices.data() length:sizeof(MacPreviewVertex) * vertices.size() atIndex:0];
    [encoder setFragmentBytes:&uniforms length:sizeof(uniforms) atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:vertices.size()];
  }

  void drawTexture(id<MTLTexture> texture,
                   const NativeRenderGraphNode& node,
                   const makelab::imgui::WorkspaceViewState& workspace,
                   id<MTLRenderCommandEncoder> encoder) {
    const auto vertices = quadVertices(node, workspace);
    MacPreviewUniforms uniforms{
        vector_float4{1.0f, 1.0f, 1.0f, 1.0f},
        cornerRadii(node),
        vector_float2{static_cast<float>(node.width), static_cast<float>(node.height)},
        static_cast<float>(std::clamp(node.opacity, 0.0, 1.0)),
        0.0f,
        0,
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
    durationSeconds_ = std::max(0.001, durationSeconds);
    fps_ = std::max(1.0, fps);
    reset();
  }

  void reset() {
    playing_ = false;
    timelineTimeSeconds_ = 0.0;
    playStartHostTime_ = CACurrentMediaTime();
    playStartTimelineTime_ = 0.0;
  }

  void togglePlayback() {
    const double nowTime = timeSeconds();
    playing_ = !playing_;
    timelineTimeSeconds_ = nowTime;
    playStartTimelineTime_ = nowTime;
    playStartHostTime_ = CACurrentMediaTime();
  }

  void scrubTo(double timeSeconds) {
    playing_ = false;
    timelineTimeSeconds_ = snapToFrame(std::clamp(timeSeconds, 0.0, durationSeconds_));
    playStartTimelineTime_ = timelineTimeSeconds_;
    playStartHostTime_ = CACurrentMediaTime();
  }

  bool isPlaying() const { return playing_; }
  double fps() const { return fps_; }

  double timeSeconds() const {
    if (!playing_) {
      return std::clamp(timelineTimeSeconds_, 0.0, durationSeconds_);
    }
    const double elapsed = std::max(0.0, CACurrentMediaTime() - playStartHostTime_);
    return std::fmod(playStartTimelineTime_ + elapsed, durationSeconds_);
  }

 private:
  double snapToFrame(double timeSeconds) const {
    return std::clamp(std::round(timeSeconds * fps_) / fps_, 0.0, durationSeconds_);
  }

  bool playing_ = false;
  double durationSeconds_ = 0.001;
  double fps_ = 30.0;
  double timelineTimeSeconds_ = 0.0;
  double playStartHostTime_ = 0.0;
  double playStartTimelineTime_ = 0.0;
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

  state.projectName = project ? StringValue(project, @"name", state.folderName.c_str()) : state.folderName;
  state.width = composition ? IntValue(composition, @"width", 1080) : 1080;
  state.height = composition ? IntValue(composition, @"height", 1920) : 1920;
  state.fps = composition ? DoubleValue(composition, @"fps", 30.0) : 30.0;
  state.durationSeconds = composition ? DoubleValue(composition, @"durationSeconds", 13.26) : 13.26;

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
      nextClip.startSeconds = DoubleValue(clip, @"start", 0.0);
      nextClip.durationSeconds = std::max(0.01, DoubleValue(clip, @"duration", 1.0));
      nextClip.trimInSeconds = DoubleValue(clip, @"trimIn", 0.0);
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
@end

@implementation AppDelegate {
  makelab::imgui::WorkspaceViewState _workspace;
  std::string _status;
  MacMetalRenderFrameExecutor* _renderExecutor;
  MacNativePlaybackScheduler _playbackScheduler;
  id<MTLTexture> _finalFrameSurface;
  double _lastRenderedTimelineTimeSeconds;
  int _lastRenderedWidth;
  int _lastRenderedHeight;
  BOOL _needsFinalFrameRender;
}

- (instancetype)initWithDesignFixture:(BOOL)designFixture initialWorkspacePath:(NSString*)initialWorkspacePath {
  self = [super init];
  if (self) {
    _designFixture = designFixture;
    _initialWorkspacePath = [initialWorkspacePath copy];
    _status = "Choose Open Folder to bind a live MakeLab workspace.";
    _lastRenderedTimelineTimeSeconds = -1.0;
    _lastRenderedWidth = 0;
    _lastRenderedHeight = 0;
    _needsFinalFrameRender = YES;
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
  ImGui::StyleColorsDark();
  ImGui_ImplOSX_Init(self.view);
  ImGui_ImplMetal_Init(self.device);

  if (self.initialWorkspacePath.length > 0) {
    NSURL* url = [NSURL fileURLWithPath:self.initialWorkspacePath isDirectory:YES];
    _workspace = LoadWorkspaceState(url);
    self.designFixture = NO;
    _playbackScheduler.bindTimeline(_workspace.durationSeconds, _workspace.fps);
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
    [self.view setNeedsDisplay:YES];
  }
}

- (void)dealloc {
  delete _renderExecutor;
  _renderExecutor = nullptr;
}

- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication*)sender {
  (void)sender;
  return YES;
}

- (void)renderAcceptedFrame {
  _finalFrameSurface = nil;
  if (!_workspace.opened || _renderExecutor == nullptr) {
    return;
  }

  const double timelineTime = _playbackScheduler.timeSeconds();
  _finalFrameSurface = _renderExecutor->render(_workspace, timelineTime, _playbackScheduler.isPlaying());
  _lastRenderedTimelineTimeSeconds = timelineTime;
  _lastRenderedWidth = _workspace.width;
  _lastRenderedHeight = _workspace.height;
  _needsFinalFrameRender = NO;
}

- (void)applyWorkspaceFrameRate {
  if (!_workspace.opened || self.view == nil) {
    return;
  }
  bool hasExpensiveFX = false;
  for (const auto& track : _workspace.tracks) {
    for (const auto& clip : track.clips) {
      if (clip.hasEffects) {
        hasExpensiveFX = true;
        break;
      }
    }
    if (hasExpensiveFX) {
      break;
    }
  }
  const double maxPreviewFPS = hasExpensiveFX ? 30.0 : 60.0;
  int fps = static_cast<int>(std::round(std::clamp(_workspace.fps, 1.0, maxPreviewFPS)));
  self.view.preferredFramesPerSecond = std::max(1, fps);
}

- (void)openProjectFolder {
  NSOpenPanel* panel = [NSOpenPanel openPanel];
  panel.canChooseFiles = NO;
  panel.canChooseDirectories = YES;
  panel.canCreateDirectories = YES;
  panel.allowsMultipleSelection = NO;
  panel.prompt = @"Open Folder";
  panel.message = @"Choose an existing MakeLab project folder or create a new empty folder.";

  NSModalResponse response = [panel runModal];
  if (response != NSModalResponseOK || panel.URL == nil) {
    return;
  }

  @try {
    _workspace = LoadWorkspaceState(panel.URL);
    self.designFixture = NO;
    self.playingDesignFixture = NO;
    _playbackScheduler.bindTimeline(_workspace.durationSeconds, _workspace.fps);
    _needsFinalFrameRender = YES;
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
    self.view.paused = YES;
    [self.view setNeedsDisplay:YES];
  } @catch (NSException* exception) {
    _workspace = {};
    _status = "Open Folder failed: " + ToStdString(exception.reason ?: @"unknown error");
  }
}

- (void)handleEditorCommand:(NSString*)command timelineTimeSeconds:(double)timelineTimeSeconds {
  if ([command isEqualToString:@"OpenProject"]) {
    [self openProjectFolder];
    return;
  }
  if ([command isEqualToString:@"ScrubTimeline"]) {
    if (!_workspace.opened) {
      _status = "Open Folder before live scrub.";
      return;
    }
    _playbackScheduler.scrubTo(timelineTimeSeconds);
    _needsFinalFrameRender = YES;
    _status = "Live scrub queued: native scheduler will request FinalFrameSurface on the next frame.";
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
    [self renderAcceptedFrame];
    if (!_finalFrameSurface) {
      _playbackScheduler.reset();
      _status = "Playback blocked: FinalFrameSurface is not ready.";
      if (_renderExecutor != nullptr && !_renderExecutor->diagnostic().empty()) {
        _status += " " + _renderExecutor->diagnostic();
      }
      return;
    }
    _playbackScheduler.togglePlayback();
    _needsFinalFrameRender = YES;
    self.view.paused = !_playbackScheduler.isPlaying();
    [self.view setNeedsDisplay:YES];
    _status = _playbackScheduler.isPlaying()
                  ? "Playback started: native scheduler driving FinalFrameSurface."
                  : "Playback paused: FinalFrameSurface retained at current timeline time.";
    return;
  }
  if ([command isEqualToString:@"RequestRender"]) {
    _status = _workspace.opened ? "Render command queued. Native RenderGraph bridge is required before preview/export execution." : "Open Folder before Render.";
    [self.view setNeedsDisplay:YES];
    return;
  }
  if ([command isEqualToString:@"RequestExport"]) {
    _status = _workspace.opened ? "Export blocked until FinalFrameSurface exporter is connected." : "Open Folder before Export.";
    [self.view setNeedsDisplay:YES];
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
      const double timelineTime = _playbackScheduler.timeSeconds();
      const double frameDuration = 1.0 / std::max(1.0, _workspace.fps);
      const bool frameChanged = std::abs(timelineTime - _lastRenderedTimelineTimeSeconds) >= frameDuration * 0.5;
      const bool sizeChanged = _workspace.width != _lastRenderedWidth || _workspace.height != _lastRenderedHeight;
      const bool shouldRenderFinalFrame = _needsFinalFrameRender ||
                                          _finalFrameSurface == nil ||
                                          _playbackScheduler.isPlaying() ||
                                          frameChanged ||
                                          sizeChanged;
      if (shouldRenderFinalFrame) {
        [self renderAcceptedFrame];
      }
      if (_finalFrameSurface) {
        std::string diagnostic = _renderExecutor != nullptr ? _renderExecutor->diagnostic() : "";
        _status = diagnostic.empty()
                      ? "FinalFrameSurface ready: MacMetalRenderFrameExecutor."
                      : "FinalFrameSurface ready: MacMetalRenderFrameExecutor. " + diagnostic;
      } else if (_renderExecutor != nullptr && !_renderExecutor->diagnostic().empty()) {
        _status = _renderExecutor->diagnostic();
      }
    }

    makelab::imgui::EditorShellConfig config;
    config.designFixture = self.designFixture;
    config.finalFrameSurfaceReady = _finalFrameSurface != nil;
    config.finalFrameSurfaceTexture = (__bridge void*)_finalFrameSurface;
    config.finalFrameSurfaceWidth = _workspace.opened ? _workspace.width : 0;
    config.finalFrameSurfaceHeight = _workspace.opened ? _workspace.height : 0;
    config.playbackTimeSeconds = _workspace.opened
                                     ? _playbackScheduler.timeSeconds()
                                     : ((self.designFixture && self.playingDesignFixture) ? fmod(CACurrentMediaTime() - self.startTime, 13.87) : 0.0);
    config.durationSeconds = _workspace.opened ? _workspace.durationSeconds : (self.designFixture ? 13.87 : 0.0);
    config.diagnostic = _status.empty()
                            ? "Preview blocked: waiting for FinalFrameSurface from Gates -> HyperFrame IR -> FrameDescriptor -> RenderGraph -> FXPassGraph."
                            : _status.c_str();
    config.workspace = &_workspace;
    makelab::imgui::EditorShellResult result = makelab::imgui::DrawEditorShell(config);
    if (!result.command.empty()) {
      NSString* command = [NSString stringWithUTF8String:result.command.c_str()];
      double timelineTimeSeconds = result.timelineTimeSeconds;
      dispatch_async(dispatch_get_main_queue(), ^{
        [self handleEditorCommand:command timelineTimeSeconds:timelineTimeSeconds];
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

int main(int argc, char** argv) {
  @autoreleasepool {
    BOOL designFixture = NO;
    NSString* initialWorkspacePath = nil;
    for (int i = 1; i < argc; ++i) {
      if (std::string(argv[i]) == "--design-fixture") {
        designFixture = YES;
      } else if (std::string(argv[i]) == "--open-workspace" && i + 1 < argc) {
        initialWorkspacePath = [NSString stringWithUTF8String:argv[++i]];
      }
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
