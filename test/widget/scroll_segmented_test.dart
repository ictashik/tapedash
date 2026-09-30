// The scrolling segmented selector (DESIGN.md 6.14): cells as wide as their labels,
// the selected one brought into view, and a chevron where there is more.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/ui/design/components/controls/tape_scroll_segmented.dart';
import 'package:tapedash/ui/design/components/controls/tape_segmented.dart'
    show TapeSegment;
import 'package:tapedash/ui/design/icons/icons.dart';
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

  const labels = [
    'Speed',
    'RPM',
    'Throttle',
    'Load',
    'Coolant',
    'Volts',
    '₹/km',
  ];

  Future<void> show(
    WidgetTester tester, {
    required ValueNotifier<String> value,
    double width = 300,
  }) async {
    setWindow(tester, const Size(640, 360));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: width,
            child: ValueListenableBuilder<String>(
              valueListenable: value,
              builder: (context, v, _) => TapeScrollSegmented<String>(
                height: 34,
                value: v,
                onChanged: (x) => value.value = x,
                segments: [for (final l in labels) TapeSegment(l, l)],
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  int chevrons() => find
      .byWidgetPredicate((w) => w is TapeIconView && w.icon == TapeIcon.chevron)
      .evaluate()
      .length;

  testWidgets(
    'seven cells that do not fit a 300 lp strip scroll, with a chevron',
    (tester) async {
      final value = ValueNotifier('Speed');
      addTearDown(value.dispose);
      await show(tester, value: value);

      expect(tester.takeException(), isNull, reason: 'no overflow');
      expect(chevrons(), 1, reason: 'more to the right, none to the left');
    },
  );

  testWidgets('a tap chooses, and the chosen cell is brought into view', (
    tester,
  ) async {
    final value = ValueNotifier('Speed');
    addTearDown(value.dispose);
    await show(tester, value: value);

    final cell = find.text('₹/KM');
    await tester.ensureVisible(cell);
    await tester.pump();
    await tester.tap(cell, warnIfMissed: false);
    for (var i = 0; i < 20; i++) {
      motion.advance(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(value.value, '₹/km');
    final r = tester.getRect(cell);
    expect(r.right, lessThanOrEqualTo(300.5));
    expect(r.left, greaterThanOrEqualTo(-0.5));
    expect(chevrons(), 1, reason: 'now the chevron is on the left');
  });

  testWidgets('a strip wide enough for all of them has no chevron', (
    tester,
  ) async {
    final value = ValueNotifier('Speed');
    addTearDown(value.dispose);
    await show(tester, value: value, width: 620);

    expect(chevrons(), 0);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a selection outside the list is the first cell, not a crash', (
    tester,
  ) async {
    final value = ValueNotifier('Nonsense');
    addTearDown(value.dispose);
    await show(tester, value: value);

    expect(tester.takeException(), isNull);
  });
}
