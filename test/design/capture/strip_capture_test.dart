// A first look at the Strip, against a real DemoDrive (the same OBD stack a
// real car would run through). Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/demo_drive.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/money/money_page.dart';
import 'package:tapedash/ui/pages/strip/parked_dock.dart';
import 'package:tapedash/ui/pages/strip/placeholder_page.dart';
import 'package:tapedash/ui/pages/strip/the_strip.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  List<Widget> pages(DriveSignals signals, ManualMotionClock motion) => [
    StripPlaceholder(
      name: 'REVIEW',
      note: 'Arrives with the trip log.',
      width: 800,
      height: 400,
    ),
    MoneyPage(signals: signals, width: 800, height: 400),
    DrivePage(signals: signals, motion: motion, width: 800, height: 400),
    StripPlaceholder(
      name: 'COACH',
      note: 'Arrives with the coach.',
      width: 800,
      height: 400,
    ),
    StripPlaceholder(
      name: 'HISTORY',
      note: 'Arrives with the trip log.',
      width: 800,
      height: 400,
    ),
  ];

  Widget strip(DriveSignals signals, ManualMotionClock motion) => Stack(
    children: [
      TheStrip(
        pages: pages(signals, motion),
        mode: signals.mode,
        motion: motion,
        width: 800,
        height: 400,
      ),
      ParkedDock(mode: signals.mode, motion: motion, width: 800, height: 400),
    ],
  );

  Future<(DriveSignals, DemoDrive, ManualMotionClock, FakeClock)> rig([
    String scenario = 'highway_cruise',
  ]) async {
    final motion = ManualMotionClock();
    final clock = FakeClock();
    final demo = DemoDrive(
      clock: clock,
      scheduler: clock,
      scenario: scenario,
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
    return (signals, demo, motion, clock);
  }

  void run(FakeClock clock, ManualMotionClock motion, Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
  }

  Future<void> pumpStrip(
    WidgetTester tester, {
    required TapeRenderKit kit,
    required ManualMotionClock motion,
    required DriveSignals signals,
  }) async {
    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: strip(signals, motion),
      ),
    );
  }

  testWidgets('the strip on Drive, parked, at the page tape', (tester) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final (signals, demo, motion, clock) = await rig('cold_start_idle');
    await pumpStrip(tester, kit: kit, motion: motion, signals: signals);

    // A cold-start drive sits parked with the engine running, so the dock
    // is risen and the tape is unlocked with Drive's own tick lit.
    run(clock, motion, const Duration(seconds: 20));
    await tester.pump();
    await capturePng(tester, 'strip-parked');

    demo.stop();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);

  testWidgets('the strip at speed, and a swipe halfway to Money', (
    tester,
  ) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final (signals, demo, motion, clock) = await rig();
    await pumpStrip(tester, kit: kit, motion: motion, signals: signals);

    // A highway drive is in motion within a few seconds: the tape shows
    // the lock on every page but Money and Drive.
    run(clock, motion, const Duration(seconds: 20));
    await tester.pump();
    await capturePng(tester, 'strip-motion-drive');

    // A drag halfway to Money, held: both pages on screen at once.
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(400, 0));
    run(clock, motion, const Duration(milliseconds: 250));
    await tester.pump();
    await capturePng(tester, 'strip-mid-swipe');

    demo.stop();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);

  testWidgets('the motion lock: a swipe toward Coach rubber-bands', (
    tester,
  ) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final (signals, demo, motion, clock) = await rig();
    await pumpStrip(tester, kit: kit, motion: motion, signals: signals);
    run(clock, motion, const Duration(seconds: 20));

    // A drag toward Coach, well past the reachable edge, released: the
    // strip springs back to Drive on the fast spring and the lock glyph
    // fades in for the lock's own 800 ms.
    final drag = await tester.startGesture(const Offset(400, 200));
    await drag.moveBy(const Offset(-400, 0));
    run(clock, motion, const Duration(milliseconds: 100));
    await drag.up();
    run(clock, motion, const Duration(milliseconds: 150));
    await tester.pump();
    await capturePng(tester, 'strip-locked');

    demo.stop();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
