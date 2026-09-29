// The clusters' content stays clear of the parked dock (DESIGN.md 7.1's dock in
// the floor zone) and of the status strip's Parked captions, at the three screen
// sizes DESIGN.md 4.7 names. Found by the phase 3b review captures, where the
// dock sat on Apex's unit label, Telemetry's bottom row and Minimal's RPM line.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/components/tape_label.dart';
import 'package:tapedash/ui/design/components/telemetry_tile.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/spacing.dart';
import 'package:tapedash/ui/pages/drive/apex_cluster.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/drive/minimal_cluster.dart';
import 'package:tapedash/ui/pages/drive/telemetry_cluster.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late DriveSignals signals;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    signals = DriveSignals(
      vehicle: VehicleState(clock: clock, scheduler: clock),
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

  // The dock's top edge: 12 lp above the bottom, 56 lp of button.
  double dockTop(double h) => h - TapeSpace.pageTapeHeight - TapeSpace.s1 - 56;

  for (final width in [640.0, 720.0, 800.0]) {
    const h = 360.0;
    Future<void> show(WidgetTester tester, Widget Function() build) async {
      setWindow(tester, Size(width, h));
      await tester.pumpWidget(
        tapeHarness(kit: kit, motion: motion, child: build()),
      );
      await tester.pump();
    }

    testWidgets('Apex, ${width.toInt()}: the unit sits above the dock', (
      tester,
    ) async {
      await show(
        tester,
        () => ApexCluster(signals: signals, width: width, height: h),
      );
      expect(tester.takeException(), isNull);
      final unit = tester.getRect(find.widgetWithText(TapeLabel, 'KM/H'));
      expect(unit.bottom, lessThan(dockTop(h)));
      expect(unit.top, greaterThan(0));
    });

    testWidgets(
      'Telemetry, ${width.toInt()}: the grid is between captions and dock',
      (tester) async {
        await show(
          tester,
          () => TelemetryCluster(signals: signals, width: width, height: h),
        );
        expect(tester.takeException(), isNull);
        final tiles = find.byType(TelemetryTile).evaluate();
        expect(tiles.length, 6);
        for (final t in tiles) {
          final r = tester.getRect(find.byWidget(t.widget));
          expect(
            r.top,
            greaterThanOrEqualTo(h * TapeSpace.clearOfCaptionsShare - 0.5),
          );
          expect(r.bottom, lessThanOrEqualTo(dockTop(h) + 0.5));
        }
      },
    );

    testWidgets('Minimal, ${width.toInt()}: the RPM line is above the dock', (
      tester,
    ) async {
      await show(
        tester,
        () => MinimalCluster(signals: signals, width: width, height: h),
      );
      expect(tester.takeException(), isNull);
      final line = find.byWidgetPredicate(
        (w) => w is CustomPaint && w.painter is RpmLinePainter,
      );
      expect(tester.getRect(line).bottom, lessThan(dockTop(h)));
    });
  }
}
