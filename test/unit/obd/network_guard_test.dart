import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/wifi_transport.dart';

void main() {
  group('allowed: private, loopback and link-local addresses', () {
    for (final host in const [
      '10.0.0.1',
      '10.255.255.255',
      '10.0.2.2', // the Android emulator's host
      '172.16.0.1',
      '172.20.10.1',
      '172.31.255.255',
      '192.168.0.10', // where a WiFi ELM327 usually is
      '192.168.4.1',
      '192.168.255.255',
      '127.0.0.1',
      '127.1.2.3',
      '169.254.1.1',
      '::1',
      'fe80::1',
      'febf::1234',
      '::ffff:192.168.0.10',
      '  192.168.0.10  ',
    ]) {
      test(host, () => expect(NetworkGuard.allows(host), isTrue));
    }
  });

  group('refused: anything on the internet', () {
    for (final host in const [
      '8.8.8.8',
      '1.1.1.1',
      '142.250.190.14',
      '11.0.0.1',
      '9.255.255.255',
      '172.15.255.255', // just below 172.16.0.0/12
      '172.32.0.1', // just above it
      '192.167.255.255',
      '192.169.0.1',
      '169.253.1.1',
      '169.255.0.1',
      '0.0.0.0',
      '255.255.255.255',
      '128.0.0.1',
      '2001:4860:4860::8888',
      'fec0::1', // site-local, deprecated: not link-local
      'fc00::1', // unique local: not in the allowed list
      '::ffff:8.8.8.8',
      '::',
    ]) {
      test(host, () => expect(NetworkGuard.allows(host), isFalse));
    }
  });

  group('refused: anything that is not a literal address', () {
    for (final host in const [
      '',
      ' ',
      'localhost', // a name is a look-up, whatever it resolves to
      'example.com',
      'obd.local',
      '192.168.0.10.example.com',
      'http://192.168.0.10',
      '192.168.0.10:35000',
      '192.168.0',
      '192.168.0.256',
      '10.0.0.1/8',
      '-1.0.0.1',
    ]) {
      test("'$host'", () => expect(NetworkGuard.allows(host), isFalse));
    }
  });
}
