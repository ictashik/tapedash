// A first look at the Apex cluster, against a real DemoDrive (the same OBD
// stack a real car would run through). Skipped unless TAPEDASH_CAPTURE_DIR
// is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/demo_drive.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/apex_cluster.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('the Apex cluster against a real demo drive', (tester) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock();
    final demo = DemoDrive(
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

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: ApexCluster(signals: signals, width: 800, height: 400),
        ),
      ),
    );

    // Let the drive get going: past the ignition RPM, and long enough that
    // the fast tier has polled several times.
    var left = const Duration(seconds: 20).inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
    await tester.pump();
    await capturePng(tester, 'apex-cluster');

    demo.stop();
    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);

  testWidgets('the Apex cluster parked, on the same real DemoDrive', (
    tester,
  ) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock();
    final demo = DemoDrive(
      clock: clock,
      scheduler: clock,
      scenario: 'highway_cruise',
      profile: 'petrol_cvt_maf',
    );
    // The drive does not run: the vehicle sits at a stop, so the mode is
    // Parked from the start and the share is parked at rest.
    demo.start();
    demo.stop();

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
          child: ApexCluster(signals: signals, width: 800, height: 400),
        ),
      ),
    );

    // A few seconds of idle readings, so the arc has a real value to show,
    // then the choreography's own reveal, which has long since settled.
    var left = const Duration(seconds: 4).inMicroseconds;
    const frame = 16667;
    var sinceIngest = 0;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      // An idle engine at a standstill, fed at the fast tier's own pace so
      // the reading never goes stale mid-capture.
      sinceIngest += step;
      if (sinceIngest >= 100000) {
        sinceIngest = 0;
        final now = clock.monotonic();
        demo.vehicle.ingest(Sensor.rpm, 750, at: now, receivedAt: now);
        demo.vehicle.ingest(Sensor.speed, 0, at: now, receivedAt: now);
        demo.vehicle.ingest(Sensor.coolant, 60, at: now, receivedAt: now);
      }
      left -= step;
    }
    await tester.pump();
    await capturePng(tester, 'apex-cluster-parked');

    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
