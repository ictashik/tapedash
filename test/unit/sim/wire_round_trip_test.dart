// The whole simulator seen from the wire: the car, its ECU and the adapter,
// asked in ELM327 text and answered in it. What comes out is decoded with the
// formulas of CLAUDE.md 8.3 and compared with what the car was doing, which is
// the check that the text is a faithful picture of the car and that a client
// can get every value back out of it (CLAUDE.md 10, Layer 2).
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/ecu.dart';
import 'package:tapedash/sim/elm327_simulator.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';

/// How many data bytes each PID carries.
const Map<int, int> _length = {
  0x04: 1,
  0x05: 1,
  0x0B: 1,
  0x0C: 2,
  0x0D: 1,
  0x0F: 1,
  0x10: 2,
  0x11: 1,
  0x2F: 1,
  0x42: 2,
  0x5E: 2,
};

/// The ECU's message in an adapter's reply, with echo, linefeeds, spaces and
/// headers all off: a single line of hex, or a line count and numbered lines
/// that have to be joined and cut to length.
List<int> _payload(String reply) {
  final lines = reply
      .split('\r')
      .where((l) => l.isNotEmpty && l != '>' && !l.startsWith('SEARCHING'))
      .toList();
  List<int> bytes(String hex) => [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];
  if (lines.length > 1 && lines[1].startsWith('0:')) {
    final total = int.parse(lines.first, radix: 16);
    final joined = [
      for (final l in lines.skip(1)) ...bytes(l.substring(2).trim()),
    ];
    return joined.take(total).toList();
  }
  return bytes(lines.single);
}

/// `41 pid data pid data`, split into a map by PID.
Map<int, List<int>> _byPid(List<int> payload) {
  expect(payload.first, 0x41);
  final out = <int, List<int>>{};
  var i = 1;
  while (i < payload.length) {
    final pid = payload[i];
    final n = _length[pid]!;
    out[pid] = payload.sublist(i + 1, i + 1 + n);
    i += 1 + n;
  }
  expect(i, payload.length, reason: 'the message is all accounted for');
  return out;
}

double _word(List<int> d) => (256 * d[0] + d[1]).toDouble();

