// A first look at the Telemetry cluster, against a real SimDrive (the same
// OBD stack a real car would run through). Skipped unless TAPEDASH_CAPTURE_DIR
// is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/ui/pages/drive/telemetry_cluster.dart';

import '../../support/sim_drive.dart';
import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  Future<void> drive(
    WidgetTester tester,
    String name, {
    required String scenario,
  }) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock();
    final demo = SimDrive(
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

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: TelemetryCluster(signals: signals, width: 800, height: 400),
        ),
      ),
    );

    // Long enough that the sparklines have real history: the tiles sample
    // at 2 Hz, so 60 s fills one completely; 60 s of drive is well past
    // the ignition and several polls.
    var left = const Duration(seconds: 60).inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
    await tester.pump();
    await capturePng(tester, name);

    demo.stop();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  }

  testWidgets('highway cruise', (tester) async {
    await drive(
      tester,
      'telemetry-cluster-highway',
      scenario: 'highway_cruise',
    );
  }, skip: !enabled);

  testWidgets('city stop-go', (tester) async {
    await drive(tester, 'telemetry-cluster-city', scenario: 'city_stop_go');
  }, skip: !enabled);
}
