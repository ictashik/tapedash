// The ignition sequence on the Apex cluster (DESIGN.md 7.13), in real pixels:
// the flank comes in late, the horizon draws out and settles, the numerals
// roll up, and the finished cluster is the same one a live drive shows.
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
import 'package:tapedash/ui/pages/drive/apex_cluster.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../design/support/harness.dart';
import 'apex_cluster_test.dart' show heroInk;

const _width = 1600; // the suite's own 800x400 at dpr 2

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late VehicleState vehicle;
  late ObservableValue<ConnectionStatus> connection;
  late DriveSignals signals;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    connection = ObservableValue(ConnectionStatus.searching);
    signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: connection,
    );
  });

  tearDown(() {
    signals.dispose();
    motion.dispose();
    kit.dispose();
  });

  void feed() {
    final now = clock.monotonic();
    vehicle.ingest(Sensor.rpm, 900, at: now, receivedAt: now);
    vehicle.ingest(Sensor.speed, 62, at: now, receivedAt: now);
    vehicle.ingest(Sensor.coolant, 90, at: now, receivedAt: now);
  }

  var sinceFeed = 0;
  void run(Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      sinceFeed += step;
      if (sinceFeed >= 100000) {
        sinceFeed = 0;
        feed();
      }
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

  /// Non-void ink in a device-pixel rectangle.
  int ink(Uint32List frame, int x0, int y0, int x1, int y1) {
    var count = 0;
    for (var y = y0; y < y1; y++) {
      for (var x = x0; x < x1; x++) {
        final v = frame[y * _width + x];
        if (((v >> 24) & 0xFF) > 60 ||
            ((v >> 16) & 0xFF) > 60 ||
            ((v >> 8) & 0xFF) > 60) {
          count++;
        }
      }
    }
    return count;
  }

  // The coolant flank: the left of the frame, mid-height (driver on the right).
  int flankInk(Uint32List f) => ink(f, 60, 200, 300, 640);

  // The outer parts of the horizon, either side of the arc's own top.
  int horizonInk(Uint32List f) =>
      ink(f, 480, 4, 650, 40) + ink(f, 950, 4, 1120, 40);

  Future<void> start(WidgetTester tester) async {
    setWindow(tester, const Size(800, 400));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: ApexCluster(signals: signals, width: 800, height: 400),
      ),
    );
    feed();
    connection.value = ConnectionStatus.connected;
  }

  testWidgets('the flank comes in after the horizon starts, not before', (
    tester,
  ) async {
    await start(tester);

    run(const Duration(milliseconds: 300));
    await tester.pump();
    expect(flankInk(await pixels(tester)), 0, reason: 'starts at 600 ms');

    run(const Duration(milliseconds: 2000));
    await tester.pump();
    expect(flankInk(await pixels(tester)), greaterThan(500));
  });

  testWidgets('the horizon is there mid-sequence, and gone once it settles', (
    tester,
  ) async {
    await start(tester);

    run(const Duration(milliseconds: 800));
    await tester.pump();
    expect(horizonInk(await pixels(tester)), greaterThan(20));

    run(const Duration(milliseconds: 3000));
    await tester.pump();
    final f = await pixels(tester);
    expect(
      horizonInk(f),
      0,
      reason:
          'a CVT at 900 rpm has no shift light: nothing is left of it, '
          'not even the edge segment a fast fall from redline passes',
    );
  });

  testWidgets('the hero rolls up from 0 to the live speed', (tester) async {
    await start(tester);

    run(const Duration(milliseconds: 100));
    await tester.pump();
    final early = heroInk(await pixels(tester));

    run(const Duration(milliseconds: 2000));
    await tester.pump();
    final settled = heroInk(await pixels(tester));

    expect(early, greaterThan(0), reason: 'a 0, not a blank');
    expect(early, lessThan(settled * 0.75), reason: 'one digit, then two');
    expect(signals.speed.value, closeTo(62, 0.5));
  });

  testWidgets('renders throughout with no exception', (tester) async {
    await start(tester);
    for (var i = 0; i < 40; i++) {
      run(const Duration(milliseconds: 40));
      await tester.pump();
    }
    expect(tester.takeException(), isNull);
  });
}
