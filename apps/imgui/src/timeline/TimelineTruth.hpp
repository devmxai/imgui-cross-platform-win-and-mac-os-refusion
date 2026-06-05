#pragma once

#include <algorithm>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <string>

namespace makelab::timeline {

struct FrameRate {
  int64_t numerator = 30;
  int64_t denominator = 1;
};

struct FrameIndex {
  int64_t value = 0;
};

struct FrameRange {
  int64_t startFrame = 0;
  int64_t endFrame = 0;
};

inline FrameRate NormalizeRate(FrameRate rate) {
  if (rate.numerator <= 0) rate.numerator = 30;
  if (rate.denominator <= 0) rate.denominator = 1;
  return rate;
}

inline bool Nearly(double a, double b, double epsilon = 0.001) {
  return std::abs(a - b) <= epsilon;
}

inline FrameRate FrameRateFromFps(double fps) {
  if (!std::isfinite(fps) || fps <= 0.0) {
    return {30, 1};
  }
  if (Nearly(fps, 23.976, 0.01) || Nearly(fps, 24000.0 / 1001.0, 0.001)) return {24000, 1001};
  if (Nearly(fps, 29.97, 0.01) || Nearly(fps, 30000.0 / 1001.0, 0.001)) return {30000, 1001};
  if (Nearly(fps, 59.94, 0.01) || Nearly(fps, 60000.0 / 1001.0, 0.001)) return {60000, 1001};
  return {std::max<int64_t>(1, static_cast<int64_t>(std::llround(fps))), 1};
}

inline double Fps(FrameRate rate) {
  rate = NormalizeRate(rate);
  return static_cast<double>(rate.numerator) / static_cast<double>(rate.denominator);
}

inline int64_t SecondsToFrameRound(double seconds, FrameRate rate) {
  rate = NormalizeRate(rate);
  const double safeSeconds = std::isfinite(seconds) ? std::max(0.0, seconds) : 0.0;
  return std::max<int64_t>(0, static_cast<int64_t>(std::llround(safeSeconds * Fps(rate))));
}

inline double FrameToSeconds(FrameIndex frame, FrameRate rate) {
  rate = NormalizeRate(rate);
  return static_cast<double>(std::max<int64_t>(0, frame.value)) *
         static_cast<double>(rate.denominator) /
         static_cast<double>(rate.numerator);
}

inline std::string FrameToClockTimecode(FrameIndex frame, FrameRate rate) {
  rate = NormalizeRate(rate);
  const int64_t safeFrame = std::max<int64_t>(0, frame.value);
  const double seconds = FrameToSeconds({safeFrame}, rate);
  const int64_t wholeSeconds = std::max<int64_t>(0, static_cast<int64_t>(std::floor(seconds)));
  const int64_t displayFps = std::max<int64_t>(1, static_cast<int64_t>(std::llround(Fps(rate))));
  const int64_t frameOfSecond = std::clamp<int64_t>(
      safeFrame - SecondsToFrameRound(static_cast<double>(wholeSeconds), rate),
      0,
      displayFps - 1);
  const int64_t hours = wholeSeconds / 3600;
  const int64_t minutes = (wholeSeconds / 60) % 60;
  const int64_t secs = wholeSeconds % 60;
  char buffer[32];
  std::snprintf(buffer,
                sizeof(buffer),
                "%02lld:%02lld:%02lld:%02lld",
                static_cast<long long>(hours),
                static_cast<long long>(minutes),
                static_cast<long long>(secs),
                static_cast<long long>(frameOfSecond));
  return buffer;
}

inline int64_t ClampFrame(int64_t frame, int64_t durationFrames) {
  return std::clamp<int64_t>(frame, 0, std::max<int64_t>(0, durationFrames));
}

inline FrameRange RangeFromLegacySeconds(double startSeconds, double durationSeconds, FrameRate rate) {
  const int64_t start = SecondsToFrameRound(startSeconds, rate);
  const int64_t duration = std::max<int64_t>(1, SecondsToFrameRound(durationSeconds, rate));
  return {start, start + duration};
}

class TimelineCoordinator {
 public:
  void bind(double durationSeconds, double fps) {
    rate_ = FrameRateFromFps(fps);
    durationFrames_ = std::max<int64_t>(1, SecondsToFrameRound(durationSeconds, rate_));
    reset();
  }

  void reset() {
    playing_ = false;
    requestedFrame_ = 0;
    acceptedFrame_ = 0;
    playStartAcceptedFrame_ = 0;
    playStartHostSeconds_ = 0.0;
    requestGeneration_ = 1;
    acceptedGeneration_ = 0;
  }

  void beginPlayback(double hostSeconds) {
    if (playing_) return;
    playing_ = true;
    playStartAcceptedFrame_ = acceptedFrame_;
    playStartHostSeconds_ = hostSeconds;
    requestedFrame_ = acceptedFrame_;
    ++requestGeneration_;
  }

  void pausePlayback() {
    playing_ = false;
    requestedFrame_ = acceptedFrame_;
    ++requestGeneration_;
  }

  void togglePlayback(double hostSeconds) {
    if (playing_) {
      pausePlayback();
    } else {
      beginPlayback(hostSeconds);
    }
  }

  int64_t requestFrameForHostTime(double hostSeconds) {
    if (playing_) {
      const double elapsed = std::max(0.0, hostSeconds - playStartHostSeconds_);
      const int64_t elapsedFrames = std::max<int64_t>(0, static_cast<int64_t>(std::floor(elapsed * Fps(rate_))));
      const int64_t nextFrame = durationFrames_ > 0 ? (playStartAcceptedFrame_ + elapsedFrames) % durationFrames_ : 0;
      if (nextFrame != requestedFrame_) {
        requestedFrame_ = nextFrame;
        ++requestGeneration_;
      }
    }
    return requestedFrame_;
  }

  uint64_t requestScrubFrame(int64_t frame) {
    playing_ = false;
    const int64_t nextFrame = ClampFrame(frame, durationFrames_);
    if (nextFrame != requestedFrame_) {
      requestedFrame_ = nextFrame;
      ++requestGeneration_;
    }
    return requestGeneration_;
  }

  bool acceptRequestedFrame(uint64_t generation) {
    if (generation != requestGeneration_) {
      return false;
    }
    acceptedFrame_ = ClampFrame(requestedFrame_, durationFrames_);
    acceptedGeneration_ = generation;
    if (!playing_) {
      playStartAcceptedFrame_ = acceptedFrame_;
    }
    return true;
  }

  bool acceptRequestedFrame() {
    return acceptRequestedFrame(requestGeneration_);
  }

  bool isPlaying() const { return playing_; }
  FrameRate rate() const { return rate_; }
  int64_t durationFrames() const { return durationFrames_; }
  int64_t requestedFrame() const { return requestedFrame_; }
  int64_t acceptedFrame() const { return acceptedFrame_; }
  uint64_t requestGeneration() const { return requestGeneration_; }
  uint64_t acceptedGeneration() const { return acceptedGeneration_; }
  double acceptedSeconds() const { return FrameToSeconds({acceptedFrame_}, rate_); }
  double requestedSeconds() const { return FrameToSeconds({requestedFrame_}, rate_); }

 private:
  FrameRate rate_;
  int64_t durationFrames_ = 1;
  int64_t requestedFrame_ = 0;
  int64_t acceptedFrame_ = 0;
  int64_t playStartAcceptedFrame_ = 0;
  double playStartHostSeconds_ = 0.0;
  uint64_t requestGeneration_ = 1;
  uint64_t acceptedGeneration_ = 0;
  bool playing_ = false;
};

}  // namespace makelab::timeline
