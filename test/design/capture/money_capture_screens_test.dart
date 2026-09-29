// The phase 4 screens in the real shell: the money on the Drive clusters, the
// Money page in Motion and Parked, and Pit Stop. Skipped unless
// TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<(FakeClock, ManualMotionClock, Future<void> Function(int))> boot(
    WidgetTester tester,
    String scenario,
    Size size,
  ) async {
    setWindow(tester, size);
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: DriveShell(clock: clock, scheduler: clock, scenario: scenario),
      ),
    );
    Future<void> run(int ms) async {
      for (var t = 0; t < ms; t += 50) {
        motion.tick(0.05);
        clock.advance(const Duration(milliseconds: 50));
        await tester.pump(const Duration(milliseconds: 50));
      }
    }

    return (clock, motion, run);
  }

  testWidgets('money on the clusters, motion', (tester) async {
    final (_, _, run) = await boot(
      tester,
      'city_stop_go',
      const Size(640, 360),
    );
    await run(140000);
    await capturePng(tester, 'money-apex-motion');
    for (final name in ['tape', 'minimal']) {
      await tester.timedDrag(
        find.byType(TheStrip),
        const Offset(0, -250),
        const Duration(milliseconds: 250),
      );
      await run(1500);
      await capturePng(tester, 'money-$name-motion');
    }
    // Back to Apex by wrapping the reel round, then to the Money page.
    for (var k = 0; k < 2; k++) {
      await tester.timedDrag(
        find.byType(TheStrip),
        const Offset(0, -250),
        const Duration(milliseconds: 250),
      );
    }
    await run(1500);
    await slowPageRight(tester, run);
    await capturePng(tester, 'money-page-motion');
  }, skip: !enabled);

  testWidgets('money page and pit stop, parked', (tester) async {
    final (_, _, run) = await boot(
      tester,
      'cold_start_idle',
      const Size(640, 360),
    );
    await run(60000);
    await slowPageRight(tester, run);
    await capturePng(tester, 'money-page-parked');
    await tester.tap(find.text('PIT STOP').first);
    await run(600);
    await capturePng(tester, 'pitstop');
    for (final k in ['3', '2', '.', '5']) {
      await tester.tap(find.text(k).first);
      await tester.pump();
    }
    await run(200);
    await capturePng(tester, 'pitstop-typed');
  }, skip: !enabled);
}

/// To the Money page, the way a release would land there.
Future<void> slowPageRight(
  WidgetTester tester,
  Future<void> Function(int) run,
) async {
  tester.state<TheStripState>(find.byType(TheStrip)).goTo(TheStrip.moneyPage);
  await run(3000);
}
