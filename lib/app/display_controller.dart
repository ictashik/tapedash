import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';

import '../core/clock.dart';
import '../core/observable.dart';
import '../core/scheduler.dart';
import '../platform/device_features.dart';
import '../ui/design/fidelity/fidelity_tier.dart';
import '../ui/design/fidelity/frame_probe.dart';
import '../ui/design/fidelity/governor.dart';
import '../ui/design/fidelity/tier_detector.dart';
import '../ui/design/theme/mode_controller.dart';
import '../ui/design/theme/palette.dart' show TapeMode;
import 'app_settings.dart';

/// How the frames are going, once a second.
class FrameStats {
  const FrameStats({required this.fps, required this.p90Milliseconds});

  /// Frames drawn a second, over the last second.
  final double fps;

  /// The 90th percentile of what a frame cost, in milliseconds.
  final double p90Milliseconds;

  static const FrameStats none = FrameStats(fps: 0, p90Milliseconds: 0);

  @override
  bool operator ==(Object other) =>
      other is FrameStats &&
      other.fps == fps &&
      other.p90Milliseconds == p90Milliseconds;

  @override
  int get hashCode => Object.hash(fps, p90Milliseconds);
}

/// The phone's side of the display (DESIGN.md 4.4, 9.2; CLAUDE.md 9): which mode
/// the light calls for, how bright the screen is, how the fidelity tier follows the
/// frames, and what a hot phone does. It joins the pieces the design system built
/// (`ModeController`, `TierGovernor`, `ScreenBrightness`) to the phone
/// (`DeviceFeatures`) and to Garage's choices (`AppSettings`).
///
/// - **Mode:** the ambient light sensor drives Daylight and Night with the spec's
///   thresholds and dwell; Garage can hold a mode. A phone without the sensor stays
///   in the normal mode.
/// - **Brightness:** maximum in Daylight, Night's lux curve with its floor, and the
///   phone's own in the normal mode.
/// - **Heat:** the battery temperature is read every [checkEvery]. Above [hotAt] the
///   phone-hot glyph shows (and Garage suggests moving it); above [tooHotAt] the
///   screen is dimmed and the tier is Lite at 30 fps, for good.
/// - **Tier:** the governor steps it down when frames run over budget; the cold open's
///   benchmark sets where it starts ([onDetected]); a tier held in Garage is kept.
///
/// Every call to the phone is allowed to fail: a phone that will not say its
/// temperature or brightness is a reason to carry on, not to show nothing.
class DisplayController {
  DisplayController({
    required this.device,
    required this.clock,
    required this.scheduler,
    required this.settings,
    this.hotAt = 45,
    this.tooHotAt = 50,
    this.checkEvery = const Duration(seconds: 30),
    this.watchFrames = true,
    this.watch = false,
  }) {
    _modes = ModeController(clock: clock)..setting = settings.modeSetting.value;
    _governor = TierGovernor(
      clock: clock,
      // A watch starts at Lite and is held to Balanced (DESIGN.md 16.9): a watch's
      // chip and battery are small, and the face looks the same in every tier.
      initial: TierDecision(
        tier: watch ? FidelityTier.lite : FidelityTier.balanced,
        fpsCap: null,
        p90Milliseconds: 0,
      ),
      config: GovernorConfig(hotCelsius: tooHotAt),
    )..pin(settings.tierPin.value);
  }

  final DeviceFeatures device;
  final Clock clock;
  final Scheduler scheduler;
  final AppSettings settings;

  /// The phone is called hot above this, in degrees Celsius.
  final double hotAt;

  /// The screen is dimmed and the tier held at Lite above this.
  final double tooHotAt;

  final Duration checkEvery;

  /// Whether to watch the engine's frame timings for the governor (off in tests).
  final bool watchFrames;

  /// The device is a watch: the tier starts at Lite and never goes above Balanced.
  final bool watch;

  late final ModeController _modes;
  late final TierGovernor _governor;
  FrameProbe? _probe;
  StreamSubscription<double>? _luxSubscription;
  ScheduledTask? _poll;
  bool _started = false;

  final ObservableValue<bool> _hot = ObservableValue(false);
  final ObservableValue<bool> _tooHot = ObservableValue(false);
  final ObservableValue<double?> _temperature = ObservableValue(null);
  final ObservableValue<FrameStats> _frameStats = ObservableValue(
    FrameStats.none,
  );
  final ObservableValue<double?> _luxValue = ObservableValue(null);
  double? _lux;
  final List<double> _costs = [];
  Duration? _statsSince;
  int? _sentBrightness;
  bool _sent = false;

  /// The mode in effect.
  Observable<TapeMode> get mode => _modes.mode;

  /// The fidelity tier and frame rate in effect.
  Observable<TierState> get tier => _governor.state;

