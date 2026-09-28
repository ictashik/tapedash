// The Tape cluster (DESIGN.md 7.3.2): renders against real DriveSignals with
// no exception, the tapes sit on the flanks of the centre zone (between the
// shared horizon and floor), the RPM tape carries the redline band, and the
// speed tape carries none -- the user threshold that would feed it has no
// source before phase 4/5.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/components/vertical_tape.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/spacing.dart';
import 'package:tapedash/ui/design/tokens/tach.dart';
import 'package:tapedash/ui/design/tokens/vertical_tape.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/drive/tape_cluster.dart';
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
        child: TapeCluster(signals: signals, width: 800, height: 400),
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

  testWidgets('the tapes sit on the flanks of the centre zone', (tester) async {
    await show(tester);
    ingest(Sensor.rpm, 2200);
    ingest(Sensor.speed, 62);
    run(const Duration(seconds: 2));
    await tester.pump();

    final tapes = tester
        .widgetList<VerticalTape>(find.byType(VerticalTape))
        .toList();
    expect(tapes.length, 2);

    final speed = tapes.singleWhere((t) => identical(t.value, signals.speed));
    final rpm = tapes.singleWhere((t) => identical(t.value, signals.rpm));

    final tapeWidth = 800 * TapeVerticalTape.widthShareOfW;
    final top = 400 * TapeSpace.horizonShare;
    final tapeHeight = 400 - top - 400 * TapeSpace.floorShare;

    Rect rectOf(VerticalTape tape) =>
        tester.getRect(find.byWidgetPredicate((w) => w == tape));

    final speedRect = rectOf(speed);
    final rpmRect = rectOf(rpm);

    // The speed tape flush with the left edge, the RPM tape flush with the
    // right, both the strip width DESIGN.md 6.3 gives (0.13W), both filling
    // the centre zone between the shared horizon and floor zones.
    expect(speedRect.left, 0);
    expect(speedRect.right, closeTo(tapeWidth, 0.01));
    expect(rpmRect.right, 800);
    expect(rpmRect.left, closeTo(800 - tapeWidth, 0.01));
    expect(speedRect.top, closeTo(top, 0.01));
    expect(rpmRect.top, closeTo(top, 0.01));
    expect(speedRect.height, closeTo(tapeHeight, 0.01));
    expect(rpmRect.height, closeTo(tapeHeight, 0.01));

    // Each readout box straddles the tape's inner edge, facing the centre
    // the way DESIGN.md 6.3 draws them (the speed tape's on its right, the
    // RPM tape's on its left). The box is 1.7x the strip wide, so half of
    // it juts into the centre zone from each side.
    expect(
      speed.readoutSide,
      TapeReadoutSide.right,
      reason: 'the speed tape is on the left, so its inner edge is its right',
    );
    expect(
      rpm.readoutSide,
      TapeReadoutSide.left,
      reason: 'the RPM tape is on the right, so its inner edge is its left',
    );
  });

  testWidgets('the RPM tape bands at the redline, the speed tape at none', (
    tester,
  ) async {
    await show(tester);
    final tapes = tester
        .widgetList<VerticalTape>(find.byType(VerticalTape))
        .toList();
    final speed = tapes.singleWhere((t) => identical(t.value, signals.speed));
    final rpm = tapes.singleWhere((t) => identical(t.value, signals.rpm));

    // DESIGN.md 6.3: the redline appears as a tinted band. The same redline
    // the tach arc uses, not a second number invented for the tape.
    expect(rpm.thresholdValue, TapeTach.defaultRedlineRpm);

    // DESIGN.md 6.3 also bands the tape from the *user's* speed threshold;
    // that setting arrives with the coach's thresholds (phase 5), so none
    // is passed rather than a guessed default (CLAUDE.md 1).
    expect(speed.thresholdValue, isNull);
  });
}
