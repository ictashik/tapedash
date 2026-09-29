// The connection states (DESIGN.md 7.12) on the Drive page: searching, waiting
// for ignition, lost, and the re-light. Skipped unless TAPEDASH_CAPTURE_DIR
// is set.
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
import 'package:tapedash/ui/pages/drive/drive_page.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../support/harness.dart';

void main() {
  final enabled = Platform.environment['TAPEDASH_CAPTURE_DIR'] != null;
  setUpAll(loadTapeFonts);

  testWidgets('searching, waiting, lost, re-light', (tester) async {
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

    void run(int ms, {bool live = false}) {
      var left = ms * 1000;
      var since = 0;
      while (left > 0) {
        motion.tick(16667 / 1e6);
        clock.advance(const Duration(microseconds: 16667));
        left -= 16667;
        since += 16667;
        if (live && since >= 100000) {
          since = 0;
          feed();
        }
      }
    }

    await tester.pumpWidget(
      tapeHarness(
        kit: kit,
        motion: motion,
        theme: TapeThemeData(livery: Liveries.ion),
        child: TapeBackdrop(
          child: DrivePage(
            signals: signals,
            motion: motion,
            width: 800,
            height: 400,
          ),
        ),
      ),
    );
    run(700);
    await tester.pump();
    await capturePng(tester, 'connection-searching');

    connection.value = ConnectionStatus.waitingForIgnition;
    run(2000);
    await tester.pump();
    await capturePng(tester, 'connection-waiting');

    connection.value = ConnectionStatus.connected;
    feed();
    run(2500, live: true);
    connection.value = ConnectionStatus.lost;
    run(3000);
    await tester.pump();
    await capturePng(tester, 'connection-lost');

    connection.value = ConnectionStatus.connected;
    feed();
    run(100);
    await tester.pump();
    await capturePng(tester, 'connection-relight');

    signals.dispose();
    motion.dispose();
    kit.dispose();
  }, skip: !enabled);
}
