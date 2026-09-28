// The Minimal cluster (DESIGN.md 7.3.3): renders against real DriveSignals
// with no exception, the RPM line's length follows RPM through the tach
// default max, and the hero reads centred.
import 'dart:typed_data';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/drive/minimal_cluster.dart';
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

  Future<void> show(WidgetTester tester) async {
    setWindow(tester, const Size(800, 400));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: MinimalCluster(signals: signals, width: 800, height: 400),
      ),
    );
  }

  testWidgets('renders real vehicle data with no exception', (tester) async {
    await show(tester);
    ingest(Sensor.rpm, 2200);
    ingest(Sensor.speed, 62);
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

  group('RpmLinePainter.shareFor (DESIGN.md 7.3.3)', () {
    test('0 at 0 rpm, proportional in between, capped at the max', () {
      expect(RpmLinePainter.shareFor(0, 7000), 0);
      expect(RpmLinePainter.shareFor(3500, 7000), 0.5);
      expect(RpmLinePainter.shareFor(7000, 7000), 1);
      // A value past the max (an over-read, or a higher-redline profile
      // feeding a line sized for this one) must not overrun the line.
      expect(RpmLinePainter.shareFor(7500, 7000), 1);
      // A max of 0 (a profile with no range at all yet) draws nothing
      // rather than dividing by zero.
      expect(RpmLinePainter.shareFor(100, 0), 0);
    });
  });

  testWidgets('the RPM line is centred and its length follows the rpm', (
    tester,
  ) async {
    // accent.core in the byte order the pixel tests read back (0xRRGGBBAA,
    // the convention the Road cluster's test writes down): the line's own
    // solid colour. The shift horizon's segments are the same hue but sit
    // in the top band, outside the rows scanned here.
    const accentCoreArgb = 0x5CE1FFFF;

    await show(tester);
    ingest(Sensor.rpm, 3500); // half of TapeTach.defaultMaxRpm.
    ingest(Sensor.speed, 60);
    run(const Duration(seconds: 3));
    await tester.pump();

    final frame = await pixels(tester);
    final width = (800 * tester.view.devicePixelRatio).round();
    final height = (400 * tester.view.devicePixelRatio).round();

    // Scan the rows below the status strip and its horizon band: the
    // line's rows are the only ones with the exact accent.core there. The
    // line sits low -- the hero numeral's own box is much taller than its
    // ink (the same property the Apex cluster's label placement rides on) --
    // so the band runs to the frame's bottom edge.
    var minX = width, maxX = -1;
    var rows = 0;
    for (var y = (height * 0.12).round(); y < height; y++) {
      var rowHit = false;
      for (var x = 0; x < width; x++) {
        if (frame[y * width + x] == accentCoreArgb) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          rowHit = true;
        }
      }
      if (rowHit) rows++;
    }
    expect(rows, greaterThan(0), reason: 'no RPM line drawn at all');
    expect(
      rows,
      lessThan(20),
      reason:
          'the line should be thin; a band this '
          'tall means something else drew accent.core down here too',
    );

    // 3500 of 7000 at the 0.25W extent: half of 0.25 x 800 = 100 logical
    // wide, centred. Device pixels at the test's 2x DPR.
    final dpr = tester.view.devicePixelRatio;
    expect(minX / dpr, closeTo(400 - 50, 3));
    expect(maxX / dpr, closeTo(400 + 50, 3));
  });

  testWidgets('the hero reads centred in the frame', (tester) async {
    await show(tester);
    ingest(Sensor.speed, 81);
    ingest(Sensor.rpm, 2200);
    run(const Duration(seconds: 3));
    await tester.pump();

    final frame = await pixels(tester);
    final width = (800 * tester.view.devicePixelRatio).round();
    final height = (400 * tester.view.devicePixelRatio).round();

    // The numeral is the only near-white element in the centre zone's
    // upper half (the status strip's glyphs sit above, the RPM line is
    // accent, not white).
    var minX = width, maxX = -1;
    for (var y = (height * 0.25).round(); y < height * 0.70; y++) {
      for (var x = 0; x < width; x++) {
        final v = frame[y * width + x];
        final r = (v >> 24) & 0xFF;
        final g = (v >> 16) & 0xFF;
        final b = (v >> 8) & 0xFF;
        if (r > 200 && g > 200 && b > 200) {
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
        }
      }
    }
    final centre = (minX + maxX) / 2;
    // The numeral's ink is centred by CenteredNumeral; the tolerance is a
    // few pixels, not an eyeball's impression of a narrow digit's side
    // bearing (which is exactly what made this worth a measured test).
    expect(centre / tester.view.devicePixelRatio, closeTo(400, 4));
  });

  testWidgets('parked, the hero shrinks to primary size (DESIGN.md 7.2)', (
    tester,
  ) async {
    await show(tester);
    ingest(Sensor.speed, 60); // the car moves: motion
    ingest(Sensor.rpm, 2200);
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
/// The band scanned is the numeral's own at either scale, above the RPM
/// line: the middle of the width and the centre zone's height, which the
/// status strip's glyphs and the line's own accent stay outside of.
/// 0 when no ink drew at all.
int heroInk(Uint32List frame) {
  const width = 1600, height = 800; // the suite's own 800x400 at dpr 2
  final xLo = (width * 0.35).round(), xHi = (width * 0.65).round();
  final yLo = (height * 0.20).round(), yHi = (height * 0.80).round();
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
