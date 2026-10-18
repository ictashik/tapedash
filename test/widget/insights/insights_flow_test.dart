// Insights through the whole shell: from the dock, while parked; the tank counted
// for a demo; closed by Close and by the car moving.
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/platform/image_sharer.dart';
import 'package:tapedash/ui/design/components/controls/tape_button.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/insights/insights_page.dart';
import 'package:tapedash/ui/pages/insights/tank_panel.dart';

import '../../design/support/harness.dart';

void main() {
  setUpAll(loadTapeFonts);

  late TapeRenderKit kit;
  late ManualMotionClock motion;
  late FakeClock clock;

  setUp(() {
    kit = TapeRenderKit();
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
  });

  tearDown(() {
    motion.dispose();
    kit.dispose();
  });

  Future<void> run(WidgetTester tester, int ms) async {
    for (var t = 0; t < ms; t += 50) {
      motion.tick(0.05);
      clock.advance(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  Future<void> boot(WidgetTester tester, String scenario) async {
    setWindow(tester, const Size(720, 360));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: DriveShell(
          clock: clock,
          scheduler: clock,
          scenario: scenario,
          sharer: MemoryImageSharer(),
        ),
      ),
    );
  }

  testWidgets('parked, the dock opens Insights, and Close closes it', (
    tester,
  ) async {
    await boot(tester, 'cold_start_idle');
    await run(tester, 30000);
    expect(find.byType(InsightsPage), findsNothing);

    await tester.tap(find.widgetWithText(TapeButton, 'INSIGHTS'));
    await run(tester, 300);
    expect(find.byType(InsightsPage), findsOneWidget);
    // The first panel is Current; a demo has no trips yet, and says so.
    expect(find.text('CURRENT'), findsWidgets);

    await tester.tap(find.text('CLOSE'));
    await run(tester, 300);
    expect(find.byType(InsightsPage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a demo starts with a full tank, so the count has something', (
    tester,
  ) async {
    await boot(tester, 'cold_start_idle');
    await run(tester, 30000);
    await tester.tap(find.widgetWithText(TapeButton, 'INSIGHTS'));
    await run(tester, 300);
    final state = tester.state<InsightsPageState>(find.byType(InsightsPage));
    state.showTab(InsightTab.tank);
    await run(tester, 300);
    expect(find.byType(TankPanel), findsOneWidget);
    // 40 L less a little idling: it reads "≈ 40", and has no empty state.
    expect(find.text('NOTHING TO COUNT FROM YET'), findsNothing);
    expect(find.textContaining('≈ 40'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('every tab opens in the shell without an exception', (
    tester,
  ) async {
    await boot(tester, 'cold_start_idle');
    await run(tester, 30000);
    await tester.tap(find.widgetWithText(TapeButton, 'INSIGHTS'));
    await run(tester, 300);
    final state = tester.state<InsightsPageState>(find.byType(InsightsPage));
    for (final tab in InsightTab.values) {
      state.showTab(tab);
      await run(tester, 200);
      expect(tester.takeException(), isNull, reason: tab.name);
    }
  });
}
