import 'dart:math' as math;

import 'fidelity_tier.dart';

/// The percentile [p] (0 to 1) of [values], by the nearest-rank method. Null for
/// an empty list.
double? percentile(List<double> values, double p) {
  if (values.isEmpty) return null;
  final sorted = List<double>.of(values)..sort();
  final rank = (p * sorted.length).ceil().clamp(1, sorted.length);
  return sorted[rank - 1];
}

/// What the detector decided.
class TierDecision {
  const TierDecision({
    required this.tier,
    required this.fpsCap,
    required this.p90Milliseconds,
  });

  final FidelityTier tier;

  /// The frame rate to hold the app to, or null to run at the display's own.
  final int? fpsCap;

  /// The 90th percentile of the frames it looked at, in milliseconds.
  final double p90Milliseconds;

  @override
  String toString() =>
      'TierDecision(${tier.label}, cap $fpsCap, p90 ${p90Milliseconds.toStringAsFixed(1)} ms)';

  @override
  bool operator ==(Object other) =>
      other is TierDecision &&
      other.tier == tier &&
      other.fpsCap == fpsCap &&
      other.p90Milliseconds == p90Milliseconds;

  @override
  int get hashCode => Object.hash(tier, fpsCap, p90Milliseconds);
}

/// Chooses a fidelity tier from how the first launch's cold open ran (DESIGN.md
/// 9.2): the highest tier whose frame budget the 90th percentile frame fits, with
/// 25% headroom.
///
/// The cold open is drawn at one tier, the [benchmarkTier], and the frames it took
/// say what that tier costs on this phone. A tier costs a known multiple of another
/// ([relativeCost]), so from one measurement the detector can say whether the
/// tiers above and below would fit. The multiples are estimates, to be tuned on
/// real phones after the hardware handoff (CLAUDE.md 13, phase 7).
class TierDetector {
  const TierDetector({
    this.benchmarkTier = FidelityTier.balanced,
    this.headroom = 1.25,
    this.percentileRank = 0.9,
    this.minimumFrames = 20,
  });

  /// The tier the cold open was drawn at.
  final FidelityTier benchmarkTier;

  /// How much faster than its budget a tier's frames must be: 25% headroom is 1.25.
  final double headroom;

  final double percentileRank;

  /// Fewer frames than this say too little to decide on.
  final int minimumFrames;

  /// What a frame at [tier] costs, against a frame at Balanced. Full adds bloom and
  /// twice the trail, and Lite has half the segments and only the cheapest halos.
  static double relativeCost(FidelityTier tier) => switch (tier) {
    FidelityTier.lite => 0.6,
    FidelityTier.balanced => 1.0,
    FidelityTier.full => 1.7,
  };

  /// The frame budget of [tier], in milliseconds, on a display refreshing at
  /// [displayHz]: Lite and Balanced aim for 60, and Full for the display's own.
  static double budgetMilliseconds(FidelityTier tier, double displayHz) {
    final fps = tier == FidelityTier.full ? math.max(60, displayHz) : 60;
    return 1000 / fps;
  }

  /// Decides from [frameMilliseconds], the cost of each frame of the cold open
  /// (the longer of its build and its raster time), on a display at [displayHz].
  ///
  /// Too few frames to judge give the middle tier. If even Lite does not fit its
  /// 60 fps budget, the answer is Lite held to 30 fps.
  TierDecision decide({
    required List<double> frameMilliseconds,
    double displayHz = 60,
  }) {
    final p90 = frameMilliseconds.length < minimumFrames
        ? null
        : percentile(frameMilliseconds, percentileRank);
    if (p90 == null) {
      return const TierDecision(
        tier: FidelityTier.balanced,
        fpsCap: 60,
        p90Milliseconds: 0,
      );
    }
    final scale = p90 / relativeCost(benchmarkTier);

    for (final tier in [
      FidelityTier.full,
      FidelityTier.balanced,
      FidelityTier.lite,
    ]) {
      // Full is only worth having if the display is fast or there is room to
      // spare, and the same rule covers both.
      final predicted = scale * relativeCost(tier);
      if (predicted * headroom <= budgetMilliseconds(tier, displayHz)) {
        return TierDecision(
          tier: tier,
          fpsCap: tier == FidelityTier.full ? null : 60,
          p90Milliseconds: p90,
        );
      }
    }
    return TierDecision(
      tier: FidelityTier.lite,
      fpsCap: 30,
      p90Milliseconds: p90,
    );
  }
}
