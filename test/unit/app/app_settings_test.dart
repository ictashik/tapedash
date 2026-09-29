import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_settings.dart';
import 'package:tapedash/coach/coach_thresholds.dart';
import 'package:tapedash/core/key_value_store.dart';
import 'package:tapedash/ui/design/fidelity/fidelity_tier.dart';
import 'package:tapedash/ui/design/motion/ignition_sequence.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/tokens/colors.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/hud/hud_settings.dart';

void main() {
  test('the defaults are the design\'s', () async {
    final s = AppSettings(MemoryKeyValueStore());
    await s.load();
    expect(s.livery.value, LiveryId.ion);
    expect(s.driverSide.value, DriverSide.right);
    expect(s.ignition.value, IgnitionMode.full);
    expect(s.reduceMotion.value, isFalse);
    expect(s.tierPin.value, isNull);
    expect(s.cluster.value, 0);
    expect(s.coachPreset.value, CoachPreset.normal);
    expect(s.speedLimitKmh.value, 100);
    expect(s.onboarded.value, isFalse);
    expect(s.hud.flipHorizontal, isTrue);
    expect(s.hud.active, isFalse);
  });

  test('every change is saved and comes back after a restart', () async {
    final store = MemoryKeyValueStore();
    final s = AppSettings(store);
    await s.load();
    s.livery.value = LiveryId.ember;
    s.driverSide.value = DriverSide.left;
    s.ignition.value = IgnitionMode.subtle;
    s.reduceMotion.value = true;
    s.tierPin.value = FidelityTier.lite;
    s.cluster.value = 3;
    s.coachPreset.value = CoachPreset.sporty;
    s.speedLimitKmh.value = 80;
    s.demoScenario.value = 'highway_cruise';
    s.demoProfile.value = 'petrol_cvt_map';
    s.onboarded.value = true;
    s.hud
      ..color = HudColor.amber
      ..layout = HudLayout.money
      ..flipHorizontal = false
      ..flipVertical = true
      ..verticalPosition = 0.4
      ..scale = 1.2
      ..active = true;
    await Future<void>.delayed(Duration.zero);

    final again = AppSettings(store);
    await again.load();
    expect(again.livery.value, LiveryId.ember);
    expect(again.driverSide.value, DriverSide.left);
    expect(again.ignition.value, IgnitionMode.subtle);
    expect(again.reduceMotion.value, isTrue);
    expect(again.tierPin.value, FidelityTier.lite);
    expect(again.cluster.value, 3);
    expect(again.coachPreset.value, CoachPreset.sporty);
    expect(again.speedLimitKmh.value, 80);
    expect(again.demoScenario.value, 'highway_cruise');
    expect(again.demoProfile.value, 'petrol_cvt_map');
    expect(again.onboarded.value, isTrue);
    expect(again.hud.color, HudColor.amber);
    expect(again.hud.layout, HudLayout.money);
    expect(again.hud.flipHorizontal, isFalse);
    expect(again.hud.flipVertical, isTrue);
    expect(again.hud.verticalPosition, 0.4);
    expect(again.hud.scale, 1.2);
    expect(again.hud.active, isTrue);
  });

  test('clearing the pinned tier goes back to automatic', () async {
    final store = MemoryKeyValueStore();
    final s = AppSettings(store);
    await s.load();
    s.tierPin.value = FidelityTier.full;
    await Future<void>.delayed(Duration.zero);
    s.tierPin.value = null;
    await Future<void>.delayed(Duration.zero);
    final again = AppSettings(store);
    await again.load();
    expect(again.tierPin.value, isNull);
  });

  test(
    'the coach thresholds are the preset with the user\'s speed limit',
    () async {
      final s = AppSettings(MemoryKeyValueStore());
      await s.load();
      s.coachPreset.value = CoachPreset.gentle;
      s.speedLimitKmh.value = 90;
      expect(
        s.thresholds.hardAccelerationMs2,
        CoachThresholds.gentle.hardAccelerationMs2,
      );
      expect(s.thresholds.speedLimitKmh, 90);
    },
  );

  test('a garbled value falls back to the default', () async {
    final store = MemoryKeyValueStore();
    await store.setString('display_livery', 'plaid');
    await store.setDouble('display_cluster', 99);
    final s = AppSettings(store);
    await s.load();
    expect(s.livery.value, LiveryId.ion);
    expect(s.cluster.value, 4);
  });
}
