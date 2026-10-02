#!/usr/bin/env bash
set -euo pipefail

# Keep all assertions, but avoid running wall-clock audio playback alongside
# the CPU-heavy FFT/AutoMix analyses on small macOS CI runners. These suites
# still run below; --skip is only used to partition the complete test set.
echo "=== Core and analysis tests ==="
swift test --skip 'PlaybackEngineSmokeTests|TransitionSegmentTests'

echo "=== Real-time playback engine tests (isolated) ==="
swift test --filter PlaybackEngineSmokeTests

echo "=== Transition segment tests (isolated) ==="
swift test --filter TransitionSegmentTests
