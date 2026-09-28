// The Apex cluster (DESIGN.md 7.3.1): renders against real DriveSignals with
// no exception, and the coolant gauge moves to the flank away from the
// driver.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/palette.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/apex_cluster.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late VehicleState vehicle;
  late DriveSignals signals;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: ObservableValue(ConnectionStatus.connected),
    );
  });

  tearDown(() {
    signals.dispose();
    motion.dispose();
    kit.dispose();
  });

  void ingest(Sensor sensor, double value) {
    final now = clock.monotonic();
    vehicle.ingest(sensor, value, at: now, receivedAt: now);
  }

  void run(Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
  }

  Future<Uint32List> pixels(WidgetTester tester) async {
    final image = await renderImage(tester);
    late ByteData data;
    await tester.runAsync(() async => data = (await image.toByteData())!);
    return Uint32List.fromList([
      for (var i = 0; i < image.width * image.height; i++)
        data.getUint32(i * 4),
    ]);
  }

  Future<void> show(
    WidgetTester tester, {
    DriverSide side = DriverSide.right,
  }) async {
    setWindow(tester, const Size(800, 400));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion, driverSide: side),
        child: ApexCluster(signals: signals, width: 800, height: 400),
      ),
    );
  }

  testWidgets('renders real vehicle data with no exception', (tester) async {
    await show(tester);
    ingest(Sensor.rpm, 2200);
    ingest(Sensor.speed, 62);
    ingest(Sensor.coolant, 91);
    run(const Duration(seconds: 2));
    await tester.pump();

    expect(tester.takeException(), isNull);
  });

  testWidgets('renders with no reading at all yet, with no exception', (
    tester,
  ) async {
    await show(tester);
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('the coolant gauge moves to the flank away from the driver', (
    tester,
  ) async {
    // accent.deep (0x1296FFFF, Ion), the fill's cold-end colour and a
    // distinctive fingerprint no other Apex element uses: not the tach
    // arc's segments (accent.core), not the status strip glyphs.
    const accentDeepArgb = 0x1296FFFF;

    Future<double> coolantCentroidX(DriverSide side) async {
      await show(tester, side: side);
      // Within the gauge's own 80-100 normal band (ApexCluster's own
      // config): the accent.deep-to-accent.core gradient fill, not the
      // solid caution/critical a below/above-band value would give.
      ingest(Sensor.coolant, 90);
      run(const Duration(seconds: 2));
      await tester.pump();
      final frame = await pixels(tester);
      final width = (800 * tester.view.devicePixelRatio).round();
      var sumX = 0, count = 0;
      for (var i = 0; i < frame.length; i++) {
        if (frame[i] == accentDeepArgb) {
          sumX += i % width;
          count++;
        }
      }
      expect(count, greaterThan(0), reason: 'no coolant fill drawn at all');
      return sumX / count;
    }

    final withDriverOnRight = await coolantCentroidX(DriverSide.right);
    final withDriverOnLeft = await coolantCentroidX(DriverSide.left);

    // Driver on the right -> coolant (the other flank) is on the left, and
    // vice versa.
    expect(withDriverOnRight, lessThan(400));
    expect(withDriverOnLeft, greaterThan(400));
  });

  testWidgets('parked, the hero shrinks to primary size (DESIGN.md 7.2)', (
    tester,
  ) async {
    await show(tester);
    ingest(Sensor.speed, 40); // the car moves: motion
    ingest(Sensor.rpm, 900);
    run(const Duration(seconds: 2));
    await tester.pump();
    expect(signals.mode.value, DrivingMode.motion);
    final motionInk = heroInk(await pixels(tester));

    // Parked: a stop, the 5 s dwell, then the share's own reveal; the hero
    // is at TypeScale.primary's share of its motion size.
    ingest(Sensor.speed, 0);
    run(const Duration(seconds: 6));
    await tester.pump();
    run(const Duration(milliseconds: 900));
    await tester.pump();
    expect(signals.mode.value, DrivingMode.parked);
    final parkedInk = heroInk(await pixels(tester));

    expect(parkedInk, greaterThan(50), reason: 'the hero is still there');
    expect(
      parkedInk,
      lessThan(motionInk * 0.45),
      reason: 'shrunken well under half of the motion ink',
    );
  });
}

/// The count of the centre zone's own ink, in device pixels: any px
/// brighter than the void counts, so the count is the numeral's reach
/// wherever its tone sits that moment, not an exact colour's match.
/// The band scanned is the numeral's own at either scale: the middle of
/// the width and the centre zone's height, which the tach's arc, needle
/// and trail, the status strip's glyphs and the flanks' gauge all sit
/// outside of. 0 when no ink drew at all.
int heroInk(Uint32List frame) {
  const width = 1600, height = 800; // the suite's own 800x400 at dpr 2
  final xLo = (width * 0.35).round(), xHi = (width * 0.65).round();
  final yLo = (height * 0.20).round(), yHi = (height * 0.90).round();
  var count = 0;
  for (var y = yLo; y < yHi; y++) {
    for (var x = xLo; x < xHi; x++) {
      final v = frame[y * width + x];
      final r = (v >> 24) & 0xFF;
      final g = (v >> 16) & 0xFF;
      final b = (v >> 8) & 0xFF;
      if (r > 60 && g > 60 && b > 60) count++;
    }
  }
  return count;
}
