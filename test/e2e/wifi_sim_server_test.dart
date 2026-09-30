// The production WiFi path, end to end and in real time (CLAUDE.md 7.5): the real
// WifiTransport, over a real socket, to tool/sim_server.dart, read by the real
// OBD session into a VehicleState. Only the hardware is missing.

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/clock.dart';
import 'package:tapedash/core/scheduler.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/wifi_transport.dart';
import 'package:tapedash/sim/ecu.dart';
import 'package:tapedash/sim/elm327_simulator.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../../tool/sim_server.dart';

void main() {
  test(
    'a car on a WiFi adapter shows live values through the real transport',
    () async {
      const clock = SystemClock();
      const scheduler = SystemScheduler();
      final scenario = DriveScenarios.cityStopGo;
      final car = SimulatedCar(
        scenario: scenario,
        profile: VehicleProfiles.petrolCvtMap,
        scheduler: scheduler,
      );
      final server = SimServer(
        car: car,
        adapter: Elm327Simulator(
          ecu: SimulatedEcu(car: car),
          quirks: scenario.quirks,
        ),
        port: 0,
      );
      await server.start();
      addTearDown(server.close);

      final transport = WifiTransport(
        host: '127.0.0.1',
        port: server.boundPort,
      );
      final vehicle = VehicleState(clock: clock, scheduler: scheduler);
      addTearDown(vehicle.dispose);
      final session = ObdSession(
        transport: transport,
        scheduler: scheduler,
        clock: clock,
        vehicle: vehicle,
      );
      addTearDown(() async {
        session.stop();
        session.dispose();
        await transport.dispose();
      });
      session.start();

      Future<void> until(bool Function() done, String what) async {
        final end = DateTime.now().add(const Duration(seconds: 25));
        while (!done()) {
          if (DateTime.now().isAfter(end)) {
            fail(
              'timed out waiting for $what (status ${session.status.value})',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }

      await until(
        () => session.status.value == ConnectionStatus.connected,
        'connected',
      );
      await until(
        () => vehicle.reading(Sensor.rpm).value != null,
        'an rpm reading',
      );
      final info = session.adapterInfo.value!;
      expect(info.banner, contains('ELM327'));
      expect(info.isCan, isTrue);
      expect(info.supportedPids, contains(0x0C));
      expect(
        vehicle.reading(Sensor.rpm).value!.value,
        inInclusiveRange(300, 7000),
      );

      // It keeps polling: the numbers move as the car drives away from rest.
      await until(
        () => (vehicle.reading(Sensor.speed).value?.value ?? 0) > 5,
        'the car to move',
      );
      expect(session.pollRate.value, greaterThan(1));
    },
    timeout: const Timeout(Duration(seconds: 45)),
  );

  test(
    'unplugging the adapter: the link is lost, and it comes back',
    () async {
      const clock = SystemClock();
      const scheduler = SystemScheduler();
      final scenario = DriveScenarios.cityStopGo;
      final car = SimulatedCar(scenario: scenario, scheduler: scheduler);
      var server = SimServer(
        car: car,
        adapter: Elm327Simulator(
          ecu: SimulatedEcu(car: car),
          quirks: scenario.quirks,
        ),
        port: 0,
      );
      await server.start();
      final port = server.boundPort;

      final transport = WifiTransport(host: '127.0.0.1', port: port);
      final vehicle = VehicleState(clock: clock, scheduler: scheduler);
      addTearDown(vehicle.dispose);
      final session = ObdSession(
        transport: transport,
        scheduler: scheduler,
        clock: clock,
        vehicle: vehicle,
      );
      addTearDown(() async {
        session.stop();
        session.dispose();
        await transport.dispose();
        await server.close();
      });
      session.start();

      Future<void> until(bool Function() done, String what) async {
        final end = DateTime.now().add(const Duration(seconds: 25));
        while (!done()) {
          if (DateTime.now().isAfter(end)) {
            fail(
              'timed out waiting for $what (status ${session.status.value})',
            );
          }
          await Future<void>.delayed(const Duration(milliseconds: 25));
        }
      }

      await until(
        () => session.status.value == ConnectionStatus.connected,
        'connected',
      );
      // Pull the plug: the server goes away.
      await server.close();
      await until(
        () => session.status.value == ConnectionStatus.lost,
        'the link to be lost',
      );
      expect(session.status.value, ConnectionStatus.lost);

      // Plugged back in, on the same address.
      server = SimServer(
        car: SimulatedCar(scenario: scenario, scheduler: scheduler),
        adapter: Elm327Simulator(
          ecu: SimulatedEcu(car: car),
          quirks: scenario.quirks,
        ),
        port: port,
      );
      await server.start();
      await until(
        () => session.status.value == ConnectionStatus.connected,
        'it to reconnect',
      );
    },
    timeout: const Timeout(Duration(seconds: 60)),
  );
}
