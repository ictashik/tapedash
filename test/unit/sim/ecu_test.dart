import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/sim/drive_scenario.dart';
import 'package:tapedash/sim/driver.dart';
import 'package:tapedash/sim/ecu.dart';
import 'package:tapedash/sim/profiles.dart';
import 'package:tapedash/sim/scenario_events.dart';
import 'package:tapedash/sim/scenarios.dart';
import 'package:tapedash/sim/sim_route.dart';
import 'package:tapedash/sim/simulated_car.dart';

/// A car that has run for [seconds] of a scenario.
SimulatedCar _carAt(
  double seconds, {
  String scenario = 'city_stop_go',
  int seed = 1,
}) {
  final car = SimulatedCar(
    scenario: DriveScenarios.byName(scenario)!,
    seed: seed,
  );
  while (car.elapsedSeconds < seconds) {
    car.tick();
  }
  return car;
}

/// The data bytes of a Mode 01 reply to a single PID, which is `41 pid data`.
List<int> _data(List<int>? reply, int pid) {
  expect(reply, isNotNull, reason: 'no reply for PID ${pid.toRadixString(16)}');
  expect(reply!.first, 0x41);
  expect(reply[1], pid);
  return reply.sublist(2);
}

// The decoders of CLAUDE.md 8.3, written out again here so that the ECU is
// checked against the spec and not against its own inverse.
double _pct(List<int> d) => d[0] * 100 / 255;
double _word(List<int> d) => (256 * d[0] + d[1]).toDouble();

