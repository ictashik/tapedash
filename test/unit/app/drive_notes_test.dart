// What a drive writes about itself into the session recording (`LiveDrive.note`):
// the setup, each change of the connection, the engine, the mode and the trip,
// and the money's numbers every 5 s. It is what a log needs to show why a trip
// ended or why a figure is what it is.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/app/app_services.dart';
import 'package:tapedash/app/drive_services.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

void main() {
  late FakeClock clock;
  late VehicleState vehicle;
  late ObservableValue<ConnectionStatus> connection;
  late DriveServices services;
  late List<String> notes;

  setUp(() async {
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    connection = ObservableValue(ConnectionStatus.connected);
    final app = await AppServices.memory(price: 115);
    notes = [];
    services = DriveServices(
      vehicle: vehicle,
      connection: connection,
      app: app,
      clock: clock,
      scheduler: clock,
      note: notes.add,
    );
  });

  tearDown(() async {
    await services.close();
    vehicle.dispose();
  });

  void feed(Sensor s, double v) {
    clock.advance(const Duration(milliseconds: 1));
    final now = clock.monotonic();
    vehicle.ingest(s, v, at: now, receivedAt: now);
  }

  test('it begins with the setup: fuel, blend, engine, tank, price', () {
    expect(
      notes.first,
      startsWith('setup petrol E20 1.5 L, tank 40 L, price 115.00'),
    );
    expect(notes.first, contains('calibration 1.000'));
  });

  test(
    'the connection, the engine, the mode and the trip are said as they change',
    () {
      feed(Sensor.voltage, 14.1);
      feed(Sensor.speed, 0);
      feed(Sensor.rpm, 800);
      expect(notes, contains('engine on (rpm 800, volts 14.1)'));
      expect(notes, contains('trip running'));

      connection.value = ConnectionStatus.waitingForIgnition;
      expect(notes.last, 'status waitingForIgnition');
      expect(notes, contains('trip ending'));

      clock.advance(const Duration(seconds: 11));
      expect(notes, contains('trip ended'));
    },
  );

  test('every 5 s the numbers the money is made of', () {
    feed(Sensor.rpm, 800);
    feed(Sensor.speed, 0);
    feed(Sensor.airFlow, 2.5);
    for (var i = 0; i < 12; i++) {
      clock.advance(const Duration(seconds: 1));
      feed(Sensor.rpm, 800);
      feed(Sensor.speed, 0);
      feed(Sensor.airFlow, 2.5);
    }

    final vitals = notes.where((n) => n.startsWith('vitals ')).toList();
    expect(vitals.length, inInclusiveRange(2, 3));
    expect(vitals.last, contains('kmh=0'));
    expect(vitals.last, contains('rpm=800'));
    expect(vitals.last, contains('maf=2.50'));
    expect(vitals.last, contains('src=MAF'));
    expect(vitals.last, contains('idle_s='));
  });

  test('after close it says nothing more', () async {
    await services.close();
    final before = notes.length;

    connection.value = ConnectionStatus.lost;
    clock.advance(const Duration(seconds: 30));

    expect(notes.length, before);
  });
}
