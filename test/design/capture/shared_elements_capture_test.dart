// A first look at the shared-element flight (DESIGN.md 7.1): the hero on
// Drive, the number travelling mid-swipe, and the landing in the Money
// page's status corner. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/money/money_page.dart';
import 'package:tapedash/ui/pages/strip/placeholder_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';
import 'package:tapedash/vehicle/vehicle_state.dart' show DrivingMode;

import '../../support/sim_drive.dart';
import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('the speed flight: Drive, mid-flight, Money', (tester) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final demo = SimDrive(
      clock: clock,
      scheduler: clock,
      scenario: 'highway_cruise',
      profile: 'petrol_cvt_maf',
    );
    demo.start();
    final signals = DriveSignals(
      vehicle: demo.vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: demo.connection,
    );
    final mode = ValueNotifier(DrivingMode.parked);
    addTearDown(() {
      demo.stop();
      signals.dispose();
      motion.dispose();
      kit.dispose();
      mode.dispose();
    });

    void run(Duration d) {
      var l = d.inMicroseconds;
      while (l > 0) {
        final s = l < 16667 ? l : 16667;
        motion.tick(s / 1e6);
        clock.advance(Duration(microseconds: s));
        l -= s;
      }
    }

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TheStrip(
          pages: [
            StripPlaceholder(
              name: 'REVIEW',
              note: '...',
              width: 800,
              height: 400,
            ),
            MoneyPage(signals: signals, width: 800, height: 400),
            DrivePage(
              signals: signals,
              motion: motion,
              width: 800,
              height: 400,
            ),
            StripPlaceholder(
              name: 'COACH',
              note: '...',
              width: 800,
              height: 400,
            ),
            StripPlaceholder(
              name: 'HISTORY',
              note: '...',
              width: 800,
              height: 400,
            ),
          ],
          mode: mode,
          motion: motion,
          width: 800,
          height: 400,
        ),
      ),
    );
    run(const Duration(seconds: 15));
    await tester.pump();
    await tester.pump();
    await capturePng(tester, 'shared-element-drive');

    // A held drag toward Money: the number leaves the hero and flies.
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(200, 0));
    run(const Duration(milliseconds: 40));
    await drag.moveBy(const Offset(200, 0));
    run(const Duration(milliseconds: 700));
    await tester.pump();
    await tester.pump();
    await capturePng(tester, 'shared-element-mid-flight');
    await drag.cancel();
    run(const Duration(seconds: 1));
    await tester.pump();

    // Settled on Money: the speed lives in the status corner.
    await tester.flingFrom(const Offset(400, 200), const Offset(800, 200), 300);
    run(const Duration(seconds: 2));
    await tester.pump();
    await tester.pump();
    await tester.pump();
    await capturePng(tester, 'shared-element-money');
  }, skip: !enabled);
}
