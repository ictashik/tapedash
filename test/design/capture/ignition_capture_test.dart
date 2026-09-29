// The ignition sequence (DESIGN.md 7.13) on the Apex cluster, at three moments
// of its 1.2 s. Skipped unless TAPEDASH_CAPTURE_DIR is set.
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/components/backdrop.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/render/render_kit.dart';
import 'package:tapedash/ui/design/theme/tape_theme.dart';
import 'package:tapedash/ui/design/tokens/livery.dart';
import 'package:tapedash/ui/pages/drive/apex_cluster.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('Apex at 250, 550 and 850 ms of the ignition', (tester) async {
    setWindow(tester, const Size(800, 400));
    final kit = TapeRenderKit();
    final motion = ManualMotionClock();
    final clock = FakeClock()..advance(const Duration(seconds: 100));
    final vehicle = VehicleState(clock: clock, scheduler: clock);
    final connection = ObservableValue(ConnectionStatus.searching);
    final signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: connection,
    );
    void feed() {
      final now = clock.monotonic();
      vehicle.ingest(Sensor.rpm, 1800, at: now, receivedAt: now);
      vehicle.ingest(Sensor.speed, 62, at: now, receivedAt: now);
      vehicle.ingest(Sensor.coolant, 88, at: now, receivedAt: now);
    }

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
    feed();
    connection.value = ConnectionStatus.connected;

    var elapsed = 0;
    for (final (ms, name) in [
      (250, 'ignition-250ms'),
      (550, 'ignition-550ms'),
      (850, 'ignition-850ms'),
    ]) {
      while (elapsed < ms * 1000) {
        motion.tick(16667 / 1e6);
        clock.advance(const Duration(microseconds: 16667));
        elapsed += 16667;
        if (elapsed % 100000 < 16667) feed();
      }
      await tester.pump();
      await capturePng(tester, name);
    }

    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
