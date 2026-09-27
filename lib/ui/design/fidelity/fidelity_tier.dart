/// The three fidelity tiers (DESIGN.md 9.1).
///
/// Composition, typography, light hierarchy and springs are the same in all of
/// them. A tier only decides how much garnish is drawn, so that the design holds
/// up on a 2016 phone and uses a flagship's headroom when there is some.
enum FidelityTier {
  /// Lite: must still look intentional and premium.
  lite('LITE', 1),

  /// Balanced.
  balanced('BALANCED', 2),

  /// Full: the display's own refresh rate, and shader bloom.
  full('FULL', 3);

  const FidelityTier(this.label, this.number);

  final String label;
  final int number;

  /// The next tier down, or null at the bottom. The governor steps down one at a
  /// time (DESIGN.md 9.2).
  FidelityTier? get lower => switch (this) {
    lite => null,
    balanced => lite,
    full => balanced,
  };

  /// What this tier draws.
  TierProfile get profile => TierProfile._byTier[this]!;
}

/// Which luminous elements get phosphor persistence (DESIGN.md 5.5).
enum PhosphorScope {
  /// Tach and horizon segments only.
  segments,

  /// Every luminous element.
  all,
}

/// What a [FidelityTier] draws: the columns of DESIGN.md 9.1.
class TierProfile {
  const TierProfile._({
    required this.targetFps,
    required this.fallbackFps,
    required this.halosOnHeroAndNeedleOnly,
    required this.halosAtHalfResolution,
    required this.shaderBloom,
    required this.trailLength,
    required this.phosphor,
    required this.parallax,
    required this.rpmPerSegment,
    required this.maxStreaks,
    required this.velocityStretch,
  });

  /// The frame rate to aim for, or null for the display's own maximum.
  final int? targetFps;

  /// The frame rate to fall back to if the target cannot be held.
  final int? fallbackFps;

  /// Baked halos on the hero readout and the needle only.
  final bool halosOnHeroAndNeedleOnly;

  /// Halo sprites at half resolution.
  final bool halosAtHalfResolution;

  /// A fragment shader adds bloom (needs a runtime compile check, DESIGN.md 9.3).
  final bool shaderBloom;

  /// How many older needle angles are drawn as a trail.
  final int trailLength;

  final PhosphorScope phosphor;

  /// Pages move with parallax across layers.
  final bool parallax;

  /// One tach segment for this many rpm.
  final int rpmPerSegment;

  /// The most speed streaks drawn in the road view.
  final int maxStreaks;

  /// Glyphs stretch vertically with roll speed, by up to 6%.
  final bool velocityStretch;

  static const Map<FidelityTier, TierProfile> _byTier = {
    FidelityTier.lite: TierProfile._(
      targetFps: 60,
      fallbackFps: 30,
      halosOnHeroAndNeedleOnly: true,
      halosAtHalfResolution: true,
      shaderBloom: false,
      trailLength: 2,
      phosphor: PhosphorScope.segments,
      parallax: false,
      rpmPerSegment: 200,
      maxStreaks: 0,
      velocityStretch: false,
    ),
    FidelityTier.balanced: TierProfile._(
      targetFps: 60,
      fallbackFps: null,
      halosOnHeroAndNeedleOnly: false,
      halosAtHalfResolution: false,
      shaderBloom: false,
      trailLength: 6,
      phosphor: PhosphorScope.all,
      parallax: true,
      rpmPerSegment: 100,
      maxStreaks: 40,
      velocityStretch: false,
    ),
    FidelityTier.full: TierProfile._(
      targetFps: null,
      fallbackFps: null,
      halosOnHeroAndNeedleOnly: false,
      halosAtHalfResolution: false,
      shaderBloom: true,
      trailLength: 12,
      phosphor: PhosphorScope.all,
      parallax: true,
      rpmPerSegment: 100,
      maxStreaks: 120,
      velocityStretch: true,
    ),
  };
}
