import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/address_entry.dart';

AddressEntry typed(String keys, {bool port = false}) {
  final e = AddressEntry()..editingPort = port;
  for (final k in keys.split(' ')) {
    e.press(k);
  }
  return e;
}

void main() {
  test('an address is typed digit by digit, with dots', () {
    final e = typed('1 9 2 . 1 6 8 . 0 . 1 0');
    expect(e.host, '192.168.0.10');
    expect(e.hostComplete, isTrue);
  });

  test('a group has at most three digits and never goes over 255', () {
    expect(typed('2 5 6').host, '25', reason: '256 is not an octet');
    expect(typed('2 5 5').host, '255');
    expect(typed('1 9 2 1').host, '192', reason: 'a fourth digit');
    expect(typed('3 0 0').host, '30');
  });

  test('no leading zeros: a zero is a group on its own', () {
    expect(typed('0 5').host, '0');
    expect(typed('1 . 0 5').host, '1.0');
  });

  test('dots: never first, never twice, never a fourth', () {
    expect(typed('.').host, '');
    expect(typed('1 . .').host, '1.');
    expect(typed('1 . 2 . 3 . 4 .').host, '1.2.3.4');
  });

  test('back removes the last key, and is safe when empty', () {
    final e = typed('1 9 . 1');
    e.press('back');
    expect(e.host, '19.');
    e.press('back');
    e.press('back');
    e.press('back');
    e.press('back');
    expect(e.host, '');
  });

  test('an address is complete only with four whole groups', () {
    expect(typed('1 9 2 . 1 6 8 . 0').hostComplete, isFalse);
    expect(typed('1 9 2 . 1 6 8 . 0 .').hostComplete, isFalse);
    expect(typed('1 9 2 . 1 6 8 . 0 . 1').hostComplete, isTrue);
    expect(AddressEntry().hostComplete, isFalse);
  });

  test('a port is up to five digits and never over 65535', () {
    expect(typed('3 5 0 0 0', port: true).port, '35000');
    expect(typed('3 5 0 0 0 1', port: true).port, '35000');
    expect(typed('6 5 5 3 6', port: true).port, '6553');
    expect(typed('6 5 5 3 5', port: true).port, '65535');
    expect(typed('9 9 9 9 9', port: true).port, '9999');
  });

  test('a port never starts with zero, and takes no dots', () {
    expect(typed('0 8 0', port: true).port, '80');
    expect(typed('3 . 5', port: true).port, '35');
    expect(typed('3 5', port: true).portNumber, 35);
    expect(AddressEntry().portNumber, isNull);
  });

  test('complete needs both', () {
    final e = typed('1 9 2 . 1 6 8 . 0 . 1 0');
    expect(e.complete, isFalse);
    e
      ..editingPort = true
      ..press('3')
      ..press('5')
      ..press('0')
      ..press('0')
      ..press('0');
    expect(e.complete, isTrue);
  });

  test('nonsense keys are ignored', () {
    expect(typed('x abc ,').host, '');
  });
}
