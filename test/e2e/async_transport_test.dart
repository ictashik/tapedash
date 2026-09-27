// The stack over a transport that delivers a microtask late, as Bluetooth and
// WiFi do, and not at once as the simulator's does. The layers must not depend
// on data arriving inside the call that caused it.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/sim/adapter_quirks.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

import '../support/async_transport.dart';

/// Advances the clock in small steps, letting the microtasks run in between, as
/// the event loop would.
Future<void> pump(
  FakeClock clock,
  Duration total, {
  Duration step = const Duration(milliseconds: 2),
}) async {
  var elapsed = Duration.zero;
  while (elapsed < total) {
    clock.advance(step);
    elapsed += step;
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  test('it connects, starts up, polls, and reads what the car does', () async {
    final clock = FakeClock();
    final car = SimulatedCar(
      scenario: DriveScenarios.cityStopGo,
      scheduler: clock,
    )..start();
    final sim = SimTransport(car: car, scheduler: clock);
    final transport = AsyncTransport(sim);
    final vehicle = VehicleState(clock: clock, scheduler: clock);
    final session = ObdSession(
      transport: transport,
      scheduler: clock,
      clock: clock,
      vehicle: vehicle,
    )..start();
    addTearDown(() async {
      session.dispose();
      vehicle.dispose();
      car.stop();
      await transport.dispose();
      await sim.dispose();
    });
    final statuses = <ConnectionStatus>[];
    session.status.addListener(() => statuses.add(session.status.value));

    await pump(clock, const Duration(seconds: 40));

    expect(statuses, [ConnectionStatus.connected]);
    expect(session.adapterInfo.value!.protocolNumber, '6');
    final rpm = vehicle.rpm.value!;
    expect(vehicle.isStale(Sensor.rpm), isFalse);
    expect((rpm.value - car.state.rpm).abs(), lessThan(400));
    expect(session.pollRate.value, greaterThan(10));
  });

  test('over a Bluetooth clone, and after a dropped link', () async {
    final clock = FakeClock();
    final car = SimulatedCar(
      scenario: DriveScenarios.adapterFlaky,
      scheduler: clock,
    )..start();
    final sim = SimTransport(
      car: car,
      scheduler: clock,
      quirks: AdapterQuirks.bluetoothClone,
    );
    final transport = AsyncTransport(sim);
    final vehicle = VehicleState(clock: clock, scheduler: clock);
    final session = ObdSession(
      transport: transport,
      scheduler: clock,
      clock: clock,
      vehicle: vehicle,
    )..start();
    addTearDown(() async {
      session.dispose();
      vehicle.dispose();
      car.stop();
      await transport.dispose();
      await sim.dispose();
    });
    final statuses = <ConnectionStatus>[];
    session.status.addListener(() => statuses.add(session.status.value));

    // Over the drop at four minutes, in steps of 5 ms.
    await pump(
      clock,
      const Duration(minutes: 5),
      step: const Duration(milliseconds: 5),
    );

    expect(statuses, [
      ConnectionStatus.connected,
      ConnectionStatus.lost,
      ConnectionStatus.connected,
    ]);
    expect(vehicle.isStale(Sensor.rpm), isFalse);
  });
}
