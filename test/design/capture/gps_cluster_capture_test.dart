// A first look at the GPS screen, against the simulator's car driving its route
// (the receiver is the simulated one). Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/location/gps_drive.dart';
import 'package:tapedash/location/sim_location_source.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/gps_cluster.dart';
import 'package:tapedash/ui/pages/drive/gps_signals.dart';

import '../../support/fake_location.dart';
import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<void> shot(
    WidgetTester tester,
    String name, {
    required Size size,
    required Future<void> Function(FakeClock clock, ManualMotionClock motion)
    play,
    required GpsDriveFactory make,
  }) async {
    setWindow(tester, size);
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final gps = make(clock);
    final signals = GpsSignals(
      gps: gps,
      motion: motion,
      clock: clock,
      scheduler: clock,
    );
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: GpsCluster(
            signals: signals,
            width: size.width,
            height: size.height,
            onAllowLocation: () {},
          ),
        ),
      ),
    );
    await gps.start();
    await play(clock, motion);
    await tester.pump();
    await capturePng(tester, name);
    signals.dispose();
    // Not awaited: tidying a stream stalls in a widget test's fake-async zone.
    unawaited(gps.dispose());
    motion.dispose();
    kit.dispose();
  }

  void run(FakeClock clock, ManualMotionClock motion, int seconds) {
    // Most of the drive at once, then the last few seconds frame by frame.
    if (seconds > 5) clock.advance(Duration(seconds: seconds - 4));
    for (var i = 0; i < (seconds > 5 ? 4 : seconds) * 60; i++) {
      motion.tick(1 / 60);
      clock.advance(const Duration(microseconds: 16667));
    }
  }

  testWidgets('driving the city route', (tester) async {
    late SimulatedCar car;
    for (final size in [const Size(800, 360)]) {
      await shot(
        tester,
        'gps-cluster-city-${size.width.toInt()}',
        size: size,
        make: (clock) {
          car = SimulatedCar(
            scenario: DriveScenarios.cityStopGo,
            scheduler: clock,
          )..start();
          return GpsDrive(
            location: SimLocationSource(
              car: car,
              scheduler: clock,
              clock: clock,
            ),
            clock: clock,
            scheduler: clock,
          );
        },
        play: (clock, motion) async => run(clock, motion, 60),
      );
      car.stop();
    }
  }, skip: !enabled);

  testWidgets('the words before a speed', (tester) async {
    for (final (name, permission, unavailable) in [
      ('searching', true, false),
      ('permission', false, false),
      ('nogps', true, true),
    ]) {
      final location = FakeLocation(
        permission: permission,
        unavailable: unavailable,
      );
      await shot(
        tester,
        'gps-cluster-$name',
        size: const Size(720, 360),
        make: (clock) =>
            GpsDrive(location: location, clock: clock, scheduler: clock),
        play: (clock, motion) async => run(clock, motion, 2),
      );
      unawaited(location.close());
    }
  }, skip: !enabled);
}

typedef GpsDriveFactory = GpsDrive Function(FakeClock clock);
