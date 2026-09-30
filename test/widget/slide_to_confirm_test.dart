import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/controls/slide_to_confirm.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';

import '../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
  });

  tearDown(() {
    kit.dispose();
    motion.dispose();
  });

  Future<void> show(WidgetTester tester, VoidCallback? onConfirmed) async {
    setWindow(tester, const Size(500, 200));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: Center(
          child: SizedBox(
            width: 400,
            child: SlideToConfirm(
              label: 'Slide to clear',
              onConfirmed: onConfirmed,
            ),
          ),
        ),
      ),
    );
  }

  SlideToConfirmState state(WidgetTester tester) =>
      tester.state<SlideToConfirmState>(find.byType(SlideToConfirm));

  testWidgets('dragged all the way across and let go, it confirms once', (
    tester,
  ) async {
    var confirmed = 0;
    await show(tester, () => confirmed++);
    final thumb =
        tester.getTopLeft(find.byType(SlideToConfirm)) + const Offset(40, 28);
    final drag = await tester.startGesture(thumb);
    await drag.moveBy(const Offset(200, 0));
    await tester.pump();
    expect(state(tester).position, greaterThan(0.4));
    expect(confirmed, 0, reason: 'nothing happens while it is being dragged');
    await drag.moveBy(const Offset(300, 0));
    await drag.up();
    await tester.pump();
    expect(confirmed, 1);

    // It goes back to the start by itself.
    motion.advance(const Duration(seconds: 2));
    await tester.pump();
    expect(state(tester).position, closeTo(0, 0.01));
  });

  testWidgets('a release short of the end springs back and does nothing', (
    tester,
  ) async {
    var confirmed = 0;
    await show(tester, () => confirmed++);
    final thumb =
        tester.getTopLeft(find.byType(SlideToConfirm)) + const Offset(40, 28);
    final drag = await tester.startGesture(thumb);
    await drag.moveBy(const Offset(250, 0));
    await tester.pump();
    expect(state(tester).position, inExclusiveRange(0.4, 0.9));
    await drag.up();
    motion.advance(const Duration(seconds: 2));
    await tester.pump();
    expect(confirmed, 0);
    expect(state(tester).position, closeTo(0, 0.01));
  });

  testWidgets('a tap does nothing', (tester) async {
    var confirmed = 0;
    await show(tester, () => confirmed++);
    await tester.tap(find.byType(SlideToConfirm));
    await tester.pump();
    expect(confirmed, 0);
  });

  testWidgets('disabled, it does not move', (tester) async {
    await show(tester, null);
    final thumb =
        tester.getTopLeft(find.byType(SlideToConfirm)) + const Offset(40, 28);
    final drag = await tester.startGesture(thumb);
    await drag.moveBy(const Offset(400, 0));
    await drag.up();
    await tester.pump();
    expect(state(tester).position, 0);
  });
}
