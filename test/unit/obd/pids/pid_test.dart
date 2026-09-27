import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/pids/pid.dart';
import 'package:tapedash/vehicle/sensor.dart';

void main() {
  group('the decoders of CLAUDE.md 8.3', () {
    // Each case is worked out by hand from the formula, and the ones from the
    // ELM327 datasheet's examples say so.
    test('04 engine load is A x 100 / 255', () {
      expect(Pids.load.decode([0]), 0);
      expect(Pids.load.decode([255]), 100);
      expect(Pids.load.decode([128]), closeTo(50.196, 0.001));
      // The datasheet's 41 04 3F.
      expect(Pids.load.decode([0x3F]), closeTo(24.706, 0.001));
    });

    test('05 coolant is A - 40', () {
      expect(Pids.coolant.decode([0]), -40);
      expect(Pids.coolant.decode([40]), 0);
      expect(Pids.coolant.decode([255]), 215);
      // The datasheet's 41 05 7B: 83 degrees. And 41 05 44: 28.
      expect(Pids.coolant.decode([0x7B]), 83);
      expect(Pids.coolant.decode([0x44]), 28);
    });

    test('0B manifold pressure is A', () {
      expect(Pids.manifoldPressure.decode([0]), 0);
      expect(Pids.manifoldPressure.decode([255]), 255);
      // The datasheet's 0B 21.
      expect(Pids.manifoldPressure.decode([0x21]), 33);
    });

    test('0C rpm is (256 A + B) / 4', () {
      expect(Pids.rpm.decode([0, 0]), 0);
      expect(Pids.rpm.decode([0, 1]), 0.25);
      expect(Pids.rpm.decode([0, 3]), 0.75);
      expect(Pids.rpm.decode([1, 0]), 64);
      expect(Pids.rpm.decode([255, 255]), 16383.75);
      // The datasheet's 41 0C 1A F8: 6904 / 4 = 1726 rpm.
      expect(Pids.rpm.decode([0x1A, 0xF8]), 1726);
      // And 0C 17 B8: 6072 / 4 = 1518.
      expect(Pids.rpm.decode([0x17, 0xB8]), 1518);
    });

    test('0D speed is A', () {
      expect(Pids.speed.decode([0]), 0);
      expect(Pids.speed.decode([255]), 255);
      expect(Pids.speed.decode([0x32]), 50);
    });

    test('0F intake air is A - 40', () {
      expect(Pids.intakeAir.decode([0]), -40);
      expect(Pids.intakeAir.decode([65]), 25);
      expect(Pids.intakeAir.decode([255]), 215);
    });

    test('10 MAF is (256 A + B) / 100', () {
      expect(Pids.airFlow.decode([0, 0]), 0);
      expect(Pids.airFlow.decode([0, 100]), 1);
      expect(Pids.airFlow.decode([0x03, 0xE8]), 10);
      expect(Pids.airFlow.decode([255, 255]), 655.35);
    });

    test('11 throttle is A x 100 / 255', () {
      expect(Pids.throttle.decode([0]), 0);
      expect(Pids.throttle.decode([255]), 100);
      expect(Pids.throttle.decode([51]), closeTo(20, 1e-9));
    });

    test('2F fuel level is A x 100 / 255', () {
      expect(Pids.fuelLevel.decode([0]), 0);
      expect(Pids.fuelLevel.decode([255]), 100);
      expect(Pids.fuelLevel.decode([178]), closeTo(69.8, 0.05));
    });

    test('42 module voltage is (256 A + B) / 1000', () {
      expect(Pids.voltage.decode([0, 0]), 0);
      // 12,345 mV is 0x3039.
      expect(Pids.voltage.decode([0x30, 0x39]), 12.345);
      // 14.1 V is 14,100 = 0x3714.
      expect(Pids.voltage.decode([0x37, 0x14]), 14.1);
      expect(Pids.voltage.decode([255, 255]), 65.535);
    });

    test('5E fuel rate is (256 A + B) / 20', () {
      expect(Pids.fuelRate.decode([0, 0]), 0);
      expect(Pids.fuelRate.decode([0, 100]), 5);
      expect(Pids.fuelRate.decode([0, 1]), 0.05);
      expect(Pids.fuelRate.decode([255, 255]), 3276.75);
    });
  });

  group('a value that would not fit', () {
    test('the wrong number of bytes is refused', () {
      expect(() => Pids.rpm.decode([1]), throwsArgumentError);
      expect(() => Pids.rpm.decode([1, 2, 3]), throwsArgumentError);
      expect(() => Pids.speed.decode([]), throwsArgumentError);
      expect(() => Pids.speed.decode([1, 2]), throwsArgumentError);
    });

    test('a byte outside 0 to 255 is refused', () {
      expect(() => Pids.speed.decode([256]), throwsArgumentError);
      expect(() => Pids.speed.decode([-1]), throwsArgumentError);
      expect(() => Pids.rpm.decode([0, 300]), throwsArgumentError);
    });
  });

  group('the table', () {
    test('has the eleven PIDs of CLAUDE.md 8.3, each once', () {
      expect(Pids.all.map((p) => p.id), [
        0x04,
        0x05,
        0x0B,
        0x0C,
        0x0D,
        0x0F,
        0x10,
        0x11,
        0x2F,
        0x42,
        0x5E,
      ]);
    });

    test('each is found by its number', () {
      for (final pid in Pids.all) {
        expect(Pids.byId(pid.id), same(pid));
      }
      expect(Pids.byId(0x99), isNull);
      expect(Pids.byId(0x00), isNull);
    });

    test('each reads its own sensor, and no sensor is read twice', () {
      expect(Pids.all.map((p) => p.sensor).toSet().length, Pids.all.length);
      expect(Pids.all.map((p) => p.sensor).toSet(), Sensor.values.toSet());
      expect(Pids.forSensor(Sensor.rpm), same(Pids.rpm));
      expect(Pids.forSensor(Sensor.fuelRate), same(Pids.fuelRate));
    });

    test('the lengths are those of the standard', () {
      const lengths = {
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
      for (final pid in Pids.all) {
        expect(pid.length, lengths[pid.id], reason: pid.name);
      }
    });
  });

  group('the outlier rules of DESIGN.md 5.2', () {
    test('rpm at 10,000 rpm/s and speed at 150 km/h/s', () {
      expect(Sensor.rpm.maxChangePerSecond, 10000);
      expect(Sensor.speed.maxChangePerSecond, 150);
    });

    test('the other sensors have none', () {
      for (final s in Sensor.values.where(
        (s) => s != Sensor.rpm && s != Sensor.speed,
      )) {
        expect(s.maxChangePerSecond, isNull, reason: s.name);
      }
    });
  });

  group('an answer to a Mode 01 request', () {
    test('one PID', () {
      final answer = Mode01Answer.parse([0x41, 0x0C, 0x1A, 0xF8])!;

      expect(answer.complete, isTrue);
      expect(answer.values.single.pid, same(Pids.rpm));
      expect(answer.values.single.value, 1726);
      expect(answer.values.single.data, [0x1A, 0xF8]);
    });

    test('the datasheet\'s four PIDs: 04 3F, 05 44, 0B 21, 0C 17 B8', () {
      final answer = Mode01Answer.parse([
        0x41, 0x04, 0x3F, 0x05, 0x44, 0x0B, 0x21, 0x0C, 0x17, 0xB8, //
      ])!;

      expect(answer.complete, isTrue);
      expect(answer.values.map((v) => v.pid.id), [0x04, 0x05, 0x0B, 0x0C]);
      expect(answer.values[0].value, closeTo(24.706, 0.001));
      expect(answer.values[1].value, 28);
      expect(answer.values[2].value, 33);
      expect(answer.values[3].value, 1518);
    });

    test(
      'the same PIDs asked for in another order come back in that order',
      () {
        final answer = Mode01Answer.parse([
          0x41, 0x0B, 0x21, 0x04, 0x3F, 0x0C, 0x17, 0xB8, 0x05, 0x44, //
        ])!;

        expect(answer.values.map((v) => v.pid.id), [0x0B, 0x04, 0x0C, 0x05]);
      },
    );

    test('valueOf finds a PID', () {
      final answer = Mode01Answer.parse([0x41, 0x0D, 0x32, 0x0C, 0x1A, 0xF8])!;

      expect(answer.valueOf(Pids.speed)!.value, 50);
      expect(answer.valueOf(Pids.rpm)!.value, 1726);
      expect(answer.valueOf(Pids.load), isNull);
    });

    test('a PID it does not know ends the reading, and is not complete', () {
      // 0x99 is not one of ours: the rest cannot be split into PIDs.
      final answer = Mode01Answer.parse([
        0x41,
        0x0D,
        0x32,
        0x99,
        0x01,
        0x0C,
        0x1A,
        0xF8,
      ])!;

      expect(answer.complete, isFalse);
      expect(answer.values.map((v) => v.pid.id), [0x0D]);
    });

    test('data cut short ends the reading, and is not complete', () {
      final answer = Mode01Answer.parse([0x41, 0x0D, 0x32, 0x0C, 0x1A])!;

      expect(answer.complete, isFalse);
      expect(answer.values.map((v) => v.pid.id), [0x0D]);
    });

    test('a message that is not a Mode 01 answer is null', () {
      expect(Mode01Answer.parse([0x43, 0x00]), isNull);
      expect(Mode01Answer.parse([0x41]), isNull);
      expect(Mode01Answer.parse([]), isNull);
      expect(Mode01Answer.parse([0x7F, 0x01, 0x12]), isNull);
    });
  });

  group('PID 01', () {
    test('no codes and no light', () {
      final status = MonitorStatus.decode([0x00, 0x07, 0x65, 0x00]);

      expect(status.milOn, isFalse);
      expect(status.codeCount, 0);
      expect(status.compressionIgnition, isFalse);
    });

    test('the light bit and a count', () {
      final status = MonitorStatus.decode([0x82, 0x07, 0x65, 0x00]);

      expect(status.milOn, isTrue);
      expect(status.codeCount, 2);
    });

    test('the count is seven bits', () {
      expect(MonitorStatus.decode([0xFF, 0, 0, 0]).codeCount, 127);
      expect(MonitorStatus.decode([0x7F, 0, 0, 0]).milOn, isFalse);
    });

    test('bit 3 of the second byte is compression ignition', () {
      expect(MonitorStatus.decode([0, 0x08, 0, 0]).compressionIgnition, isTrue);
      expect(MonitorStatus.decode([0, 0x0F, 0, 0]).compressionIgnition, isTrue);
      expect(
        MonitorStatus.decode([0, 0x07, 0, 0]).compressionIgnition,
        isFalse,
      );
    });

    test('the wrong number of bytes is refused', () {
      expect(() => MonitorStatus.decode([0, 0]), throwsArgumentError);
    });
  });
}
