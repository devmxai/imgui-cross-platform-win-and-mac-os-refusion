#include "timeline/TimelineTruth.hpp"

#include <cassert>
#include <cmath>

using makelab::timeline::FrameRateFromFps;
using makelab::timeline::FrameToClockTimecode;
using makelab::timeline::FrameToSeconds;
using makelab::timeline::RangeFromLegacySeconds;
using makelab::timeline::SecondsToFrameRound;
using makelab::timeline::TimelineCoordinator;

int main() {
  {
    const auto rate = FrameRateFromFps(29.97);
    assert(rate.numerator == 30000);
    assert(rate.denominator == 1001);
    assert(SecondsToFrameRound(1001.0 / 30000.0, rate) == 1);
    assert(std::abs(FrameToSeconds({30}, rate) - (30.0 * 1001.0 / 30000.0)) < 0.0000001);
  }
  {
    const auto rate = FrameRateFromFps(59.94);
    assert(rate.numerator == 60000);
    assert(rate.denominator == 1001);
    assert(SecondsToFrameRound(1001.0 / 60000.0, rate) == 1);
  }
  {
    const auto rate = FrameRateFromFps(30.0);
    const auto range = RangeFromLegacySeconds(3.0, 2.0, rate);
    assert(range.startFrame == 90);
    assert(range.endFrame == 150);
    assert(90 >= range.startFrame && 90 < range.endFrame);
    assert(149 >= range.startFrame && 149 < range.endFrame);
    assert(!(150 >= range.startFrame && 150 < range.endFrame));
  }
  {
    const auto rate = FrameRateFromFps(24.0);
    assert(SecondsToFrameRound(1.0, rate) == 24);
    assert(std::abs(FrameToSeconds({48}, rate) - 2.0) < 0.0000001);
    assert(FrameToClockTimecode({0}, rate) == "00:00:00:00");
    assert(FrameToClockTimecode({23}, rate) == "00:00:00:23");
    assert(FrameToClockTimecode({24}, rate) == "00:00:01:00");
    assert(FrameToClockTimecode({24 * 60 + 7}, rate) == "00:01:00:07");
  }
  {
    const auto rate = FrameRateFromFps(30000.0 / 1001.0);
    assert(FrameToClockTimecode({0}, rate) == "00:00:00:00");
    assert(FrameToClockTimecode({29}, rate) == "00:00:00:29");
    assert(FrameToClockTimecode({30}, rate) == "00:00:01:00");
  }
  {
    TimelineCoordinator coordinator;
    coordinator.bind(10.0, 30.0);
    const uint64_t generation1 = coordinator.requestScrubFrame(30);
    const uint64_t generation2 = coordinator.requestScrubFrame(90);
    assert(generation2 != generation1);
    assert(!coordinator.acceptRequestedFrame(generation1));
    assert(coordinator.acceptedFrame() == 0);
    assert(coordinator.acceptRequestedFrame(generation2));
    assert(coordinator.acceptedFrame() == 90);
  }
  return 0;
}
