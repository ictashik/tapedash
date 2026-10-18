import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/design/tokens/spacing.dart';
import 'package:tapedash/ui/pages/strip/parked_dock.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../../design/support/harness.dart';
// The parked dock (DESIGN.md 7.1): rises into the floor zone when parked,
// the buttons staggered after it; falls on spring.snap inside the motion
// return's own 300 ms when the car starts moving. The buttons are disabled
// and documented: their destinations do not exist yet.

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late ValueNotifier<DrivingMode> mode;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    mode = ValueNotifier(DrivingMode.parked);
  });

  tearDown(() {
    motion.dispose();
    kit.dispose();
  });

  void run(Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
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
        child: ParkedDock(mode: mode, motion: motion, width: 800, height: 400),
      ),
    );
  }

  testWidgets('the dock is risen while parked, its five buttons visible', (
    tester,
  ) async {
    await show(tester);
    run(const Duration(milliseconds: 800));
    await tester.pump();

    final state = tester.state<ParkedDockState>(find.byType(ParkedDock));
    expect(state.rise, closeTo(1, 0.05));

    // The dock's own floor sits the tape's own height above the bottom,
    // and each button's own translate rides it in from below: the buttons
    // are inside the frame, with their own tops at the dock's own floor.
    final rect = tester.getRect(find.byType(ParkedDock));
    expect(rect.bottom, closeTo(400, 0.01));
    for (final b in find.byType(TapeButton).evaluate()) {
      final r = tester.getRect(find.byWidget(b.widget));
      expect(r.top, greaterThanOrEqualTo(400 - 56 - 12 - 1 - 0.01));
      // Risen into the floor zone: above the page tape and its gap.
      expect(r.bottom, closeTo(400 - 12, 0.5));
    }
  });

  testWidgets('the buttons keep the pages\' margin from the screen edge', (
    tester,
  ) async {
    // The first real phone cut off the left chamfer of the first button: the
    // row started at 0, where every page starts at the margin.
    await show(tester);
    run(const Duration(milliseconds: 800));
    await tester.pump();

    final margin = TapeSpace.margin(400);
    final buttons = find.byType(TapeButton);
    final first = tester.getRect(buttons.first);

    expect(first.left, closeTo(margin, 0.5));
  });

  group('End trip', () {
    late ValueNotifier<bool> running;
    var ended = 0;

    setUp(() {
      running = ValueNotifier(false);
      ended = 0;
    });
    tearDown(() => running.dispose());

    Future<void> showAt(WidgetTester tester, Size size) async {
      setWindow(tester, size);
      await tester.pumpWidget(
        tapeHarness(
          kit: kit,
          motion: motion,
          theme: TapeThemeData(livery: Liveries.ion),
          child: ParkedDock(
            mode: mode,
            motion: motion,
            width: size.width,
            height: size.height,
            onGarage: () {},
            onPitStop: () {},
            onDiagnostics: () {},
            onInsights: () {},
            onHud: () {},
            onEndTrip: () => ended++,
            endTripAvailable: running,
          ),
        ),
      );
      run(const Duration(milliseconds: 800));
      await tester.pump();
    }

    testWidgets('is there while a trip is recorded, and calls back', (
      tester,
    ) async {
      running.value = true;
      await showAt(tester, const Size(720, 360));

      expect(find.text('END TRIP'), findsOneWidget);
      await tester.tap(find.text('END TRIP'));
      expect(ended, 1);
    });

    testWidgets('is not there with no trip to end, and comes when one starts', (
      tester,
    ) async {
      await showAt(tester, const Size(720, 360));
      expect(find.text('END TRIP'), findsNothing);
      expect(find.byType(TapeButton), findsNWidgets(5));

      running.value = true;
      run(const Duration(milliseconds: 800));
      await tester.pump();
      expect(find.text('END TRIP'), findsOneWidget);

      running.value = false;
      await tester.pump();
      expect(find.text('END TRIP'), findsNothing);
    });

    for (final size in const [Size(640, 360), Size(720, 360), Size(800, 360)]) {
      testWidgets(
        'all six buttons are on the screen at ${size.width.toInt()}x360',
        (tester) async {
          running.value = true;
          await showAt(tester, size);

          expect(tester.takeException(), isNull, reason: 'no overflow');
          for (final b in find.byType(TapeButton).evaluate()) {
            final r = tester.getRect(find.byWidget(b.widget));
            expect(r.left, greaterThanOrEqualTo(0));
            expect(r.right, lessThanOrEqualTo(size.width));
          }
          expect(find.byType(TapeButton), findsNWidgets(6));
        },
      );
    }
  });

  testWidgets('the dock falls inside the motion return when moving', (
    tester,
  ) async {
    await show(tester);
    run(const Duration(milliseconds: 800));
    await tester.pump();

    mode.value = DrivingMode.motion;
    run(const Duration(milliseconds: 300));
    await tester.pump();
    await tester.pump();

    final state = tester.state<ParkedDockState>(find.byType(ParkedDock));
    expect(state.rise, closeTo(0, 0.05));
  });

  for (final width in [640.0, 720.0, 800.0]) {
    testWidgets(
      'the five buttons fit ${width.toInt()} lp, no overflow, 48 lp+',
      (tester) async {
        setWindow(tester, Size(width, 360));
        await tester.pumpWidget(
          tapeHarness(
            kit: kit,
            motion: motion,
            child: ParkedDock(
              mode: mode,
              motion: motion,
              width: width,
              height: 360,
            ),
          ),
        );
        run(const Duration(milliseconds: 900));
        await tester.pump();
        expect(tester.takeException(), isNull);
        for (final b in find.byType(TapeButton).evaluate()) {
          final r = tester.getRect(find.byWidget(b.widget));
          expect(r.left, greaterThanOrEqualTo(0));
          expect(r.right, lessThanOrEqualTo(width));
          expect(r.width, greaterThanOrEqualTo(48));
          expect(r.height, greaterThanOrEqualTo(48));
        }
      },
    );
  }
}
