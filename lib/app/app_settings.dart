import 'package:flutter/foundation.dart';

import '../coach/coach_thresholds.dart';
import '../core/key_value_store.dart';
import '../ui/design/fidelity/fidelity_tier.dart';
import '../ui/design/motion/ignition_sequence.dart';
import '../ui/design/theme/mode_controller.dart' show ModeSetting;
import '../ui/design/theme/palette.dart' show DriverSide;
import '../ui/design/tokens/colors.dart' show HudColor;
import '../ui/design/tokens/livery.dart';
import '../ui/hud/hud_settings.dart';

/// The Garage's Gentle, Normal and Sporty presets for the coach's thresholds
/// (DESIGN.md 7.8).
enum CoachPreset {
  gentle('Gentle'),
  normal('Normal'),
  sporty('Sporty');

  const CoachPreset(this.label);

  final String label;

  CoachThresholds get thresholds => switch (this) {
    gentle => CoachThresholds.gentle,
    normal => CoachThresholds.normal,
    sporty => CoachThresholds.sporty,
  };
}

/// Everything the user sets that is not about the car's fuel or the price (those
/// are `AppServices`'): the look, the HUD, the coach and the demo. Each value is
/// a [ValueNotifier] the screens listen to, and each change is written to the
/// phone's settings at once (CLAUDE.md 5: `shared_preferences`; defaults over
/// settings, so nothing here has to be set).
class AppSettings {
  AppSettings(this._store, {HudSettings? hud}) : hud = hud ?? HudSettings();

  static const _liveryKey = 'display_livery';
  static const _driverKey = 'display_driver_side';
  static const _ignitionKey = 'display_ignition';
  static const _reduceKey = 'display_reduce_motion';
  static const _tierKey = 'display_fidelity';
  static const _modeKey = 'display_mode';
  static const _clusterKey = 'display_cluster';
  static const _presetKey = 'coach_preset';
  static const _limitKey = 'coach_speed_limit';
  static const _scenarioKey = 'demo_scenario';
  static const _profileKey = 'demo_profile';
  static const _onboardedKey = 'onboarded';
  static const _hudColorKey = 'hud_color';
  static const _hudLayoutKey = 'hud_layout';
  static const _hudFlipHKey = 'hud_flip_h';
  static const _hudFlipVKey = 'hud_flip_v';
  static const _hudPositionKey = 'hud_position';
  static const _hudScaleKey = 'hud_scale';
  static const _hudActiveKey = 'hud_active';

  final KeyValueStore _store;

  /// The HUD's settings (DESIGN.md 8), saved as they change.
  final HudSettings hud;

  final ValueNotifier<LiveryId> livery = ValueNotifier(LiveryId.ion);
  final ValueNotifier<DriverSide> driverSide = ValueNotifier(DriverSide.right);
  final ValueNotifier<IgnitionMode> ignition = ValueNotifier(IgnitionMode.full);
  final ValueNotifier<bool> reduceMotion = ValueNotifier(false);

  /// Follow the light sensor for Daylight and Night, or hold one mode (DESIGN.md
  /// 4.4).
  final ValueNotifier<ModeSetting> modeSetting = ValueNotifier(
    ModeSetting.auto,
  );

  /// The fidelity tier held by hand, or null for automatic (DESIGN.md 9.2).
  final ValueNotifier<FidelityTier?> tierPin = ValueNotifier(null);

  /// The Drive cluster opened on, 0 to 4 (Apex, Tape, Minimal, Telemetry, Road).
  final ValueNotifier<int> cluster = ValueNotifier(0);
  final ValueNotifier<CoachPreset> coachPreset = ValueNotifier(
    CoachPreset.normal,
  );
  final ValueNotifier<double> speedLimitKmh = ValueNotifier(100);
  final ValueNotifier<String> demoScenario = ValueNotifier('city_stop_go');
  final ValueNotifier<String> demoProfile = ValueNotifier('');

  /// Whether the choice at first launch has been made, so it is not asked again.
  final ValueNotifier<bool> onboarded = ValueNotifier(false);

  /// The coach's thresholds: the preset, with the user's speed threshold.
  CoachThresholds get thresholds =>
      coachPreset.value.thresholds.copyWith(speedLimitKmh: speedLimitKmh.value);