  /// The phone is hot: show the glyph, and say so when parked.
  Observable<bool> get phoneHot => _hot;

  /// The phone is too hot: dimmed, and Lite at 30 fps.
  Observable<bool> get phoneTooHot => _tooHot;

  /// The frames a second and what the slow ones cost, for the debug overlay.
  Observable<FrameStats> get frameStats => _frameStats;

  /// The last ambient light reading, in lux, or null with no sensor.
  Observable<double?> get lux => _luxValue;

  /// The battery temperature, or null until one is read or if the phone has none.
  Observable<double?> get temperature => _temperature;

  /// Starts listening to the light, the battery, the frames and Garage.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    settings.modeSetting.addListener(_onSetting);
    settings.tierPin.addListener(_onPin);
    _modes.mode.addListener(_applyBrightness);
    _tooHot.addListener(_applyBrightness);

    if (watchFrames) {
      _probe = FrameProbe(onFrames)..start();
    }
    try {
      final support = await device.sensorSupport();
      if (support.ambientLight) {
        _luxSubscription = device.ambientLux.listen(
          _onLux,
          onError: (Object _) {},
        );
      }
    } on Object catch (error) {
      debugPrint('No light sensor: $error');
    }
    _poll = scheduler.runEvery(checkEvery, () => unawaited(_checkBattery()));
    await _checkBattery();
    _applyBrightness();
  }

  void _onSetting() {
    _modes.setting = settings.modeSetting.value;
    _applyBrightness();
  }

  void _onPin() => _governor.pin(settings.tierPin.value);

  void _onLux(double lux) {
    _lux = lux;
    _luxValue.value = lux;
    _modes.onLux(lux);
    // Night's brightness follows the light between the mode's changes too.
    if (_modes.mode.value == TapeMode.night) _applyBrightness();
  }

  /// Takes the cost, in milliseconds, of some frames that were just drawn: they go
  /// to the governor, and to the frame statistics.
  void onFrames(List<double> milliseconds) {
    _governor.onFrames(milliseconds);
    final now = clock.monotonic();
    _statsSince ??= now;
    _costs.addAll(milliseconds);
    final span = now - _statsSince!;
    if (span < const Duration(seconds: 1)) return;
    final seconds = span.inMicroseconds / 1e6;
    final sorted = List.of(_costs)..sort();
    final p90 = sorted.isEmpty
        ? 0.0
        : sorted[math.min(sorted.length - 1, (sorted.length * 0.9).floor())];
    _frameStats.value = FrameStats(
      fps: _costs.length / seconds,
      p90Milliseconds: p90,
    );
    _costs.clear();
    _statsSince = now;
  }

  /// The tier the cold open's frame timings chose.
  void onDetected(TierDecision decision) => _governor.onDetected(
    watch && decision.tier == FidelityTier.full
        ? TierDecision(
            tier: FidelityTier.balanced,
            fpsCap: decision.fpsCap ?? 60,
            p90Milliseconds: decision.p90Milliseconds,
          )
        : decision,
  );

  Future<void> _checkBattery() async {
    double? celsius;
    try {
      celsius = await device.batteryTemperatureCelsius();
    } on Object {
      celsius = null;
    }
    _temperature.value = celsius;
    _hot.value = celsius != null && celsius > hotAt;
    _tooHot.value = celsius != null && celsius > tooHotAt;
    _governor.onBatteryTemperature(celsius);
  }

  /// What the brightness should be now: the mode's, and no more than half when
  /// the phone is too hot.
  double? get brightness {
    var b = ScreenBrightness.forMode(_modes.mode.value, _lux);
    if (_tooHot.value) b = math.min(b ?? 1.0, _hotBrightness);
    return b;
  }

  static const double _hotBrightness = 0.5;

  void _applyBrightness() {
    final b = brightness;
    // Sent in fiftieths, so a drifting light does not send the phone a value a
    // frame.
    final step = b == null ? -1 : (b * 50).round();
    if (_sent && step == _sentBrightness) return;
    _sent = true;
    _sentBrightness = step;
    unawaited(_setBrightness(b));
  }

  Future<void> _setBrightness(double? level) async {
    try {
      await device.setBrightness(level);
    } on Object {
      // A phone that will not change its brightness keeps its own.
    }
  }

  Future<void> dispose() async {
    settings.modeSetting.removeListener(_onSetting);
    settings.tierPin.removeListener(_onPin);
    _modes.mode.removeListener(_applyBrightness);
    _tooHot.removeListener(_applyBrightness);
    _probe?.stop();
    _poll?.cancel();
    await _luxSubscription?.cancel();
    _modes.dispose();
    _governor.dispose();
    _hot.dispose();
    _tooHot.dispose();
    _temperature.dispose();
    _frameStats.dispose();
    _luxValue.dispose();
  }
}
