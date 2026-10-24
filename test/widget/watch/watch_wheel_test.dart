// The watch's wheel (DESIGN.md 16.7): a list, a choice and a dial in one. Which
// row is chosen, what a tap on the centre or on a neighbour does, the bezel (and its
// quick stride), a swipe, and that it builds only the rows near the centre.
import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/watch/watch_face.dart';
import 'package:tapedash/ui/design/components/watch/watch_wheel.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/tokens/watch.dart';

import '../../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  const face = WatchFace(225);
  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;
  late StreamController<int> bezel;
  late List<int> chosen;
  late List<int> moved;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock();
    bezel = StreamController<int>.broadcast();
    chosen = [];
    moved = [];
  });

  tearDown(() {
    bezel.close();
    motion.dispose();
    kit.dispose();
  });

  void run(Duration d) {
    var left = d.inMicroseconds;
    while (left > 0) {
      final step = left < 16667 ? left : 16667;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
  }

  Future<void> boot(
    WidgetTester tester, {
    int count = 5,
    int initial = 0,
    int fast = 1,
    String? title = 'Menu',
  }) async {
    setWindow(tester, const Size(225, 225));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: WatchWheel(
          title: title,
          itemCount: count,
          initial: initial,
          fastStride: fast,
          face: face,
          motion: motion,
          rotary: bezel.stream,
          rowAt: (i) => WheelRow(
            label: 'Row $i',
            value: i == 1 ? 'Set to x' : null,
            lit: i == 2,
          ),
          onChoose: chosen.add,
          onMoved: moved.add,
        ),
      ),
    );
  }

  WatchWheelState wheel(WidgetTester tester) =>
      tester.state<WatchWheelState>(find.byType(WatchWheel));

  Future<void> settle(WidgetTester tester) async {
    run(const Duration(milliseconds: 800));
    await tester.pump();
  }

  testWidgets('shows the chosen row at the centre and its neighbours', (
    tester,
  ) async {
    await boot(tester, initial: 2);
    expect(find.text('ROW 2'), findsOneWidget);
    expect(find.text('ROW 1'), findsOneWidget);
    expect(find.text('ROW 3'), findsOneWidget);
    // Two away is out of the circle: not even built.
    expect(find.text('ROW 0'), findsNothing);
    expect(find.text('ROW 4'), findsNothing);
    expect(find.text('MENU'), findsOneWidget);
    // A neighbour shows its second line too, dimmer.
    expect(find.text('SET TO X'), findsOneWidget);
  });

  testWidgets('a tap on the centre chooses it', (tester) async {
    await boot(tester, initial: 1);
    await tester.tapAt(const Offset(112.5, 112.5));
    await tester.pump();
    expect(chosen, [1]);
  });

  testWidgets(
    'a tap on a neighbour moves the wheel there and chooses nothing',
    (tester) async {
      await boot(tester, initial: 1);
      await tester.tapAt(Offset(112.5, 112.5 + TapeWatch.wheelRow));
      await tester.pump();
      await settle(tester);
      expect(chosen, isEmpty);
      expect(wheel(tester).selected, 2);
      await tester.tapAt(Offset(112.5, 112.5 - TapeWatch.wheelRow));
      await tester.pump();
      await settle(tester);
      expect(wheel(tester).selected, 1);
    },
  );

  testWidgets('the bezel steps a row a detent and stops at the ends', (
    tester,
  ) async {
    await boot(tester);
    bezel.add(-1);
    await tester.pump();
    await settle(tester);
    expect(wheel(tester).selected, 0);
    for (var i = 0; i < 8; i++) {
      bezel.add(1);
      await tester.pump();
      run(const Duration(milliseconds: 200));
    }
    await settle(tester);
    expect(wheel(tester).selected, 4);
    expect(moved.last, 4);
  });

  testWidgets('quick turns of a dial step its fast stride, slow ones one', (
    tester,
  ) async {
    await boot(tester, count: 1000, initial: 100, fast: 10);
    // A slow turn: one row.
    bezel.add(1);
    await tester.pump();
    run(const Duration(milliseconds: 400));
    await tester.pump();
    expect(wheel(tester).selected, 101);
    // Three quick turns, 40 ms apart: the first is slow, the other two fast.
    for (var i = 0; i < 3; i++) {
      bezel.add(1);
      await tester.pump();
      run(const Duration(milliseconds: 40));
    }
    await settle(tester);
    expect(wheel(tester).selected, 101 + 1 + 10 + 10);
  });

  testWidgets('a swipe up moves on and a swipe down comes back', (
    tester,
  ) async {
    await boot(tester, initial: 1);
    await tester.drag(
      find.byType(WatchWheel),
      const Offset(0, -TapeWatch.wheelRow),
    );
    await tester.pump();
    await settle(tester);
    expect(wheel(tester).selected, 2);
    await tester.drag(
      find.byType(WatchWheel),
      const Offset(0, TapeWatch.wheelRow),
    );
    await tester.pump();
    await settle(tester);
    expect(wheel(tester).selected, 1);
  });

  testWidgets(
    'a dial of a thousand rows builds only the ones near the centre',
    (tester) async {
      await boot(tester, count: 1000, initial: 500);
      expect(find.byType(Text).evaluate().length, lessThan(10));
    },
  );

  testWidgets('reports the row it has come to rest on, and only then', (
    tester,
  ) async {
    await boot(tester);
    bezel.add(1);
    await tester.pump();
    expect(moved, isEmpty);
    await settle(tester);
    expect(moved, [1]);
  });
}
