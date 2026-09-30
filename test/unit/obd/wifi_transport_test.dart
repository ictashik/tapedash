// The WiFi transport over real loopback sockets: it connects, sends and receives
// ELM327 text, notices when the far end goes, and never opens a socket to an
// address outside the private ranges.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/obd/transport/wifi_transport.dart';

void main() {
  late ServerSocket server;
  final accepted = <Socket>[];
  final received = <String>[];

  setUp(() async {
    accepted.clear();
    received.clear();
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
    server.listen((socket) {
      accepted.add(socket);
      socket.listen((data) => received.add(latin1.decode(data)));
    });
  });

  tearDown(() async {
    for (final s in accepted) {
      s.destroy();
    }
    await server.close();
  });

  WifiTransport transport() =>
      WifiTransport(host: '127.0.0.1', port: server.port);

  Future<void> until(bool Function() done) async {
    final end = DateTime.now().add(const Duration(seconds: 5));
    while (!done()) {
      if (DateTime.now().isAfter(end)) fail('timed out');
      await Future<void>.delayed(const Duration(milliseconds: 5));
    }
  }

  test('it connects, and says so', () async {
    final t = transport();
    addTearDown(t.dispose);
    final states = <TransportState>[];
    t.state.listen(states.add);
    expect(t.currentState.status, TransportStatus.disconnected);

    await t.connect();
    expect(t.currentState, TransportState.connected);
    expect(states, [TransportState.connecting, TransportState.connected]);
    await until(() => accepted.length == 1);
  });

  test(
    'what is written arrives as it was, and what comes back is text',
    () async {
      final t = transport();
      addTearDown(t.dispose);
      final incoming = StringBuffer();
      t.incoming.listen(incoming.write);
      await t.connect();
      await until(() => accepted.isNotEmpty);

      await t.write('ATZ\r');
      await until(() => received.join().contains('ATZ\r'));
      expect(received.join(), 'ATZ\r');

      accepted.single.add(latin1.encode('\r\rELM327 v1.5\r\r>'));
      await until(() => incoming.toString().endsWith('>'));
      expect(incoming.toString(), '\r\rELM327 v1.5\r\r>');
    },
  );

  test('bytes that are not ASCII survive the trip', () async {
    final t = transport();
    addTearDown(t.dispose);
    final incoming = StringBuffer();
    t.incoming.listen(incoming.write);
    await t.connect();
    await until(() => accepted.isNotEmpty);
    accepted.single.add([0x41, 0xFF, 0x80, 0x0D, 0x3E]);
    await until(() => incoming.length == 5);
    expect(incoming.toString().codeUnits, [0x41, 0xFF, 0x80, 0x0D, 0x3E]);
  });

  test('when the far end closes, the link is lost', () async {
    final t = transport();
    addTearDown(t.dispose);
    await t.connect();
    await until(() => accepted.isNotEmpty);
    final lost = t.state.firstWhere((s) => !s.isConnected);

    accepted.single.destroy();
    expect(
      await lost.timeout(const Duration(seconds: 5)),
      const TransportState.disconnected(failure: TransportFailure.lost),
    );
    await expectLater(
      t.write('ATZ\r'),
      throwsA(
        isA<TransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.notConnected,
        ),
      ),
    );
  });

  test(
    'a disconnect by the app is not a failure, and it can connect again',
    () async {
      final t = transport();
      addTearDown(t.dispose);
      await t.connect();
      await t.disconnect();
      expect(t.currentState, const TransportState.disconnected());
      await t.disconnect(); // safe when it is not up

      await t.connect();
      expect(t.currentState, TransportState.connected);
      await until(() => accepted.length == 2);
    },
  );

  test('writing with no link fails, and says why', () async {
    final t = transport();
    addTearDown(t.dispose);
    await expectLater(
      t.write('ATZ\r'),
      throwsA(
        isA<TransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.notConnected,
        ),
      ),
    );
  });

  test('nobody listening: unreachable, and the state says so', () async {
    final port = server.port;
    await server.close();
    final t = WifiTransport(
      host: '127.0.0.1',
      port: port,
      connectTimeout: const Duration(seconds: 2),
    );
    addTearDown(t.dispose);
    await expectLater(
      t.connect(),
      throwsA(
        isA<TransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.unreachable,
        ),
      ),
    );
    expect(
      t.currentState,
      const TransportState.disconnected(failure: TransportFailure.unreachable),
    );
    // Restart the server so that tearDown has something to close.
    server = await ServerSocket.bind(InternetAddress.loopbackIPv4, 0);
  });

  group('the network guard, at the point of use', () {
    for (final host in const [
      '8.8.8.8',
      '142.250.190.14',
      'example.com',
      'localhost',
      '',
    ]) {
      test("'$host' is refused before any socket is made", () async {
        var opened = 0;
        final t = WifiTransport(
          host: host,
          connector: (h, p, timeout) async {
            opened++;
            throw StateError('a socket was opened to $h');
          },
        );
        addTearDown(t.dispose);
        await expectLater(
          t.connect(),
          throwsA(
            isA<TransportException>().having(
              (e) => e.failure,
              'failure',
              TransportFailure.unreachable,
            ),
          ),
        );
        expect(opened, 0);
        expect(t.currentState.status, TransportStatus.disconnected);
      });
    }

    test('private addresses get as far as the socket', () async {
      final tried = <String>[];
      for (final host in const ['192.168.0.10', '10.0.2.2', '172.16.5.5']) {
        final t = WifiTransport(
          host: host,
          port: 1234,
          connector: (h, p, timeout) async {
            tried.add('$h:$p');
            throw const SocketException('no route in a test');
          },
        );
        await expectLater(t.connect(), throwsA(isA<TransportException>()));
        await t.dispose();
      }
      expect(tried, ['192.168.0.10:1234', '10.0.2.2:1234', '172.16.5.5:1234']);
    });
  });

  test('a disconnect while connecting cancels it', () async {
    final gate = Completer<Socket>();
    final t = WifiTransport(
      host: '127.0.0.1',
      connector: (h, p, timeout) => gate.future,
    );
    addTearDown(t.dispose);
    final connecting = t.connect();
    expect(t.currentState, TransportState.connecting);
    await t.disconnect();
    final socket = await Socket.connect('127.0.0.1', server.port);
    gate.complete(socket);
    await expectLater(
      connecting,
      throwsA(
        isA<TransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.cancelled,
        ),
      ),
    );
    expect(t.currentState, const TransportState.disconnected());
  });
}
