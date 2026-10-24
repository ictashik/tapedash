// A first look at the watch's faces, against a real SimDrive. Skipped unless
// TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/watch.dart';
import 'package:tapedash/ui/pages/watch/watch_reel.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../support/sim_shell.dart';
import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<void> run(
    WidgetTester tester,
    ManualMotionClock motion,
    FakeClock clock,
    double seconds,
  ) async {
    for (var i = 0; i < seconds * 60; i++) {
      motion.tick(1 / 60);
      clock.advance(const Duration(microseconds: 16667));
      if (i % 20 == 0) await tester.pump();
    }
    await tester.pump();
  }

  for (final d in [198.0, 225.0, 240.0]) {
    testWidgets('the watch faces at $d', (tester) async {
      setWindow(tester, Size(d, d));
      final kit = TapeRenderKit();
      final motion = ManualMotionClock();
      final clock = FakeClock();
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(
            livery: Liveries.ion.withNumeralWeightAtLeast(
              TapeWatch.minNumeralWeight,
            ),
          ),
          child: SimWatchShell(
            clock: clock,
            scheduler: clock,
            scenario: 'city_stop_go',
          ),
        ),
      );
      final shell = tester.state<SimWatchShellState>(
        find.byType(SimWatchShell),
      );
      // Drive until the car is moving fast.
      for (var s = 0; s < 400; s++) {
        await run(tester, motion, clock, 1);
        if ((shell.drive.vehicle.speed.value?.value ?? 0) > 40) break;
      }
      await capturePng(tester, 'watch-$d-1-drive');
      final reel = tester.state<WatchReelState>(find.byType(WatchReel));
      reel.goTo(1);
      await run(tester, motion, clock, 2);
      await capturePng(tester, 'watch-$d-2-money');
      reel.goTo(0);
      // Then until it has stopped and settled into Parked.
      for (var s = 0; s < 600; s++) {
        await run(tester, motion, clock, 1);
        if (shell.drive.vehicle.mode.value == DrivingMode.parked) break;
      }
      await run(tester, motion, clock, 3);
      await capturePng(tester, 'watch-$d-3-drive-parked');
      reel.goTo(1);
      await run(tester, motion, clock, 2);
      await capturePng(tester, 'watch-$d-4-money-parked');
      reel.goTo(2);
      await run(tester, motion, clock, 2);
      await capturePng(tester, 'watch-$d-5-where');
      reel.goTo(3);
      await run(tester, motion, clock, 2);
      await capturePng(tester, 'watch-$d-6-menu-cover');
      await tester.tapAt(Offset(d / 2, d / 2));
      await run(tester, motion, clock, 1);
      await capturePng(tester, 'watch-$d-7-menu');
      kit.dispose();
      motion.dispose();
    }, skip: !enabled);
  }
}
