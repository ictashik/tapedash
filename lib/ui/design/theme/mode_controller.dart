import 'dart:math' as math;

import '../../../core/clock.dart';
import '../../../core/observable.dart';
import '../tokens/motion_tokens.dart';
import 'palette.dart';

/// The Garage choice of mode (DESIGN.md 4.4): follow the light sensor, or hold
/// one mode.
enum ModeSetting {
  auto('AUTO'),
  normal('NORMAL'),
  daylight('DAYLIGHT'),
  night('NIGHT');

  const ModeSetting(this.label);

  final String label;

  /// The mode this setting holds, or null for [auto].
  TapeMode? get fixed => switch (this) {
    auto => null,
    normal => TapeMode.normal,
    daylight => TapeMode.daylight,
    night => TapeMode.night,
  };
}

/// When ambient light turns Daylight and Night on and off (DESIGN.md 4.4). Each
/// mode is entered at one level and left at another, and the light must stay
/// past the level for a while, so a passing shadow or a street light does not
/// make the screen flicker between modes.
class ModeThresholds {
  const ModeThresholds({
    this.daylightAbove = 5000,
    this.daylightBelow = 2000,
    this.nightBelow = 20,
    this.nightAbove = 60,
    this.dwell = TapeMotion.modeDwell,
  });

  /// Enter Daylight above this many lux, and leave it below [daylightBelow].
  final double daylightAbove;
  final double daylightBelow;

  /// Enter Night below this many lux, and leave it above [nightAbove].
  final double nightBelow;
  final double nightAbove;

  /// How long the light must stay past a threshold.
  final Duration dwell;
}

/// Picks the mode from the ambient light (DESIGN.md 4.4).
///
/// Feed it lux readings with [onLux]. It keeps the mode it is in until the light
/// has been past a threshold for the whole dwell time. A [ModeSetting] other
/// than auto holds a mode whatever the light does.
class ModeController {
  ModeController({
    required this.clock,
    this.thresholds = const ModeThresholds(),
    this._setting = ModeSetting.auto,
  }) {
    _mode = ObservableValue(_setting.fixed ?? TapeMode.normal);
  }

  final Clock clock;
  final ModeThresholds thresholds;

  late final ObservableValue<TapeMode> _mode;
  ModeSetting _setting;

  /// What the light says, apart from the setting.
  TapeMode _auto = TapeMode.normal;
  TapeMode? _candidate;
  Duration? _candidateSince;

  /// The mode in effect.
  Observable<TapeMode> get mode => _mode;

  ModeSetting get setting => _setting;

  set setting(ModeSetting value) {
    _setting = value;
    _apply();
  }

  /// Takes an ambient light reading, in lux.
  void onLux(double lux) {
    if (lux.isNaN) return;
    final target = _targetFor(lux);
    final now = clock.monotonic();
    if (target == _auto) {
      _candidate = null;
      _candidateSince = null;
      return;
    }
    if (_candidate != target) {
      _candidate = target;
      _candidateSince = now;
    }
    if (now - _candidateSince! >= thresholds.dwell) {
      _auto = target;
      _candidate = null;
      _candidateSince = null;
      _apply();
    }
  }

  /// The mode the light points to from where it is: each mode is left at a
  /// different level from the one it is entered at.
  TapeMode _targetFor(double lux) {
    switch (_auto) {
      case TapeMode.normal:
        if (lux > thresholds.daylightAbove) return TapeMode.daylight;
        if (lux < thresholds.nightBelow) return TapeMode.night;
        return TapeMode.normal;
      case TapeMode.daylight:
        if (lux >= thresholds.daylightBelow) return TapeMode.daylight;
        return lux < thresholds.nightBelow ? TapeMode.night : TapeMode.normal;
      case TapeMode.night:
        if (lux <= thresholds.nightAbove) return TapeMode.night;
        return lux > thresholds.daylightAbove
            ? TapeMode.daylight
            : TapeMode.normal;
    }
  }

  void _apply() => _mode.value = _setting.fixed ?? _auto;

  void dispose() => _mode.dispose();
}

/// How bright the screen should be, from 0 to 1, or null to leave it to the
/// phone (DESIGN.md 4.4 and 8).
abstract final class ScreenBrightness {
  /// Night's floor: the screen never goes dimmer than this.
  static const double nightFloor = 0.12;

  /// The HUD's floor at night (DESIGN.md 8).
  static const double hudNightFloor = 0.20;

  /// Where the night curve tops out, at [nightCeilingLux].
  static const double nightCeiling = 0.45;
  static const double nightCeilingLux = 60;

  /// Daylight is at maximum. Night follows a lux curve from [floor] up to
  /// [nightCeiling]. Normal is the phone's own.
  static double? forMode(
    TapeMode mode,
    double? lux, {
    double floor = nightFloor,
  }) {
    switch (mode) {
      case TapeMode.daylight:
        return 1;
      case TapeMode.normal:
        return null;
      case TapeMode.night:
        final share = math.min(
          1.0,
          math.max(0.0, (lux ?? 0) / nightCeilingLux),
        );
        // Perception is roughly logarithmic, so the first lux count for most.
        final curve = math.sqrt(share);
        return floor + (math.max(floor, nightCeiling) - floor) * curve;
    }
  }
}
