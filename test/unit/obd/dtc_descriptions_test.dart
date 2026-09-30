import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/dtc/dtc.dart';
import 'package:tapedash/obd/dtc/dtc_descriptions.dart';

void main() {
  final file = File('assets/dtc/dtc.json').readAsStringSync();
  final descriptions = DtcDescriptions.parse(file);

  test('the bundled file is a sorted object of codes to one line each', () {
    final map = jsonDecode(file) as Map<String, dynamic>;
    expect(map.length, greaterThan(200));
    expect(map.keys.toList(), [...map.keys]..sort());
    for (final e in map.entries) {
      expect(
        RegExp(r'^[PCBU][0-3][0-9A-F]{3}$').hasMatch(e.key),
        isTrue,
        reason: '${e.key} is not a code',
      );
      final text = e.value as String;
      expect(text.trim(), text, reason: e.key);
      expect(text, isNotEmpty, reason: e.key);
      expect(text.contains('\n'), isFalse, reason: e.key);
      expect(
        text.length,
        lessThan(90),
        reason: '${e.key} is not one short line',
      );
    }
  });

  test('the codes the simulator injects are described', () {
    expect(descriptions.describe(const Dtc('P0420')), contains('Catalytic'));
    expect(descriptions.describe(const Dtc('P0171')), contains('lean'));
    expect(descriptions.knows(const Dtc('P0420')), isTrue);
  });

  test('the generated families are right', () {
    expect(
      descriptions.describe(const Dtc('P0136')),
      'Oxygen sensor, bank 1, sensor 2 (after the catalyst): circuit fault',
    );
    expect(
      descriptions.describe(const Dtc('P0141')),
      contains('heater circuit fault'),
    );
    expect(descriptions.describe(const Dtc('P0157')), contains('bank 2'));
    expect(descriptions.describe(const Dtc('P0304')), 'Misfire in cylinder 4');
    expect(descriptions.describe(const Dtc('P0208')), contains('cylinder 8'));
    expect(descriptions.describe(const Dtc('P0352')), contains('coil B'));
  });

  test('a code not in the file is described by its system, never guessed', () {
    final standard = descriptions.describe(const Dtc('P0999'));
    expect(descriptions.knows(const Dtc('P0999')), isFalse);
    expect(standard, contains('engine or transmission'));
    expect(standard, contains('workshop manual'));

    final maker = descriptions.describe(const Dtc('P1234'));
    expect(maker, contains('car maker defines'));

    expect(descriptions.describe(const Dtc('C0777')), contains('brakes'));
    expect(descriptions.describe(const Dtc('B1000')), contains('maker'));
    expect(
      descriptions.describe(const Dtc('U0999')),
      contains('communication between the car'),
    );
    // P2xxx is the standard's; C2xxx is not.
    expect(descriptions.describe(const Dtc('P2000')), contains('manual'));
    expect(descriptions.describe(const Dtc('P2000')), isNot(contains('maker')));
    expect(descriptions.describe(const Dtc('C2000')), contains('maker'));
  });

  test('with no file, every code has its system', () {
    expect(
      DtcDescriptions.empty.describe(const Dtc('P0420')),
      contains('engine or transmission'),
    );
  });
}
