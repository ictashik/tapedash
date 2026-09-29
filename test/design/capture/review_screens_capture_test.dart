// Review, the Debrief, Coach and History in the real shell, after a demo trip has
// ended. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/drive_shell.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/pages/review/review_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('a finished demo trip: the Debrief, Review, Coach, History', (
    tester,
  ) async {
    setWindow(tester, const Size(720, 360));
    final kit = TapeRenderKit();
    addTearDown(kit.dispose);
    final motion = ManualMotionClock();
    addTearDown(motion.dispose);
    final app = AppServices.inMemory();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        child: DriveShell(
          clock: clock,
          scheduler: clock,
          scenario: 'city_stop_go',
          app: app,
        ),
      ),
    );
    Future<void> run(int ms) async {
      for (var t = 0; t < ms; t += 100) {
        motion.advance(const Duration(milliseconds: 100));
        clock.advance(const Duration(milliseconds: 100));
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    // Until the drive ends, starts over and the trip has ended into the Debrief.
    final review = find.byType(ReviewPage);
    for (var i = 0; i < 4000; i++) {
      await run(500);
      if (review.evaluate().isNotEmpty &&
          tester.state<ReviewPageState>(review).isDebriefing) {
        break;
      }
    }
    expect(
      review.evaluate().isNotEmpty &&
          tester.state<ReviewPageState>(review).isDebriefing,
      isTrue,
      reason: 'the demo trip should have ended into the Debrief',
    );
    // A demo trip has a route: the demo's GPS follows the demo car.
    final trips = await tester.runAsync(() => app.trips.all(includeDemo: true));
    final samples = await tester.runAsync(
      () => app.trips.samples(trips!.first.id!),
    );
    expect(samples!.where((s) => s.latitude != null), isNotEmpty);
    await run(1400);
    await capturePng(tester, 'debrief-1');
    await run(1600);
    await capturePng(tester, 'debrief-2');
    await run(1000);
    await capturePng(tester, 'debrief-3');
    await run(4000);
    await capturePng(tester, 'review');
    tester.state<TheStripState>(find.byType(TheStrip)).goTo(3);
    await run(3000);
    await capturePng(tester, 'coach');
    tester.state<TheStripState>(find.byType(TheStrip)).goTo(4);
    await run(2000);
    await capturePng(tester, 'history');
  }, skip: !enabled);
}
