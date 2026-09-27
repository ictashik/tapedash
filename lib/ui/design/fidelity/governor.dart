import 'dart:collection';

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../tokens/motion_tokens.dart';
import 'fidelity_tier.dart';
import 'tier_detector.dart';

/// Why the tier is what it is.
enum TierReason {
  /// The detector chose it from the cold open.
  detected,

  /// The governor stepped down because frames were over budget.
  governor,

  /// The phone is hot (DESIGN.md 9.2).
  thermal,

  /// The user chose it in the Garage.
  user,
}

/// The tier in effect, and how fast to run.
class TierState {
  const TierState({
    required this.tier,
    required this.fpsCap,
    required this.reason,
  });

  final FidelityTier tier;

  /// The frame rate to hold the app to, or null for the display's own.
  final int? fpsCap;

  final TierReason reason;

  @override
  bool operator ==(Object other) =>
      other is TierState &&
      other.tier == tier &&
      other.fpsCap == fpsCap &&
      other.reason == reason;

  @override
  int get hashCode => Object.hash(tier, fpsCap, reason);

  @override
  String toString() => 'TierState(${tier.label}, cap $fpsCap, ${reason.name})';
}

/// The numbers behind the governor.
class GovernorConfig {
  const GovernorConfig({
    this.overBudgetFor = TapeMotion.governorOverBudget,
    this.window = TapeMotion.governorWindow,
    this.percentileRank = 0.9,
    this.minimumFrames = 30,
    this.hotCelsius = 50,
    this.crossfade = TapeMotion.tierCrossfade,
  });

  /// The 90th percentile frame must be over budget for this long before the
  /// governor steps down (DESIGN.md 9.2).
  final Duration overBudgetFor;

  /// The recent frames the percentile is taken over.
  final Duration window;

  final double percentileRank;

  /// Fewer frames than this in the window say too little to act on.
  final int minimumFrames;

  /// The phone is hot above this, in degrees Celsius (DESIGN.md 9.2).
  final double hotCelsius;

  /// A step down is shown as a crossfade this long (DESIGN.md 9.2).
  final Duration crossfade;
}

/// The runtime governor (DESIGN.md 9.2): if the frames run over budget for 5 s, it
/// steps down one tier. It never steps up during a trip, and takes a hot phone to
/// Lite at 30 fps. Frames are fed in with [onFrames] and the tier is read from
/// [state].
///
/// It works on the injected [Clock], so tests run it in no time.
class TierGovernor {
  TierGovernor({
    required this.clock,
    required TierDecision initial,
    this.config = const GovernorConfig(),
    TierReason reason = TierReason.detected,
  }) : _state = ObservableValue(
         TierState(tier: initial.tier, fpsCap: initial.fpsCap, reason: reason),
       );

  final Clock clock;
  final GovernorConfig config;

  final ObservableValue<TierState> _state;
  final Queue<(Duration, double)> _frames = Queue();
  Duration? _overSince;
  FidelityTier? _pinned;
  bool _hot = false;

  /// The tier and frame rate in effect.
  Observable<TierState> get state => _state;

  /// The tier the user has chosen, or null for automatic (DESIGN.md 7.8).
  FidelityTier? get pinnedTier => _pinned;

  /// Chooses a tier, or null for automatic. A chosen tier is held: the governor does
  /// not step it down. A hot phone still overrides it.
  void pin(FidelityTier? tier) {
    _pinned = tier;
    _overSince = null;
    _frames.clear();
    if (_hot) return;
    if (tier != null) {
      _state.value = TierState(
        tier: tier,
        fpsCap: tier.profile.targetFps,
        reason: TierReason.user,
      );
    }
  }

  /// Says whether the phone is hot. Above 50 C the tier is Lite at 30 fps; and
  /// it stays there, since the tier never steps up during a trip.
  void onBatteryTemperature(double? celsius) {
    if (celsius == null || celsius <= config.hotCelsius) return;
    _hot = true;
    _state.value = const TierState(
      tier: FidelityTier.lite,
      fpsCap: 30,
      reason: TierReason.thermal,
    );
  }

  /// Takes the cost, in milliseconds, of some frames that were just drawn: the
  /// longer of each one's build and raster time.
  void onFrames(List<double> milliseconds) {
    final now = clock.monotonic();
    for (final ms in milliseconds) {
      _frames.add((now, ms));
    }
    while (_frames.isNotEmpty && now - _frames.first.$1 >= config.window) {
      _frames.removeFirst();
    }
    if (_pinned != null || _hot) return;
    if (_frames.length < config.minimumFrames) return;

    final p90 = percentile([
      for (final f in _frames) f.$2,
    ], config.percentileRank)!;
    final current = _state.value;
    final fps = current.fpsCap ?? 60;
    final budget = 1000 / fps;
    if (p90 <= budget) {
      _overSince = null;
      return;
    }
    _overSince ??= now;
    if (now - _overSince! < config.overBudgetFor) return;

    // Over budget for long enough: one step down, and start counting afresh.
    _overSince = null;
    _frames.clear();
    final lower = current.tier.lower;
    if (lower != null) {
      _state.value = TierState(
        tier: lower,
        fpsCap: lower == FidelityTier.full ? null : (current.fpsCap ?? 60),
        reason: TierReason.governor,
      );
    } else if (current.fpsCap != 30) {
      // Lite and still slow: the last resort is 30 fps.
      _state.value = TierState(
        tier: FidelityTier.lite,
        fpsCap: 30,
        reason: TierReason.governor,
      );
    }
  }

  void dispose() => _state.dispose();
}