void main() {
  for (final profile in VehicleProfiles.all) {
    group(profile.name, () {
      late SimulatedCar car;
      late Elm327Simulator adapter;

      setUp(() {
        car = SimulatedCar(
          scenario: profile.name == 'petrol_manual_sporty'
              ? DriveScenarios.spiritedRevs
              : DriveScenarios.cityStopGo,
          profile: profile,
        );
        adapter = Elm327Simulator(ecu: SimulatedEcu(car: car));
        for (final c in ['ATZ', 'ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATSP6']) {
          adapter.execute(c);
        }
        // The engine has to be running for most of these to say anything.
        while (car.elapsedSeconds < 45) {
          car.tick();
        }
      });

      test('the bitmasks list exactly the PIDs the profile has', () {
        final supported = <int>{};
        for (final base in [0x00, 0x20, 0x40]) {
          final hex = base.toRadixString(16).padLeft(2, '0');
          final reply = adapter.execute('01$hex').text;
          if (reply.startsWith('NO DATA')) continue;
          final data = _payload(reply).sublist(2);
          expect(data.length, 4);
          final mask = data.fold<int>(0, (a, b) => (a << 8) | b);
          for (var bit = 0; bit < 32; bit++) {
            if (mask & (1 << (31 - bit)) != 0) supported.add(base + 1 + bit);
          }
        }

        // Each range's own PID is the last bit, and PID 01 is always there.
        supported.removeAll([0x20, 0x40, 0x60]);
        expect(supported, {0x01, ...profile.supportedPids});
      });

      test('every value read as text decodes to what the car was doing', () {
        var readings = 0;
        while (car.elapsedSeconds < 105) {
          for (var i = 0; i < 20; i++) {
            car.tick();
          }
          final s = car.state;
          for (final pid in profile.supportedPids) {
            final hex = pid.toRadixString(16).toUpperCase().padLeft(2, '0');
            final d = _byPid(_payload(adapter.execute('01${hex}1').text))[pid]!;
            final (double got, double truth, double tolerance) = switch (pid) {
              0x04 => (d[0] * 100 / 255, s.loadFraction * 100, 2.5),
              0x05 => (d[0] - 40.0, s.coolantC, 0.51),
              0x0B => (d[0].toDouble(), s.manifoldKpa, 1.6),
              0x0C => (_word(d) / 4, s.rpm, 17.0),
              0x0D => (d[0].toDouble(), s.speedKmh, 0.51),
              0x0F => (d[0] - 40.0, s.intakeAirC, 0.51),
              0x10 => (
                _word(d) / 100,
                s.airGramsPerSecond,
                s.airGramsPerSecond * 0.02 + 0.01,
              ),
              0x11 => (d[0] * 100 / 255, s.throttleFraction * 100, 1.2),
              0x2F => (d[0] * 100 / 255, s.fuelLevelFraction * 100, 0.25),
              0x42 => (_word(d) / 1000, s.voltage, 0.12),
              0x5E => (
                _word(d) / 20,
                s.fuelRateLitresPerHour,
                s.fuelRateLitresPerHour * 0.02 + 0.06,
              ),
              _ => fail('PID $hex is not one of the eleven'),
            };
            expect(got, closeTo(truth, tolerance), reason: 'PID $hex');
            readings++;
          }
        }

        expect(readings, greaterThan(200));
      });

      test('six PIDs in one request come back as one message, in order', () {
        final pids = profile.supportedPids.take(6).toList();
        final request = pids
            .map((p) => p.toRadixString(16).toUpperCase().padLeft(2, '0'))
            .join();
        final s = car.state;

        final reply = adapter.execute('01${request}1').text;
        final got = _byPid(_payload(reply));

        expect(got.keys.toList(), pids, reason: 'in the order asked');
        if (pids.contains(0x0D)) {
          expect(got[0x0D]![0], closeTo(s.speedKmh, 0.51));
        }
        // More than seven bytes means the multi-frame form, unless it fits.
        final bytes = 1 + pids.fold<int>(0, (a, p) => a + 1 + _length[p]!);
        expect(reply.startsWith(RegExp('[0-9A-F]{3}\r0:')), bytes > 7);
      });

      test(
        'with headers on, the same message is CAN frames that reassemble',
        () {
          adapter
            ..execute('ATH1')
            ..execute('ATS1');
          final pids = profile.supportedPids.take(6).toList();
          final request = pids
              .map((p) => p.toRadixString(16).toUpperCase().padLeft(2, '0'))
              .join();

          final reply = adapter.execute('01${request}1').text;
          final frames = reply
              .split('\r')
              .where((l) => l.startsWith('7E8 '))
              .map(
                (l) => l
                    .trim()
                    .split(' ')
                    .skip(1)
                    .map((h) => int.parse(h, radix: 16))
                    .toList(),
              )
              .toList();

          // Every frame is eight bytes. A single frame is its length and the
          // data; a first frame is 1x, the length, and six bytes; the rest are
          // 2n and seven.
          expect(frames, everyElement(hasLength(8)));
          final int length;
          final payload = <int>[];
          if (frames.first.first < 8) {
            length = frames.first.first;
            payload.addAll(frames.first.skip(1));
          } else {
            expect(frames.first.first & 0xF0, 0x10);
            length = ((frames.first[0] & 0x0F) << 8) | frames.first[1];
            payload.addAll(frames.first.skip(2));
            for (var n = 1; n < frames.length; n++) {
              expect(frames[n][0], 0x20 | (n & 0xF));
              payload.addAll(frames[n].skip(1));
            }
          }
          final expected = _byPid(payload.take(length).toList());

          expect(expected.keys.toList(), pids);
        },
      );
    });
  }
}
