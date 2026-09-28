// A first look at the road view. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/components/road_view.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/motion/smoothing_pipeline.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/vehicle/reading.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<void> shot(
    WidgetTester tester,
    String name, {
    double speed = 0,
    double rpm = 1500,
    double longAccel = 0,
    double latAccel = 0,
    TapeMode mode = TapeMode.normal,
    Duration settle = const Duration(seconds: 2),
  }) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));

    SmoothedSignal sig(double v, SpringSpec spring) {
      final s = SmoothedSignal(motion: motion, clock: clock, spring: spring);
      s.ingest(
        Reading(value: v, at: clock.monotonic(), receivedAt: clock.monotonic()),
      );
      return s;
    }

    final speedSig = sig(speed, TapeSprings.gauge);
    final rpmSig = sig(rpm, TapeSprings.gauge);
    final longSig = sig(longAccel, TapeSprings.needle);
    final latSig = sig(latAccel, TapeSprings.needle);

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion, mode: mode),
        child: TapeBackdrop(
          child: RoadView(
            speed: speedSig,
            rpm: rpmSig,
            maxRpm: 6500,
            longitudinalAcceleration: longSig,
            lateralAcceleration: latSig,
            width: 800,
            height: 400,
          ),
        ),
      ),
    );
    motion.advance(settle);
    await tester.pump();
    await capturePng(tester, name);
    speedSig.dispose();
    rpmSig.dispose();
    longSig.dispose();
    latSig.dispose();
    motion.dispose();
    kit.dispose();
  }

  testWidgets('standing still', (tester) async {
    await shot(tester, 'road-stopped', speed: 0, rpm: 800);
  }, skip: !enabled);

  testWidgets('cruising, daylight', (tester) async {
    await shot(tester, 'road-cruise', speed: 70, rpm: 2200);
  }, skip: !enabled);

  testWidgets('hard braking', (tester) async {
    await shot(tester, 'road-braking', speed: 40, rpm: 1800, longAccel: -4);
  }, skip: !enabled);

  testWidgets('cornering', (tester) async {
    await shot(tester, 'road-cornering', speed: 50, rpm: 2400, latAccel: 4);
  }, skip: !enabled);

  testWidgets('highway speed, streaks', (tester) async {
    await shot(tester, 'road-highway', speed: 120, rpm: 3200);
  }, skip: !enabled);

  testWidgets('night mode', (tester) async {
    await shot(
      tester,
      'road-night',
      speed: 60,
      rpm: 2000,
      mode: TapeMode.night,
    );
  }, skip: !enabled);
}
