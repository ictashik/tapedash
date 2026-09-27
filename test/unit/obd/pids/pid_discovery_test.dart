import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/core/fake_clock.dart';
import 'package:tapedash/obd/elm327/elm327_client.dart';
import 'package:tapedash/obd/elm327/elm327_failure.dart';
import 'package:tapedash/obd/pids/pid_discovery.dart';
import 'package:tapedash/obd/transport/sim_transport.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';

import '../../../support/fake_transport.dart';

void main() {
  group('a support reply', () {
    test('the top bit is the first PID of the range', () {
      final support = PidSupport.decode(0x00, [0x80, 0, 0, 0]);

      expect(support.pids, {0x01});
      expect(support.nextRange, isFalse);
    });

    test('the bit before the last is the 31st PID', () {
      final support = PidSupport.decode(0x00, [0, 0, 0, 0x02]);

      expect(support.pids, {0x1F});
      expect(support.nextRange, isFalse);
    });

    test('the last bit is the flag for the next range, not a PID', () {
      final support = PidSupport.decode(0x00, [0, 0, 0, 0x01]);

      expect(support.pids, isEmpty);
      expect(support.nextRange, isTrue);
    });

    test('nothing set is nothing supported', () {
      final support = PidSupport.decode(0x20, [0, 0, 0, 0]);

      expect(support.pids, isEmpty);
      expect(support.nextRange, isFalse);
    });

    test('every bit set is 31 PIDs and the flag', () {
      final support = PidSupport.decode(0x20, [0xFF, 0xFF, 0xFF, 0xFF]);

      expect(support.pids, {for (var p = 0x21; p <= 0x3F; p++) p});
      expect(support.nextRange, isTrue);
    });

    test('a range starts after its own number', () {
      expect(PidSupport.decode(0x20, [0, 0x02, 0, 0x01]).pids, {0x2F});
      expect(PidSupport.decode(0x40, [0x40, 0, 0, 0]).pids, {0x42});
      expect(PidSupport.decode(0x40, [0, 0, 0, 0x04]).pids, {0x5E});
      expect(PidSupport.decode(0x60, [0x80, 0, 0, 0]).pids, {0x61});
    });

    test(
      'worked out by hand: 98 3B 80 01 is 01 04 05 0B 0C 0D 0F 10 11 and more',
      () {
        // 98 is 1001 1000: PIDs 01, 04, 05. 3B is 0011 1011: PIDs 0B, 0C, 0D,
        // 0F, 10. 80 is 1000 0000: PID 11. 01: the next range.
        final support = PidSupport.decode(0x00, [0x98, 0x3B, 0x80, 0x01]);

        expect(support.pids, {
          0x01,
          0x04,
          0x05,
          0x0B,
          0x0C,
          0x0D,
          0x0F,
          0x10,
          0x11,
        });
        expect(support.nextRange, isTrue);
      },
    );

    test('the datasheet\'s BE 1F B8 10', () {
      // BE is 1011 1110: PIDs 01, 03, 04, 05, 06, 07. 1F is 0001 1111: PIDs 0C
      // to 10. B8 is 1011 1000: PIDs 11, 13, 14, 15. 10 is 0001 0000: PID 1C.
      final support = PidSupport.decode(0x00, [0xBE, 0x1F, 0xB8, 0x10]);

      expect(support.pids, {
        0x01, 0x03, 0x04, 0x05, 0x06, 0x07, //
        0x0C, 0x0D, 0x0E, 0x0F, 0x10,
        0x11, 0x13, 0x14, 0x15, 0x1C,
      });
      expect(support.nextRange, isFalse);
    });

    test('the wrong number of bytes is refused', () {
      expect(() => PidSupport.decode(0, [0, 0, 0]), throwsArgumentError);
      expect(() => PidSupport.decode(0, [0, 0, 0, 0, 0]), throwsArgumentError);
    });
  });

  group('asking', () {
    late FakeClock clock;
    late FakeTransport transport;
    late Elm327Client client;
    late List<DiscoveryResult> results;

    setUp(() {
      clock = FakeClock();
      transport = FakeTransport(clock: clock);
      client = Elm327Client(
        transport: transport,
        scheduler: clock,
        clock: clock,
      );
      results = [];
    });

    tearDown(() {
      client.dispose();
      transport.dispose();
    });

    /// The car says [reply] to the request just written.
    void answer(String reply) {
      clock.advance(const Duration(milliseconds: 30));
      transport.receive('$reply\r\r>');
    }

    test('one range, when the last bit is clear', () {
      PidDiscovery.run(client, results.add);

      expect(transport.writes, ['0100\r']);
      answer('41 00 98 18 80 00');

      expect(results.single.ok, isTrue);
      expect(results.single.supported, {0x01, 0x04, 0x05, 0x0C, 0x0D, 0x11});
      expect(results.single.ecuCount, 1);
      expect(transport.writes, ['0100\r']);
    });

    test('each next range while the last bit is set', () {
      PidDiscovery.run(client, results.add);

      answer('41 00 98 3B 80 01');
      expect(transport.writes.last, '0120\r');
      answer('41 20 00 02 00 01');
      expect(transport.writes.last, '0140\r');
      answer('41 40 40 00 00 00');

      expect(transport.writes, ['0100\r', '0120\r', '0140\r']);
      expect(results.single.supported, {
        0x01, 0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F, 0x10, 0x11, //
        0x2F,
        0x42,
      });
    });

    test('the support PIDs themselves are not in the result', () {
      PidDiscovery.run(client, results.add);
      answer('41 00 98 3B 80 01');
      answer('41 20 00 02 00 01');
      answer('41 40 40 00 00 00');

      for (final range in PidDiscovery.ranges) {
        expect(results.single.supported, isNot(contains(range)));
      }
    });

    test('it stops at the last range even if the flag says more', () {
      PidDiscovery.run(client, results.add);
      for (final base in PidDiscovery.ranges) {
        expect(
          transport.writes.last,
          '01${base.toRadixString(16).padLeft(2, '0').toUpperCase()}\r',
        );
        answer('41 ${base.toRadixString(16).padLeft(2, '0')} 00 00 00 01');
      }

      expect(transport.writes.length, 7);
      expect(results.single.ok, isTrue);
      expect(results.single.supported, isEmpty);
    });

    test('two ECUs give the union, and the count', () {
      PidDiscovery.run(client, results.add);

      clock.advance(const Duration(milliseconds: 30));
      transport.receive('41 00 98 18 80 00\r41 00 80 00 00 00\r\r>');

      expect(results.single.supported, {0x01, 0x04, 0x05, 0x0C, 0x0D, 0x11});
      expect(results.single.ecuCount, 2);
    });

    test('a next range flagged by only one ECU is asked', () {
      PidDiscovery.run(client, results.add);
      clock.advance(const Duration(milliseconds: 30));
      transport.receive('41 00 98 18 80 00\r41 00 80 00 00 01\r\r>');

      expect(transport.writes.last, '0120\r');
    });

    test('an answer to some other PID is skipped', () {
      PidDiscovery.run(client, results.add);

      answer('41 0D 32');
      expect(results, isEmpty);
      answer('41 00 98 18 80 00');

      expect(results.single.ok, isTrue);
    });

    test('the first request failing is the failure of discovery', () {
      PidDiscovery.run(client, results.add);

      answer('SEARCHING...\rUNABLE TO CONNECT');

      expect(results.single.ok, isFalse);
      expect(results.single.failure, Elm327Failure.unableToConnect);
      expect(results.single.searched, isTrue);
      expect(results.single.supported, isEmpty);
    });

    test('NO DATA at the start is a failure too', () {
      PidDiscovery.run(client, results.add);

      answer('NO DATA');

      expect(results.single.failure, Elm327Failure.noData);
    });

    test('a later range failing ends discovery with what it has', () {
      PidDiscovery.run(client, results.add);
      answer('41 00 98 3B 80 01');

      answer('NO DATA');

      expect(results.single.ok, isTrue);
      expect(results.single.supported, {
        0x01,
        0x04,
        0x05,
        0x0B,
        0x0C,
        0x0D,
        0x0F,
        0x10,
        0x11,
      });
    });

    test('a support reply of the wrong length is a failure at the start', () {
      PidDiscovery.run(client, results.add);

      answer('41 00 98 18 80');

      expect(results.single.ok, isFalse);
      expect(results.single.failure, Elm327Failure.garbled);
    });

    test('the first request is given the long timeout', () {
      PidDiscovery.run(
        client,
        results.add,
        firstTimeout: const Duration(seconds: 12),
      );

      clock.advance(const Duration(seconds: 11));
      expect(results, isEmpty);
      clock.advance(const Duration(seconds: 1));

      expect(results.single.failure, Elm327Failure.timeout);
    });

    test('the later ranges get the ordinary timeout', () {
      PidDiscovery.run(
        client,
        results.add,
        firstTimeout: const Duration(seconds: 12),
      );
      answer('41 00 98 3B 80 01');

      clock.advance(const Duration(milliseconds: 1500));

      expect(results.single.ok, isTrue);
    });

    test(
      'the requests carry no count digit, since the ECUs are not yet known',
      () {
        PidDiscovery.run(client, results.add);
        answer('41 00 98 3B 80 01');
        answer('41 20 00 00 00 00');

        expect(transport.writes, ['0100\r', '0120\r']);
      },
    );
  });

  group('against each simulated car', () {
    for (final profile in VehicleProfiles.all) {
      test(profile.name, () {
        final clock = FakeClock();
        final car = SimulatedCar(
          scenario: DriveScenarios.cityStopGo,
          profile: profile,
          scheduler: clock,
        )..start();
        final transport = SimTransport(car: car, scheduler: clock);
        transport.connect().catchError((Object _) {});
        clock.advance(const Duration(seconds: 1));
        final client = Elm327Client(
          transport: transport,
          scheduler: clock,
          clock: clock,
        );
        addTearDown(() {
          client.dispose();
          car.stop();
          transport.dispose();
        });
        // Start the car and the adapter as the app will.
        for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP0']) {
          client.command(c, (_) {}, timeout: const Duration(seconds: 5));
          clock.advance(const Duration(seconds: 2));
        }
        clock.advance(const Duration(seconds: 5));
        DiscoveryResult? result;

        PidDiscovery.run(
          client,
          (r) => result = r,
          firstTimeout: const Duration(seconds: 12),
        );
        clock.advance(const Duration(seconds: 30));

        expect(result!.ok, isTrue);
        expect(result!.supported, {0x01, ...profile.supportedPids});
        expect(result!.ecuCount, 1);
        expect(result!.searched, isTrue);
      });
    }
  });
}
