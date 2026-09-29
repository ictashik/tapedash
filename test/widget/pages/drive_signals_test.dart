// DriveSignals: real VehicleState sensors bound to live SmoothedSignals, the
// ConnectionStatus -> AdapterLinkState mapping, and that dispose cleans up
// what it owns.
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/core/observable.dart';
import 'package:tapedash/obd/obd_session.dart';
import 'package:tapedash/ui/design/components/status_strip.dart';
import 'package:tapedash/ui/design/motion/ignition_sequence.dart';
import 'package:tapedash/ui/design/motion/motion_clock.dart';
import 'package:tapedash/ui/design/tokens/motion_tokens.dart';
import 'package:tapedash/ui/pages/drive/drive_signals.dart';
import 'package:tapedash/vehicle/sensor.dart';
import 'package:tapedash/vehicle/vehicle_state.dart';

void main() {
  late ManualMotionClock motion;
  late FakeClock clock;
  late VehicleState vehicle;
  late ObservableValue<ConnectionStatus> connection;
  late DriveSignals signals;

  setUp(() {
    motion = ManualMotionClock();
    clock = FakeClock()..advance(const Duration(seconds: 100));
    vehicle = VehicleState(clock: clock, scheduler: clock);
    connection = ObservableValue(ConnectionStatus.searching);
    signals = DriveSignals(
      vehicle: vehicle,
      motion: motion,
      clock: clock,
      scheduler: clock,
      connection: connection,
    );
  });

  tearDown(() {
    signals.dispose();
    motion.dispose();
  });

  void ingest(Sensor sensor, double value) {
    final now = clock.monotonic();
    vehicle.ingest(sensor, value, at: now, receivedAt: now);
  }

  void run(Duration duration) {
    var left = duration.inMicroseconds;
    const frame = 16667;
    while (left > 0) {
      final step = left < frame ? left : frame;
      motion.tick(step / 1e6);
      clock.advance(Duration(microseconds: step));
      left -= step;
    }
  }

  group('binding', () {
    test('rpm, speed, coolant and throttle follow the vehicle', () {
      expect(signals.rpm.hasValue, isFalse);
      ingest(Sensor.rpm, 2200);
      ingest(Sensor.speed, 62);
      ingest(Sensor.coolant, 91);
      ingest(Sensor.throttle, 18);
      run(const Duration(seconds: 1));

      expect(signals.rpm.value, closeTo(2200, 1));
      expect(signals.speed.value, closeTo(62, 1));
      expect(signals.coolant.value, closeTo(91, 1));
      expect(signals.throttle.value, closeTo(18, 1));
    });

    test('a later reading retargets the same signal, not a new one', () {
      ingest(Sensor.rpm, 1000);
      run(const Duration(seconds: 1));
      final first = signals.rpm.value;

      ingest(Sensor.rpm, 4000);
      run(const Duration(seconds: 1));

      expect(signals.rpm.value, isNot(first));
      expect(signals.rpm.value, closeTo(4000, 1));
    });
  });

  group('mode', () {
    test('reflects VehicleState.mode directly', () {
      expect(signals.mode.value, DrivingMode.parked);
      ingest(Sensor.rpm, 1500);
      ingest(Sensor.speed, 40);
      run(const Duration(seconds: 1));
      expect(signals.mode.value, DrivingMode.motion);
    });
  });

  group('parkedShare (DESIGN.md 7.2)', () {
    test('starts parked with a parked vehicle, at rest', () {
      expect(signals.mode.value, DrivingMode.parked);
      expect(signals.parkedShare.value, 1);
      // Searching turns the connection beam (DESIGN.md 7.12), which does ask
      // for frames; the share itself is at rest once connected.
      connection.value = ConnectionStatus.connected;
      run(const Duration(seconds: 2));
      expect(motion.attachedCount, 0);
    });

    test('the car starting to move returns it inside the 300 ms budget', () {
      ingest(Sensor.rpm, 1500);
      ingest(Sensor.speed, 40);
      run(TapeMotion.motionReturn);

      expect(signals.mode.value, DrivingMode.motion);
      expect(signals.parkedShare.value, closeTo(0, 0.05));
    });

    test(
      'parks again after its 5 s stop dwell, from wherever the fall had got',
      () {
        ingest(Sensor.rpm, 1500);
        ingest(Sensor.speed, 40);
        run(TapeMotion.motionReturn);
        // An immediate stop: the park dwell runs from here, and the screen is
        // still mid-return to motion when the park takes over from it.
        ingest(Sensor.speed, 0);
        run(const Duration(seconds: 6));

        expect(signals.mode.value, DrivingMode.parked);
        expect(signals.parkedShare.value, closeTo(1, 0.05));
      },
    );
  });

  group('adapter (DESIGN.md 6.9)', () {
    test('connected and waiting-for-ignition both read as flowing', () {
      connection.value = ConnectionStatus.connected;
      expect(signals.adapter.value, AdapterLinkState.flowing);
      connection.value = ConnectionStatus.waitingForIgnition;
      expect(signals.adapter.value, AdapterLinkState.flowing);
    });

    test('stopped and searching both read as searching', () {
      connection.value = ConnectionStatus.stopped;
      expect(signals.adapter.value, AdapterLinkState.searching);
      connection.value = ConnectionStatus.searching;
      expect(signals.adapter.value, AdapterLinkState.searching);
    });

    test('lost reads as lost', () {
      connection.value = ConnectionStatus.lost;
      expect(signals.adapter.value, AdapterLinkState.lost);
    });

    test('updates live as the connection changes, without re-subscribing', () {
      var notifications = 0;
      signals.adapter.addListener(() => notifications++);
      connection.value = ConnectionStatus.connected;
      expect(notifications, greaterThan(0));
      expect(signals.adapter.value, AdapterLinkState.flowing);
    });
  });

  group('gpsHasFix and phoneHot (DESIGN.md 13, phase 4 gaps)', () {
    test('are a plain, honest "not yet", not invented data', () {
      expect(signals.gpsHasFix.value, isFalse);
      expect(signals.phoneHot.value, isFalse);
    });
  });

  group('acceleration (DESIGN.md 6.11)', () {
    test('longitudinal follows VehicleState.motion as the car speeds up', () {
      expect(signals.longitudinalAcceleration.hasValue, isFalse);
      // A rising speed over real time gives VehicleState.motion a positive
      // acceleration sample (CLAUDE.md 8.8's smoothed-speed delta).
      ingest(Sensor.speed, 0);
      run(const Duration(milliseconds: 500));
      ingest(Sensor.speed, 20);
      run(const Duration(milliseconds: 500));
      ingest(Sensor.speed, 40);
      run(const Duration(seconds: 1));

      expect(signals.longitudinalAcceleration.hasValue, isTrue);
      expect(signals.longitudinalAcceleration.value, greaterThan(0));
    });

    test('lateral has no source yet: never ingested into, honestly', () {
      ingest(Sensor.speed, 40);
      run(const Duration(seconds: 2));
      expect(signals.lateralAcceleration.hasValue, isFalse);
    });
  });

  group('the ignition sequence (DESIGN.md 7.13)', () {
    test('plays on the first rpm above 400 once connected, and not before', () {
      ingest(Sensor.rpm, 900);
      expect(signals.ignition.isRunning, isFalse, reason: 'not connected yet');

      connection.value = ConnectionStatus.connected;
      expect(signals.ignition.isRunning, isTrue);
      expect(signals.rpm.isHeld, isTrue, reason: 'the needle sweeps');
    });

    test('an engine that is not running (rpm 400 or below) does not', () {
      connection.value = ConnectionStatus.connected;
      ingest(Sensor.rpm, 300);
      expect(signals.ignition.isRunning, isFalse);

      ingest(Sensor.rpm, 850);
      expect(signals.ignition.isRunning, isTrue);
    });

    test('plays once per connection: a lost link and back is not a replay', () {
      connection.value = ConnectionStatus.connected;
      ingest(Sensor.rpm, 900);
      run(const Duration(seconds: 2));
      expect(signals.ignition.isRunning, isFalse);

      connection.value = ConnectionStatus.lost;
      connection.value = ConnectionStatus.connected;
      expect(signals.ignition.isRunning, isFalse);
    });

    test('the ignition going off and on again plays it again', () {
      connection.value = ConnectionStatus.connected;
      ingest(Sensor.rpm, 900);
      run(const Duration(seconds: 2));

      connection.value = ConnectionStatus.waitingForIgnition;
      connection.value = ConnectionStatus.connected;
      ingest(Sensor.rpm, 950);
      expect(signals.ignition.isRunning, isTrue);
    });

    test('never delays live data: the needle lands on the live rpm', () {
      connection.value = ConnectionStatus.connected;
      ingest(Sensor.rpm, 900);
      run(const Duration(milliseconds: 300));
      ingest(Sensor.rpm, 2000);
      run(const Duration(seconds: 2));

      expect(signals.rpm.value, closeTo(2000, 30));
    });

    test('shutdown: the needle falls to 0 on its own spring', () {
      connection.value = ConnectionStatus.connected;
      ingest(Sensor.rpm, 900);
      run(const Duration(seconds: 2));

      ingest(Sensor.rpm, 0);
      run(const Duration(seconds: 1));

      expect(signals.rpm.value, closeTo(0, 5));
    });

    test('Off never holds anything', () {
      signals.dispose();
      signals = DriveSignals(
        vehicle: vehicle,
        motion: motion,
        clock: clock,
        scheduler: clock,
        connection: connection,
        ignitionMode: IgnitionMode.off,
      );
      connection.value = ConnectionStatus.connected;
      ingest(Sensor.rpm, 900);

      expect(signals.ignition.isRunning, isFalse);
      expect(signals.rpm.isHeld, isFalse);
    });
  });
}
