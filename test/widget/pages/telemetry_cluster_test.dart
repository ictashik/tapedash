// The Telemetry cluster (DESIGN.md 7.3.4): renders against real DriveSignals
// with no exception, the six tiles are the six candidates with a real
// source, each bound to its own signal, and the grid fills the centre zone
// between the shared horizon and floor.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/components/telemetry_tile.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/spacing.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/drive/telemetry_cluster.dart';
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

  Future<void> show(WidgetTester tester) async {
    setWindow(tester, const Size(800, 400));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TelemetryCluster(signals: signals, width: 800, height: 400),
      ),
    );
  }

  testWidgets('renders real vehicle data with no exception', (tester) async {
    await show(tester);
    ingest(Sensor.rpm, 2200);
    ingest(Sensor.speed, 62);
    ingest(Sensor.throttle, 18);
    ingest(Sensor.load, 35);
    ingest(Sensor.coolant, 91);
    ingest(Sensor.voltage, 14.1);
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

  testWidgets('the six tiles are the six candidates with a real source', (
    tester,
  ) async {
    await show(tester);
    ingest(Sensor.rpm, 2200);
    ingest(Sensor.speed, 62);
    ingest(Sensor.throttle, 18);
    ingest(Sensor.load, 35);
    ingest(Sensor.coolant, 91);
    ingest(Sensor.voltage, 14.1);
    run(const Duration(seconds: 2));
    await tester.pump();

    final tiles = tester
        .widgetList<TelemetryTile>(find.byType(TelemetryTile))
        .toList();
    expect(tiles.length, 6);

    final byLabel = {for (final t in tiles) t.label: t};
    expect(byLabel.keys.toSet(), {
      'RPM',
      'SPEED',
      'THROTTLE',
      'LOAD',
      'COOLANT',
      'VOLTS',
    });

    // Each tile reads the signal it is named for, and no two share one.
    expect(identical(byLabel['RPM']!.value, signals.rpm), isTrue);
    expect(identical(byLabel['SPEED']!.value, signals.speed), isTrue);
    expect(identical(byLabel['THROTTLE']!.value, signals.throttle), isTrue);
    expect(identical(byLabel['LOAD']!.value, signals.load), isTrue);
    expect(identical(byLabel['COOLANT']!.value, signals.coolant), isTrue);
    expect(identical(byLabel['VOLTS']!.value, signals.voltage), isTrue);

    // Voltage shows a decimal; nothing else does.
    expect(byLabel['VOLTS']!.format.decimals, 1);
    for (final label in ['RPM', 'SPEED', 'THROTTLE', 'LOAD', 'COOLANT']) {
      expect(byLabel[label]!.format.decimals, 0);
    }
  });

  testWidgets(
    'the grid fills the centre zone, clear of the captions and the dock',
    (tester) async {
      await show(tester);
      run(const Duration(seconds: 1));
      await tester.pump();

      final tiles = tester
          .widgetList<TelemetryTile>(find.byType(TelemetryTile))
          .toList();
      expect(tiles.length, 6);

      final margin = TapeSpace.margin(400);
      final top = 400 * TapeSpace.clearOfCaptionsShare;
      final tileWidth = (800 - 2 * margin - 2 * TapeSpace.s3) / 3;
      final tileHeight =
          (400 - top - 400 * TapeSpace.clearOfDockShare - TapeSpace.s3) / 2;

      for (final tile in tiles) {
        final rect = tester.getRect(find.byWidget(tile));
        // The tile's own size is the cell's.
        expect(rect.width, closeTo(tileWidth, 0.01), reason: tile.label);
        expect(rect.height, closeTo(tileHeight, 0.01), reason: tile.label);
        // Inside the centre zone.
        expect(rect.top, greaterThanOrEqualTo(top - 0.01));
        expect(
          rect.bottom,
          lessThanOrEqualTo(400 - 400 * TapeSpace.clearOfDockShare + 0.01),
        );
      }

      // Three distinct columns and two distinct rows.
      final lefts = tiles
          .map((t) => tester.getRect(find.byWidget(t)).left)
          .toSet();
      final tops = tiles
          .map((t) => tester.getRect(find.byWidget(t)).top)
          .toSet();
      expect(lefts.length, 3);
      expect(tops.length, 2);
    },
  );
}
