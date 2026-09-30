// The Diagnostics page's source over a whole simulated stack: the adapter's
// details, the poll rate, the fuel source, and the fault codes, read and cleared
// through it, and following the session when it is replaced.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/fuel/fuel_estimator.dart';
import 'package:tapedash/obd/diagnostics_source.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/obd/session_diagnostics.dart';
import 'package:tapedash/sim/scenarios.dart';

import 'trip_rig.dart';

void main() {
  test('it shows the adapter, the protocol, the PIDs and the poll rate', () {
    final rig = TripRig(DriveScenarios.dtcPresent);
    addTearDown(rig.close);
    final sessions = ObservableValue<ObdSession?>(rig.rig.session);
    final source = SessionDiagnostics(
      sessions: sessions,
      estimator: rig.estimator,
      vehicle: rig.rig.vehicle,
    );
    addTearDown(source.dispose);
    expect(source.adapterInfo.value, isNull);

    expect(
      rig.rig.runUntil(() => rig.rig.status == ConnectionStatus.connected),
      isTrue,
    );
    rig.rig.run(20);
    final info = source.adapterInfo.value!;
    expect(info.banner, contains('ELM327'));
    expect(protocolName(info.protocolNumber), contains('CAN'));
    expect(info.supportedPids, containsAll([0x0C, 0x0D, 0x11]));
    expect(source.pollRate.value, greaterThan(2));
    expect(source.fuelSource.value, isNot(FuelSource.none));
    expect(source.voltage.value?.value, greaterThan(11));
  });

  test('codes are read through it, and clearing is refused while moving', () {
    final rig = TripRig(DriveScenarios.dtcPresent);
    addTearDown(rig.close);
    final source = SessionDiagnostics(
      sessions: ObservableValue<ObdSession?>(rig.rig.session),
      estimator: rig.estimator,
      vehicle: rig.rig.vehicle,
    );
    addTearDown(source.dispose);
    rig.rig.runUntil(() => rig.rig.status == ConnectionStatus.connected);

    DtcReadResult? read;
    source.readCodes((r) => read = r);
    rig.rig.run(5);
    expect(read!.ok, isTrue);
    expect(read!.stored.map((d) => d.code), ['P0420', 'P0171']);

    expect(rig.rig.runUntil(() => rig.rig.car.state.speedMs > 5), isTrue);
    rig.rig.run(2);
    DtcClearOutcome? outcome;
    source.clearCodes((o) => outcome = o);
    rig.rig.run(2);
    expect(outcome, DtcClearOutcome.notStationary);
    expect(rig.rig.car.storedDtcs, ['P0420', 'P0171']);
  });

  test('with no session it says so instead of saying nothing', () {
    final rig = TripRig(DriveScenarios.dtcPresent);
    addTearDown(rig.close);
    final source = SessionDiagnostics(
      sessions: ObservableValue<ObdSession?>(null),
      estimator: rig.estimator,
      vehicle: rig.rig.vehicle,
    );
    addTearDown(source.dispose);
    DtcReadResult? read;
    DtcClearOutcome? outcome;
    source.readCodes((r) => read = r);
    source.clearCodes((o) => outcome = o);
    expect(read!.ok, isFalse);
    expect(outcome, DtcClearOutcome.failed);
    expect(source.pollRate.value, 0);
  });

  test('it follows the session when it is replaced', () {
    final first = TripRig(DriveScenarios.dtcPresent);
    final second = TripRig(DriveScenarios.cityStopGo);
    addTearDown(first.close);
    addTearDown(second.close);
    final sessions = ObservableValue<ObdSession?>(first.rig.session);
    final source = SessionDiagnostics(
      sessions: sessions,
      estimator: first.estimator,
      vehicle: first.rig.vehicle,
    );
    addTearDown(source.dispose);
    first.rig.runUntil(() => first.rig.status == ConnectionStatus.connected);
    first.rig.run(10);
    expect(source.adapterInfo.value, isNotNull);

    var changes = 0;
    source.adapterInfo.addListener(() => changes++);
    sessions.value = null;
    expect(source.adapterInfo.value, isNull);
    expect(source.pollRate.value, 0);

    second.rig.runUntil(() => second.rig.status == ConnectionStatus.connected);
    sessions.value = second.rig.session;
    expect(
      source.adapterInfo.value,
      same(second.rig.session.adapterInfo.value),
    );
    expect(changes, greaterThanOrEqualTo(2));
  });

  test(
    'protocols are named, and an unknown one is said not to be reported',
    () {
      expect(protocolName('6'), 'ISO 15765-4 CAN, 11-bit, 500 kbaud');
      expect(protocolName('A'), 'SAE J1939 CAN');
      expect(protocolName(null), 'Not reported');
      expect(protocolName('Z'), 'Not reported');
    },
  );
}