void main() {
  group('DtcCodec', () {
    test('P0420 is 04 20 and P0171 is 01 71', () {
      expect(DtcCodec.encode('P0420'), [0x04, 0x20]);
      expect(DtcCodec.encode('P0171'), [0x01, 0x71]);
    });

    test('the letter is the top two bits: P, C, B, U', () {
      expect(DtcCodec.encode('C0300'), [0x43, 0x00]);
      expect(DtcCodec.encode('B1000'), [0x90, 0x00]);
      expect(DtcCodec.encode('U0100'), [0xC1, 0x00]);
    });

    test('the first digit is the next two bits, 0 to 3', () {
      expect(DtcCodec.encode('P1234'), [0x12, 0x34]);
      expect(DtcCodec.encode('P2000'), [0x20, 0x00]);
      expect(DtcCodec.encode('P3FFF'), [0x3F, 0xFF]);
    });

    test('decoding gives the code back', () {
      for (final code in [
        'P0420',
        'P0171',
        'C0300',
        'B1000',
        'U0100',
        'P3FFF',
        'P0000',
      ]) {
        final bytes = DtcCodec.encode(code)!;
        expect(DtcCodec.decode(bytes[0], bytes[1]), code);
      }
    });

    test('00 00 is P0000, which is what an unused slot reads as', () {
      expect(DtcCodec.decode(0, 0), 'P0000');
    });

    test('lower case is accepted', () {
      expect(DtcCodec.encode('p0420'), [0x04, 0x20]);
    });

    test('anything that is not a code is refused', () {
      for (final bad in ['', 'P042', 'P04200', 'X0420', 'P4000', 'P04G0']) {
        expect(DtcCodec.encode(bad), isNull, reason: bad);
      }
    });
  });

  group('SupportMask', () {
    test('the first PID of a range is the top bit', () {
      expect(SupportMask.encode({0x01}, 0x00), [0x80, 0x00, 0x00, 0x00]);
    });

    test('the 32nd PID of a range is the last bit', () {
      expect(SupportMask.encode({0x20}, 0x00), [0x00, 0x00, 0x00, 0x01]);
    });

    test(
      'PIDs in other ranges are not in it, except as the next-range bit',
      () {
        expect(SupportMask.encode({0x2F}, 0x00), [0x00, 0x00, 0x00, 0x01]);
        expect(SupportMask.encode({0x2F}, 0x20), [0x00, 0x02, 0x00, 0x00]);
      },
    );

    test('a range with nothing after it does not set the next-range bit', () {
      expect(SupportMask.encode({0x42}, 0x40), [0x40, 0x00, 0x00, 0x00]);
    });

    test('an empty set is all zeros', () {
      expect(SupportMask.encode(const {}, 0x00), [0, 0, 0, 0]);
    });
  });

  group('the support bitmasks of each profile', () {
    // Worked out by hand from the PID lists of CLAUDE.md 7.2. In 0100, PID 01
    // is 80 00 00 00, 04 is 10 00 00 00, 05 is 08 00 00 00, 0B is 00 20 00 00,
    // 0C is 00 10 00 00, 0D is 00 08 00 00, 0F is 00 02 00 00, 10 is
    // 00 01 00 00 and 11 is 00 00 80 00.
    SimulatedEcu ecuFor(String profileName) => SimulatedEcu(
      car: SimulatedCar(
        scenario: DriveScenarios.coldStartIdle,
        profile: VehicleProfiles.byName(profileName),
      )..tick(),
    );

    test('petrol_cvt_maf', () {
      final ecu = ecuFor('petrol_cvt_maf');

      expect(_data(ecu.respond([0x01, 0x00]), 0x00), [0x98, 0x3B, 0x80, 0x01]);
      expect(_data(ecu.respond([0x01, 0x20]), 0x20), [0x00, 0x02, 0x00, 0x01]);
      expect(_data(ecu.respond([0x01, 0x40]), 0x40), [0x40, 0x00, 0x00, 0x00]);
    });

    test('petrol_cvt_map has no 10, so no 00 01 00 00', () {
      final ecu = ecuFor('petrol_cvt_map');

      expect(_data(ecu.respond([0x01, 0x00]), 0x00), [0x98, 0x3A, 0x80, 0x01]);
    });

    test('petrol_cvt_fuelrate adds 5E, the 30th bit of 0140', () {
      final ecu = ecuFor('petrol_cvt_fuelrate');

      expect(_data(ecu.respond([0x01, 0x40]), 0x40), [0x40, 0x00, 0x00, 0x04]);
    });

    test('minimal_old_car: 04, 05, 0C, 0D, 11 and nothing after', () {
      final ecu = ecuFor('minimal_old_car');

      expect(_data(ecu.respond([0x01, 0x00]), 0x00), [0x98, 0x18, 0x80, 0x00]);
      expect(ecu.respond([0x01, 0x20]), isNull);
      expect(ecu.respond([0x01, 0x40]), isNull);
    });
  });

  group('the readings, against the car', () {
    test('every supported PID decodes to what the car is doing', () {
      final car = _carAt(0);
      final ecu = SimulatedEcu(car: car);
      var readings = 0;

      while (car.elapsedSeconds < 150) {
        for (var i = 0; i < 20; i++) {
          car.tick();
        }
        final s = car.state;
        final rpm = _word(_data(ecu.respond([0x01, 0x0C]), 0x0C)) / 4;
        final maf = _word(_data(ecu.respond([0x01, 0x10]), 0x10)) / 100;

        expect(
          _pct(_data(ecu.respond([0x01, 0x04]), 0x04)),
          closeTo(s.loadFraction * 100, 2.5),
        );
        expect(
          _data(ecu.respond([0x01, 0x05]), 0x05)[0] - 40,
          closeTo(s.coolantC, 0.51),
        );
        expect(
          _data(ecu.respond([0x01, 0x0B]), 0x0B)[0],
          closeTo(s.manifoldKpa, 1.6),
        );
        expect(rpm, closeTo(s.rpm, 17));
        expect(
          _data(ecu.respond([0x01, 0x0D]), 0x0D)[0],
          closeTo(s.speedKmh, 0.51),
        );
        expect(
          _data(ecu.respond([0x01, 0x0F]), 0x0F)[0] - 40,
          closeTo(s.intakeAirC, 0.51),
        );
        expect(
          maf,
          closeTo(s.airGramsPerSecond, s.airGramsPerSecond * 0.02 + 0.01),
        );
        expect(
          _pct(_data(ecu.respond([0x01, 0x11]), 0x11)),
          closeTo(s.throttleFraction * 100, 1.2),
        );
        expect(
          _pct(_data(ecu.respond([0x01, 0x2F]), 0x2F)),
          closeTo(s.fuelLevelFraction * 100, 0.25),
        );
        expect(
          _word(_data(ecu.respond([0x01, 0x42]), 0x42)) / 1000,
          closeTo(s.voltage, 0.12),
        );
        readings++;
      }

      expect(readings, greaterThan(100));
    });

    test('PID 5E is the fuel rate in litres per hour, in 1/20ths', () {
      final car = SimulatedCar(
        scenario: DriveScenarios.cityStopGo,
        profile: VehicleProfiles.petrolCvtFuelRate,
      );
      final ecu = SimulatedEcu(car: car);
      while (car.elapsedSeconds < 90) {
        car.tick();
      }

      final litresPerHour = _word(_data(ecu.respond([0x01, 0x5E]), 0x5E)) / 20;

      expect(
        litresPerHour,
        closeTo(
          car.state.fuelRateLitresPerHour,
          car.state.fuelRateLitresPerHour * 0.02 + 0.06,
        ),
      );
    });

    test(
      'a stopped engine reads zero rpm, zero MAF, and a resting voltage',
      () {
        // Ignition on, engine not yet running: the first tick of a cold start.
        final car = SimulatedCar(scenario: DriveScenarios.coldStartIdle)
          ..tick();
        final ecu = SimulatedEcu(car: car);
        expect(car.state.engineRunning, isFalse);

        expect(_word(_data(ecu.respond([0x01, 0x0C]), 0x0C)), 0);
        expect(_word(_data(ecu.respond([0x01, 0x10]), 0x10)), 0);
        expect(_data(ecu.respond([0x01, 0x0D]), 0x0D), [0]);
        final volts = _word(_data(ecu.respond([0x01, 0x42]), 0x42)) / 1000;
        expect(volts, closeTo(12.4, 0.2));
      },
    );

    test('the noise averages out: it does not bias a reading', () {
      final car = _carAt(60);
      final ecu = SimulatedEcu(car: car);
      final truth = car.state.rpm;
      var sum = 0.0;
      const reads = 600;

      for (var i = 0; i < reads; i++) {
        sum += _word(_data(ecu.respond([0x01, 0x0C]), 0x0C)) / 4;
      }

      expect(sum / reads, closeTo(truth, 0.7));
    });

    test('a reading is never outside the bytes it has to fit in', () {
      final car = _carAt(0);
      final ecu = SimulatedEcu(car: car);

      while (car.elapsedSeconds < 200) {
        car.tick();
        for (final pid in car.profile.supportedPids) {
          final reply = ecu.respond([0x01, pid])!;
          expect(reply.skip(2), everyElement(inInclusiveRange(0, 255)));
        }
      }
    });
  });

  group('requests', () {
    test('several PIDs at once come back in one reply, in the order asked', () {
      final ecu = SimulatedEcu(car: _carAt(60));

      final reply = ecu.respond([0x01, 0x0D, 0x0C, 0x05])!;

      // 41, then 0D and one byte, 0C and two, 05 and one.
      expect(reply.length, 1 + 2 + 3 + 2);
      expect(reply[0], 0x41);
      expect(reply[1], 0x0D);
      expect(reply[3], 0x0C);
      expect(reply[6], 0x05);
    });

    test('six PIDs are allowed and seven are not', () {
      final ecu = SimulatedEcu(car: _carAt(60));
      const six = [0x04, 0x05, 0x0B, 0x0C, 0x0D, 0x0F];

      expect(ecu.respond([0x01, ...six]), isNotNull);
      expect(ecu.respond([0x01, ...six, 0x11]), isNull);
    });

    test('an unsupported PID in a request is left out of the reply', () {
      final ecu = SimulatedEcu(car: _carAt(60));

      // The default profile has no 5E.
      final reply = ecu.respond([0x01, 0x5E, 0x0D])!;

      expect(reply, [0x41, 0x0D, reply[2]]);
    });

    test('a request for nothing that is supported gets no answer at all', () {
      final ecu = SimulatedEcu(car: _carAt(60));

      expect(ecu.respond([0x01, 0x5E]), isNull);
      expect(ecu.respond([0x01, 0x5E, 0x66]), isNull);
    });

    test('modes that are not simulated get no answer', () {
      final ecu = SimulatedEcu(car: _carAt(60));

      expect(ecu.respond([0x02, 0x00]), isNull);
      expect(ecu.respond([0x0A]), isNull);
      expect(ecu.respond([]), isNull);
      expect(ecu.respond([0x01]), isNull);
    });
  });

  group('the ignition', () {
    test('the ECU is silent until the ignition is on', () {
      final car = SimulatedCar(scenario: DriveScenarios.coldStartIdle);
      final ecu = SimulatedEcu(car: car);

      expect(ecu.isAwake, isFalse);
      expect(ecu.respond([0x01, 0x00]), isNull);
      expect(ecu.respond([0x03]), isNull);

      car.tick();

      expect(ecu.isAwake, isTrue);
      expect(ecu.respond([0x01, 0x00]), isNotNull);
    });

    test('the battery is there with the ignition off', () {
      final ecu = SimulatedEcu(
        car: SimulatedCar(scenario: DriveScenarios.coldStartIdle),
      );

      expect(ecu.isAwake, isFalse);
      expect(ecu.batteryVolts, inInclusiveRange(11.8, 13));
    });

    test('the ECU goes quiet when the ignition goes off mid-drive', () {
      final car = SimulatedCar(
        scenario: DriveScenarios.mixedCommute(
          ignitionOff: const Duration(minutes: 2),
        ),
      );
      final ecu = SimulatedEcu(car: car);
      var sawSilence = false;
      var wasSilent = false;
      var answeredAgain = false;

      while (!car.isFinished && car.elapsedSeconds < 3000) {
        car.tick();
        final answered = ecu.respond([0x01, 0x0D]) != null;
        if (!answered && car.elapsedSeconds > 5) {
          sawSilence = true;
          wasSilent = true;
        } else if (answered && wasSilent) {
          answeredAgain = true;
        }
      }

      expect(sawSilence, isTrue);
      expect(answeredAgain, isTrue);
    });
  });

  group('PID 01: the check-engine light and the code count', () {
    test('with no codes: no light and a count of 0', () {
      final ecu = SimulatedEcu(car: _carAt(30));

      final data = _data(ecu.respond([0x01, 0x01]), 0x01);

      expect(data[0], 0x00);
    });

    test('with two stored codes: the light bit and a count of 2', () {
      final ecu = SimulatedEcu(car: _carAt(5, scenario: 'dtc_present'));

      final data = _data(ecu.respond([0x01, 0x01]), 0x01);

      expect(data[0], 0x82);
    });

    test('a pending code lights nothing and is not counted', () {
      final car = SimulatedCar(
        scenario: DriveScenario(
          name: 'pending',
          description: 'a pending code',
          route: SimRoute.straight(100),
          dtcs: const [
            DtcInjection(
              at: Duration.zero,
              code: 'P0300',
              kind: DtcKind.pending,
            ),
          ],
          driverBuilder: () => ScriptedDriver([IdleFor(1000)]),
        ),
      )..tick();
      final ecu = SimulatedEcu(car: car);

      expect(_data(ecu.respond([0x01, 0x01]), 0x01)[0], 0x00);
      expect(ecu.respond([0x03]), [0x43, 0x00]);
      expect(ecu.respond([0x07]), [0x47, 0x01, 0x03, 0x00]);
    });

    test(
      'compression ignition is bit 3 of the second byte, for the diesel',
      () {
        SimulatedEcu ecuFor(String profileName) => SimulatedEcu(
          car: SimulatedCar(
            scenario: DriveScenarios.coldStartIdle,
            profile: VehicleProfiles.byName(profileName),
          )..tick(),
        );

        expect(
          _data(ecuFor('petrol_cvt_maf').respond([0x01, 0x01]), 0x01)[1] & 0x08,
          0,
        );
        expect(
          _data(ecuFor('diesel_manual').respond([0x01, 0x01]), 0x01)[1] & 0x08,
          0x08,
        );
      },
    );
  });

  group('fault codes', () {
    test('mode 03 lists the stored codes, after a count byte', () {
      final ecu = SimulatedEcu(car: _carAt(5, scenario: 'dtc_present'));

      // 43, two codes, P0420 and P0171.
      expect(ecu.respond([0x03]), [0x43, 0x02, 0x04, 0x20, 0x01, 0x71]);
    });

    test('mode 03 with none stored is the mode byte and a count of 0', () {
      final ecu = SimulatedEcu(car: _carAt(30));

      expect(ecu.respond([0x03]), [0x43, 0x00]);
    });

    test('mode 07 lists pending codes and is empty when there are none', () {
      final ecu = SimulatedEcu(car: _carAt(5, scenario: 'dtc_present'));

      expect(ecu.respond([0x07]), [0x47, 0x00]);
    });

    test('mode 04 clears them, and says 44', () {
      final car = _carAt(5, scenario: 'dtc_present');
      final ecu = SimulatedEcu(car: car);
      // Not while moving, so wait for the car to be at rest: the drive begins
      // stationary, so 5 s in it has not moved yet.
      expect(car.state.speedMs, lessThan(0.3));

      expect(ecu.respond([0x04]), [0x44]);
      expect(car.storedDtcs, isEmpty);
      expect(car.milOn, isFalse);
      expect(ecu.respond([0x03]), [0x43, 0x00]);
      expect(_data(ecu.respond([0x01, 0x01]), 0x01)[0], 0);
    });

    test('mode 04 is refused while the car is moving: 7F 04 22', () {
      final car = _carAt(0, scenario: 'dtc_present');
      final ecu = SimulatedEcu(car: car);
      while (car.state.speedMs < 3) {
        car.tick();
      }

      expect(ecu.respond([0x04]), [0x7F, 0x04, 0x22]);
      expect(car.storedDtcs, ['P0420', 'P0171']);
      expect(car.milOn, isTrue);
    });
  });

  group('mode 09', () {
    test('PID 00 says that PID 02, the VIN, is supported', () {
      final ecu = SimulatedEcu(car: _carAt(5));

      expect(ecu.respond([0x09, 0x00]), [0x49, 0x00, 0x40, 0x00, 0x00, 0x00]);
    });

    test('PID 02 is 49 02 01 and the 17 characters', () {
      final ecu = SimulatedEcu(car: _carAt(5), vin: '1D4GP00R55B123456');

      final reply = ecu.respond([0x09, 0x02])!;

      expect(reply.take(3), [0x49, 0x02, 0x01]);
      expect(String.fromCharCodes(reply.skip(3)), '1D4GP00R55B123456');
      expect(reply.length, 20);
    });

    test('other PIDs get no answer', () {
      final ecu = SimulatedEcu(car: _carAt(5));

      expect(ecu.respond([0x09, 0x04]), isNull);
    });
  });

  group('determinism', () {
    List<List<int>?> pollLog(int noiseSeed) {
      final car = _carAt(0);
      final ecu = SimulatedEcu(car: car, noiseSeed: noiseSeed);
      final log = <List<int>?>[];
      while (car.elapsedSeconds < 30) {
        car.tick();
        log
          ..add(ecu.respond([0x01, 0x0C]))
          ..add(ecu.respond([0x01, 0x10]))
          ..add(ecu.respond([0x01, 0x0B]));
      }
      return log;
    }

    test('the same seed gives the same bytes', () {
      expect(pollLog(7), pollLog(7));
    });

    test('a different noise seed gives different noise', () {
      expect(pollLog(7), isNot(pollLog(8)));
    });

    test('polling the ECU never changes how the car drives', () {
      final polled = _carAt(0);
      final ecu = SimulatedEcu(car: polled);
      final quiet = _carAt(0);

      for (var i = 0; i < 4000; i++) {
        polled.tick();
        quiet.tick();
        ecu.respond([0x01, 0x0C, 0x0D, 0x10]);
      }

      expect(polled.truth.fuelLitres, quiet.truth.fuelLitres);
      expect(polled.truth.distanceKm, quiet.truth.distanceKm);
      expect(polled.state.rpm, quiet.state.rpm);
    });
  });
}