  Future<void> load() async {
    T pick<T extends Enum>(List<T> values, String? name, T fallback) =>
        values.firstWhere((v) => v.name == name, orElse: () => fallback);

    livery.value = pick(
      [LiveryId.ion, LiveryId.ember, LiveryId.vfd, LiveryId.mono],
      await _store.getString(_liveryKey),
      LiveryId.ion,
    );
    driverSide.value = pick(
      DriverSide.values,
      await _store.getString(_driverKey),
      DriverSide.right,
    );
    ignition.value = pick(
      IgnitionMode.values,
      await _store.getString(_ignitionKey),
      IgnitionMode.full,
    );
    reduceMotion.value = await _store.getBool(_reduceKey) ?? false;
    modeSetting.value = pick(
      ModeSetting.values,
      await _store.getString(_modeKey),
      ModeSetting.auto,
    );
    final tier = await _store.getString(_tierKey);
    tierPin.value = FidelityTier.values
        .where((t) => t.name == tier)
        .firstOrNull;
    cluster.value = ((await _store.getDouble(_clusterKey)) ?? 0).round().clamp(
      0,
      4,
    );
    coachPreset.value = pick(
      CoachPreset.values,
      await _store.getString(_presetKey),
      CoachPreset.normal,
    );
    speedLimitKmh.value = await _store.getDouble(_limitKey) ?? 100;
    demoScenario.value = await _store.getString(_scenarioKey) ?? 'city_stop_go';
    demoProfile.value = await _store.getString(_profileKey) ?? '';
    onboarded.value = await _store.getBool(_onboardedKey) ?? false;

    hud
      ..color = pick(
        HudColor.values,
        await _store.getString(_hudColorKey),
        HudColor.green,
      )
      ..layout = pick(
        HudLayout.values,
        await _store.getString(_hudLayoutKey),
        HudLayout.drive,
      )
      ..flipHorizontal = await _store.getBool(_hudFlipHKey) ?? true
      ..flipVertical = await _store.getBool(_hudFlipVKey) ?? false
      ..verticalPosition = await _store.getDouble(_hudPositionKey) ?? 0
      ..scale = await _store.getDouble(_hudScaleKey) ?? 1
      ..active = await _store.getBool(_hudActiveKey) ?? false;
    _bind();
  }

  bool _bound = false;

  /// Writes each change as it happens.
  void _bind() {
    if (_bound) return;
    _bound = true;
    livery.addListener(() => _store.setString(_liveryKey, livery.value.name));
    driverSide.addListener(
      () => _store.setString(_driverKey, driverSide.value.name),
    );
    ignition.addListener(
      () => _store.setString(_ignitionKey, ignition.value.name),
    );
    reduceMotion.addListener(
      () => _store.setBool(_reduceKey, reduceMotion.value),
    );
    modeSetting.addListener(
      () => _store.setString(_modeKey, modeSetting.value.name),
    );
    tierPin.addListener(() {
      final t = tierPin.value;
      if (t == null) {
        _store.remove(_tierKey);
      } else {
        _store.setString(_tierKey, t.name);
      }
    });
    cluster.addListener(
      () => _store.setDouble(_clusterKey, cluster.value.toDouble()),
    );
    coachPreset.addListener(
      () => _store.setString(_presetKey, coachPreset.value.name),
    );
    speedLimitKmh.addListener(
      () => _store.setDouble(_limitKey, speedLimitKmh.value),
    );
    demoScenario.addListener(
      () => _store.setString(_scenarioKey, demoScenario.value),
    );
    demoProfile.addListener(
      () => _store.setString(_profileKey, demoProfile.value),
    );
    onboarded.addListener(() => _store.setBool(_onboardedKey, onboarded.value));
    hud.addListener(() {
      _store.setString(_hudColorKey, hud.color.name);
      _store.setString(_hudLayoutKey, hud.layout.name);
      _store.setBool(_hudFlipHKey, hud.flipHorizontal);
      _store.setBool(_hudFlipVKey, hud.flipVertical);
      _store.setDouble(_hudPositionKey, hud.verticalPosition);
      _store.setDouble(_hudScaleKey, hud.scale);
      // The last mode is remembered (DESIGN.md 8): whether the HUD is up.
      _store.setBool(_hudActiveKey, hud.active);
    });
  }

  void dispose() {
    for (final n in [
      livery,
      driverSide,
      ignition,
      reduceMotion,
      tierPin,
      cluster,
      coachPreset,
      speedLimitKmh,
      demoScenario,
      demoProfile,
      onboarded,
    ]) {
      n.dispose();
    }
    hud.dispose();
  }
}
