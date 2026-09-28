// The Drive page's reel (DESIGN.md 7.3): a vertical swipe cycles the five
// cluster layouts reel-like, the choice held for the session, the slots
// following the same open window the reel paints on, and a page inside
// the window never rebuilding while the reel moves within it.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
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
    final vehicle = VehicleState(clock: clock, scheduler: clock);
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
        child: DrivePage(
          signals: signals,
          motion: motion,
          width: 800,
          height: 400,
        ),
      ),
    );
  }

  testWidgets('the reel starts on Apex and holds it', (tester) async {
    await show(tester);
    run(const Duration(seconds: 2));
    await tester.pump();

    final state = tester.state<DrivePageState>(find.byType(DrivePage));
    expect(state.reel, closeTo(0, 0.05));
  });

  testWidgets('a vertical swipe cycles to the next cluster', (tester) async {
    await show(tester);
    await tester.pump();

    await tester.flingFrom(const Offset(400, 200), const Offset(0, -480), 2000);
    run(const Duration(seconds: 1));
    await tester.pump();

    final state = tester.state<DrivePageState>(find.byType(DrivePage));
    expect(state.reel, closeTo(1, 0.05));
  });

  testWidgets("the reel's own ends hold: no cluster beyond the last", (
    tester,
  ) async {
    await show(tester);
    await tester.pump();

    final state = tester.state<DrivePageState>(find.byType(DrivePage));

    // Past the last cluster: the reel holds at the end.
    for (var i = 0; i < 6; i++) {
      await tester.flingFrom(
        const Offset(400, 200),
        const Offset(0, -480),
        2000,
      );
      run(const Duration(milliseconds: 200));
    }
    run(const Duration(seconds: 2));
    await tester.pump();
    expect(state.reel, closeTo(4, 0.05));
  });

  testWidgets('a page inside the window does not rebuild while the reel '
      'moves within it', (tester) async {
    var builds = 0;
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: Builder(
          builder: (context) {
            builds++;
            return DrivePage(
              signals: signals,
              motion: motion,
              width: 800,
              height: 400,
            );
          },
        ),
      ),
    );
    builds = 0;

    // A slow swipe within a cluster's own window: the DrivePage itself
    // builds once and never again.
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(0, 120));
    run(const Duration(milliseconds: 40));
    await drag.moveBy(const Offset(0, -120));
    run(const Duration(seconds: 1));
    await tester.pump();
    await tester.pump();
    expect(builds, 0);
  });
}
