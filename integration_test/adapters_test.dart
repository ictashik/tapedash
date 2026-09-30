// The adapter side of the app on a real Android (CLAUDE.md 10, layer 5): the Kotlin
// channels answer, the recordings folder can be written, and the WiFi transport
// talks to the simulator over a real socket from the phone's own network stack.
//
// Start the simulator on the dev machine first (the emulator reaches it at
// 10.0.2.2):
//
//   dart run tool/sim_server.dart --port 35000 --scenario city_stop_go
//   flutter test integration_test/adapters_test.dart -d emulator-5554
//
// **What this does not do:** there is no Bluetooth adapter to talk to, so the
// Bluetooth channels are only asked what they can do, and what they say when they
// cannot. Pairing, scanning, connecting and the GATT lookup need real hardware
// (docs/HARDWARE_HANDOFF.md).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:tapedash/core/clock.dart';
import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/native_link.dart';
import 'package:tapedash/obd/transport/wifi_transport.dart';
import 'package:tapedash/platform/adapter_radio.dart';
import 'package:tapedash/platform/device_channel.dart';
import 'package:tapedash/platform/file_session_sink.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  for (final kind in RadioKind.values) {
    group(kind.label, () {
      testWidgets('the channel answers, and says what the phone has', (
        tester,
      ) async {
        final status = await AdapterRadio(kind).status();
        // Whatever this phone has, the channel is alive and answers in full.
        // ignore: avoid_print
        print('${kind.label}: $status');
        expect(status.supported || !status.enabled, isTrue);
      });

      testWidgets(
        'without permission or a radio, a request fails with a code',
        (tester) async {
          final radio = AdapterRadio(kind);
          final status = await radio.status();
          // An emulator with Bluetooth has nothing to refuse.
          if (status.ready) return;
          // A search that cannot start says why, as an error on its stream.
          await expectLater(
            radio.scan().toList(),
            throwsA(
              isA<NativeLinkException>().having(
                (e) => e.problem,
                'problem',
                anyOf(
                  NativeLinkProblem.unsupported,
                  NativeLinkProblem.permissionDenied,
                  NativeLinkProblem.radioOff,
                ),
              ),
            ),
          );
          // Opening a link to nothing fails the same way, and never hangs.
          await expectLater(
            radio.link('00:00:00:00:00:00').open(),
            throwsA(anything),
          );
        },
      );
    });
  }

  testWidgets('the recordings folder can be written from the app', (
    tester,
  ) async {
    final device = DeviceChannel();
    final base = await device.externalFilesDirectory();
    expect(base, isNotNull);
    final sink = FileSessionSink(device);
    await sink.save('integration-test.log', '# tapedash-session v1\n');
    final file = File('${sink.directory}/integration-test.log');
    expect(file.existsSync(), isTrue);
    expect(file.readAsStringSync(), contains('tapedash-session'));
    file.deleteSync();
  });

  testWidgets(
    'a car on a WiFi adapter shows live values, from a real phone socket',
    (tester) async {
      const clock = SystemClock();
      const scheduler = SystemScheduler();
      final transport = WifiTransport(host: '10.0.2.2', port: 35000);
      final vehicle = VehicleState(clock: clock, scheduler: scheduler);
      final session = ObdSession(
        transport: transport,
        scheduler: scheduler,
        clock: clock,
        vehicle: vehicle,
      )..start();
      addTearDown(() async {
        session.stop();
        session.dispose();
        await transport.dispose();
        vehicle.dispose();
      });

      Future<void> until(bool Function() done, String what) async {
        final end = DateTime.now().add(const Duration(seconds: 30));
        while (!done()) {
          if (DateTime.now().isAfter(end)) {
            fail(
              'timed out waiting for $what (${session.status.value}); '
              'is tool/sim_server.dart running on the host?',
            );
          }
          await tester.pump(const Duration(milliseconds: 50));
          await Future<void>.delayed(const Duration(milliseconds: 50));
        }
      }

      await until(
        () => session.status.value == ConnectionStatus.connected,
        'the adapter',
      );
      await until(
        () => vehicle.reading(Sensor.rpm).value != null,
        'an rpm reading',
      );
      expect(session.adapterInfo.value!.banner, contains('ELM327'));
      await until(() => session.pollRate.value > 0, 'a poll rate');
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  testWidgets('a public address is refused on the phone too', (tester) async {
    final transport = WifiTransport(host: '8.8.8.8');
    addTearDown(transport.dispose);
    await expectLater(transport.connect(), throwsA(anything));
  });
}
