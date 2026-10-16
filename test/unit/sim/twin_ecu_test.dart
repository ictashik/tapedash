import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/ecu.dart';
import 'package:tapedash/sim/elm327_simulator.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/simulated_car.dart';

/// The ECU's reply to a command, as the lines the app would read: the echo
/// is off, the linefeeds are off and the spaces are off, so each line is plain
/// hex.
List<String> _lines(Elm327Simulator sim, String command) => sim
    .execute(command)
    .text
    .split('\r')
    .where((l) => l.isNotEmpty && l != '>')
    .toList();

Elm327Simulator _twin({bool headers = true}) {
  final car = SimulatedCar(
    scenario: DriveScenarios.cityStopGo,
    profile: VehicleProfiles.surveyTwin,
  );
  while (car.elapsedSeconds < 60) {
    car.tick();
  }
  final sim = Elm327Simulator.forCar(car)
    ..execute('ATE0')
    ..execute('ATL0')
    ..execute('ATS0')
    ..execute('ATH${headers ? 1 : 0}')
    ..execute('ATSP0')
    // The first request opens the session, and the adapter says it is
    // searching; the app has done this by the time it asks for anything.
    ..execute('0100');
  return sim;
}

void main() {
  group('a car with two ECUs on 29-bit CAN', () {
    test('the profile builds two ECUs and says 29-bit', () {
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        profile: VehicleProfiles.surveyTwin,
      );
      expect(SimulatedEcu.forCar(car), hasLength(2));
      expect(VehicleProfiles.surveyTwin.canProtocol, 7);
      expect(VehicleProfiles.byName('petrol_cvt_twin_ecu'), isNotNull);
      // It is not one of the profiles every scenario is run against.
      expect(VehicleProfiles.all, isNot(contains(VehicleProfiles.surveyTwin)));
    });

    test('a one-ECU profile is still one ECU, on 11-bit CAN', () {
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        profile: VehicleProfiles.petrolCvtMaf,
      );
      expect(SimulatedEcu.forCar(car), hasLength(1));
      expect(VehicleProfiles.petrolCvtMaf.canProtocol, 6);
    });

    test('with headers on, each ECU\'s support mask carries its own ID', () {
      final sim = _twin();

      // The masks the first real recordings listed, byte for byte.
      // (Each frame is padded to eight bytes with zeros.) The second ECU's
      // last mask byte is 03 with the engine running: PID 1F, the run time.
      expect(_lines(sim, '0100'), [
        '18DAF110064100983A800100',
        '18DAF111064100BC3FA80300',
      ]);
      expect(_lines(sim, '0120'), [
        '18DAF1100641208005B00100',
        '18DAF1110641208000A00100',
      ]);
      expect(_lines(sim, '0140'), [
        '18DAF110064140CAC0000000',
        '18DAF1110641407AD0000000',
      ]);
    });

    test('with spaces on, a 29-bit ID is printed byte by byte', () {
      final sim = _twin()..execute('ATS1');

      final lines = sim.execute('0100').text.split('\r');
      expect(lines.first, '18 DA F1 10 06 41 00 98 3A 80 01 00 ');
    });

    test('two long answers: only the first ECU is sent flow control', () {
      final sim = _twin();

      // Six PIDs: the first ECU has no MAF, so its answer is shorter, but both
      // are more than one frame.
      final lines = _lines(sim, '010C0D1110040B1');

      expect(lines.where((l) => l.startsWith('18DAF110')), hasLength(2));
      expect(lines.where((l) => l.startsWith('18DAF111')), hasLength(1));
      // The first frames come first, the later frame after them.
      expect(lines[0].startsWith('18DAF110'), isTrue);
      expect(lines[1].startsWith('18DAF111'), isTrue);
      expect(lines[2].startsWith('18DAF110'), isTrue);
    });

    test('ATCRA makes one ECU listen, and its answer is whole', () {
      final sim = _twin();

      expect(_lines(sim, 'ATCRA18DAF111'), ['OK']);
      final lines = _lines(sim, '010C0D1110040B1');

      expect(lines.every((l) => l.startsWith('18DAF111')), isTrue);
      // A first frame, then enough later ones to carry the rest.
      expect(lines.length, greaterThan(1));
      expect(lines.first.substring(8, 10), '10');
      expect(lines[1].substring(8, 10), '21');
    });

    test('ATCRA with no ID puts every ECU back; a bad one is refused', () {
      final sim = _twin();

      sim.execute('ATCRA18DAF111');
      expect(_lines(sim, 'ATCRA'), ['OK']);
      expect(_lines(sim, '0100'), hasLength(2));
      expect(_lines(sim, 'ATCRA18DAF1'), ['?']);
      expect(_lines(sim, 'ATCRAXYZ'), ['?']);
    });

    test('a reset puts the filter back, as it does every setting', () {
      final sim = _twin();

      sim.execute('ATCRA18DAF111');
      sim.execute('ATZ');
      sim
        ..execute('ATE0')
        ..execute('ATL0')
        ..execute('ATS0')
        ..execute('ATH1');

      // (The adapter searches again after a reset, and says so.)
      expect(
        _lines(sim, '0100').where((l) => l.startsWith('18DAF1')),
        hasLength(2),
      );
    });

    test('an ID the filter does not match gives NO DATA', () {
      final sim = _twin();

      sim.execute('ATCRA18DAF1AA');

      expect(_lines(sim, '0100'), ['NO DATA']);
    });

    test('a physical header reaches one ECU only', () {
      final sim = _twin();

      expect(_lines(sim, 'ATSHDA11F1'), ['OK']);
      expect(_lines(sim, '0100'), ['18DAF111064100BC3FA80300']);
      expect(_lines(sim, 'ATSH18DA10F1'), ['OK']);
      expect(_lines(sim, '0100'), ['18DAF110064100983A800100']);
      sim.execute('ATSHDB33F1');
      expect(_lines(sim, '0100'), hasLength(2));
    });

    test('with headers off the long answers are the real car\'s shape', () {
      final sim = _twin(headers: false);

      // Both begin; the continuation that follows is the first ECU's only.
      final lines = _lines(sim, '010C0D1110040B1');
      final lengths = lines.where((l) => RegExp(r'^[0-9A-F]{3}$').hasMatch(l));

      expect(lengths.toList(), ['00C', '00F']);
      expect(lines.where((l) => l.startsWith('0:')), hasLength(2));
      // The first ECU's twelve bytes need one more line; the second's fifteen
      // would need two, and never get them.
      expect(lines.where((l) => l.startsWith('1:')), hasLength(1));
      expect(lines.where((l) => l.startsWith('2:')), isEmpty);
    });

    test('ATRV, ATI and the protocol are still the adapter\'s own', () {
      final sim = _twin();

      expect(_lines(sim, 'ATDPN'), ['A7']);
      expect(_lines(sim, 'ATRV').single, matches(RegExp(r'^\d\d\.\dV$')));
    });
  });

  group('what a survey asks an ECU beyond Mode 01', () {
    SimulatedEcu ecu({bool survey = true}) {
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        profile: VehicleProfiles.surveyTwin,
      );
      while (car.elapsedSeconds < 60) {
        car.tick();
      }
      return SimulatedEcu(car: car, surveyData: survey);
    }

    test('Mode 06 has a mask of monitor IDs and results for each', () {
      final e = ecu();

      final mask = e.respond([0x06, 0x00])!;
      expect(mask.take(2), [0x46, 0x00]);
      // 01 is the first bit of the first byte; the last bit says the next
      // range has some (21).
      expect(mask[2] & 0x80, isNonZero);
      expect(mask.last & 1, 1);
      // The chain goes on to A1, and ends there.
      for (final id in [0x20, 0x40, 0x60, 0x80, 0xA0]) {
        expect(e.respond([0x06, id]), isNotNull, reason: 'mask $id');
      }
      expect(e.respond([0x06, 0xC0]), isNull);

      final result = e.respond([0x06, 0x01])!;
      expect(result.take(2), [0x46, 0x01]);
      // Test results are 8 bytes each.
      expect((result.length - 2) % 8, 0);
      expect(e.respond([0x06, 0x02]), isNull);
    });

    test('Mode 0A is an empty list of permanent codes', () {
      expect(ecu().respond([0x0A]), [0x4A, 0x00]);
    });

    test('Mode 09 offers the calibration ID, its CVN and the ECU name', () {
      final e = ecu();

      expect(e.respond([0x09, 0x00]), [0x49, 0x00, 0x54, 0x40, 0x00, 0x00]);
      final cal = e.respond([0x09, 0x04])!;
      expect(cal.take(3), [0x49, 0x04, 0x01]);
      expect(cal.length, 3 + 16);
      expect(e.respond([0x09, 0x06])!.length, 3 + 4);
      expect(e.respond([0x09, 0x0A])!.length, 3 + 20);
    });

    test('a plain ECU answers none of those: it is the one the app knows', () {
      final e = ecu(survey: false);

      expect(e.respond([0x06, 0x00]), isNull);
      expect(e.respond([0x0A]), isNull);
      expect(e.respond([0x09, 0x04]), isNull);
      expect(e.respond([0x09, 0x00]), [0x49, 0x00, 0x40, 0x00, 0x00, 0x00]);
    });

    test('the PIDs the app does not read answer with the right length', () {
      final e = SimulatedEcu(
        car: SimulatedCar(
          scenario: DriveScenarios.cityStopGo,
          profile: VehicleProfiles.surveyTwin,
        )..tick(),
        pids: {
          for (final p in [
            0x03, 0x06, 0x0E, 0x13, 0x15, 0x1F, 0x21, 0x2E, 0x30, //
            0x31, 0x33, 0x34, 0x41, 0x43, 0x44, 0x45, 0x47, 0x49, //
            0x4A, 0x4C,
          ])
            p,
        },
      );
      const lengths = {
        0x03: 2, 0x06: 1, 0x0E: 1, 0x13: 1, 0x15: 2, 0x1F: 2, 0x21: 2, //
        0x2E: 1, 0x30: 1, 0x31: 2, 0x33: 1, 0x34: 4, 0x41: 4, 0x43: 2, //
        0x44: 2, 0x45: 1, 0x47: 1, 0x49: 1, 0x4A: 1, 0x4C: 1,
      };

      for (final entry in lengths.entries) {
        final reply = e.respond([0x01, entry.key]);
        expect(reply, isNotNull, reason: 'PID ${entry.key.toRadixString(16)}');
        expect(
          reply!.length,
          2 + entry.value,
          reason: 'PID ${entry.key.toRadixString(16)}',
        );
      }
    });
  });
}
