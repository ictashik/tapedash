// The Road cluster (DESIGN.md 7.3.5): renders against real DriveSignals with
// no exception, the horizon RPM bar maps rpm through the tach's default max
// (the cluster's own choice, DESIGN.md 6.11), and night mode adds the
// headlight cone the road view draws (DESIGN.md 6.11) through the cluster's
// wiring too.
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
import 'package:tapedash/ui/design/tokens/road_view.dart';
import 'package:tapedash/ui/design/tokens/tach.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/drive/road_cluster.dart';
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
    TapeMode mode = TapeMode.normal,
  }) async {
    setWindow(tester, const Size(800, 400));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion, mode: mode),
        child: RoadCluster(signals: signals, width: 800, height: 400),
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

  testWidgets(
    'the horizon RPM bar maps the cluster rpm through the tach default max',
    (tester) async {
      // accent.core (Ion, R=0x5C G=0xE1 B=0xFF), the fill's own solid
      // colour, in the byte order `toByteData` reads back on this platform
      // (0xRRGGBBAA, the convention every pixel test here follows -- the
      // Apex cluster test's 0x1296FFFF accent.deep is the same convention).
      // Nothing else in the scene draws it exactly: the car's rim-light
      // hint is the same hue at 80% alpha (blended), the centre dashes are
      // accent.deep.
      const accentCoreArgb = 0x5CE1FFFF;

      Future<double> barFillShare() async {
        await show(tester);
        ingest(Sensor.rpm, 2100);
        ingest(Sensor.speed, 80);
        run(const Duration(seconds: 3));
        await tester.pump();
        final frame = await pixels(tester);
        final width = (800 * tester.view.devicePixelRatio).round();
        final height = (400 * tester.view.devicePixelRatio).round();

        // The bar is a rectangle along the horizon (TapeRoadView.horizonShare
        // of the height, a few pixels thick). Scan the band around it.
        final horizonY = (height * TapeRoadView.horizonShare).round();
        final bandTop = horizonY - 12;
        final bandBottom = horizonY + 12;
        var rightmost = -1;
        var count = 0;
        for (var y = bandTop; y <= bandBottom; y++) {
          for (var x = 0; x < width; x++) {
            if (frame[y * width + x] == accentCoreArgb) {
              if (x > rightmost) rightmost = x;
              count++;
            }
          }
        }
        expect(count, greaterThan(0), reason: 'no RPM bar drawn at all');
        return rightmost / width;
      }

      final share = await barFillShare();
      // 2100 of TapeTach.defaultMaxRpm (7000): 30%. The spring has settled
      // by 3 s, and the sweep starts at the left edge, so the bar's
      // rightmost lit pixel is the fill's end. A few percent loose, so that
      // antialiasing at the fill's end does not flake the test.
      expect(share, closeTo(2100 / TapeTach.defaultMaxRpm, 0.04));
    },
  );

  testWidgets('night mode adds the headlight cone to the road', (tester) async {
    // A patch of plain road below the car's base and clear of the centre
    // dashes, the edges and the streak threshold: on the daylight frame it
    // is void alone; on the night frame the cone's radial gradient (centred
    // at the frame's bottom centre) adds inkBright there.
    Future<double> patchBrightness() async {
      final frame = await pixels(tester);
      final width = (800 * tester.view.devicePixelRatio).round();
      final dpr = tester.view.devicePixelRatio;
      final x0 = (300 * dpr).round();
      final x1 = (360 * dpr).round();
      final y0 = (392 * dpr).round();
      final y1 = (398 * dpr).round();
      var sum = 0;
      var count = 0;
      for (var y = y0; y < y1; y++) {
        for (var x = x0; x < x1; x++) {
          final argb = frame[y * width + x];
          // Red channel (top byte in the 0xRRGGBBAA packing): inkBright
          // lifts all of them.
          sum += (argb >> 24) & 0xFF;
          count++;
        }
      }
      return sum / count;
    }

    await show(tester, mode: TapeMode.normal);
    ingest(Sensor.rpm, 1600);
    ingest(Sensor.speed, 40); // below the streak threshold.
    run(const Duration(seconds: 3));
    await tester.pump();
    final daylight = await patchBrightness();
    expect(
      daylight,
      lessThan(12),
      reason:
          'the daylight patch is not the plain void it should be, so the '
          'comparison below would not be measuring the cone',
    );

    await show(tester, mode: TapeMode.night);
    ingest(Sensor.rpm, 1600);
    ingest(Sensor.speed, 40);
    run(const Duration(seconds: 3));
    await tester.pump();
    final night = await patchBrightness();

    expect(
      night,
      greaterThan(daylight + 3),
      reason:
          'the headlight cone (DESIGN.md 6.11) should lift the road '
          'surface measurably at night',
    );
  });
}
