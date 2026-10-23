// The transport over a native link (Bluetooth Classic, BLE), against a fake link.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/native_link.dart';
import 'package:tapedash/obd/transport/native_link_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';

class FakeLink implements NativeLink {
  final StreamController<String> in_ = StreamController.broadcast(sync: true);
  final StreamController<void> lost_ = StreamController.broadcast(sync: true);
  final StreamController<String> diag_ = StreamController.broadcast(sync: true);
  final List<String> sent = [];
  Completer<void>? gate;
  NativeLinkException? openError;
  Object? sendError;
  int opens = 0;
  int closes = 0;

  @override
  Stream<String> get incoming => in_.stream;
  @override
  Stream<void> get lost => lost_.stream;
  @override
  Stream<String> get diagnostics => diag_.stream;

  @override
  Future<void> open() async {
    opens++;
    if (gate != null) await gate!.future;
    if (openError != null) throw openError!;
  }

  @override
  Future<void> close() async => closes++;

  Future<void> dispose() async {
    await in_.close();
    await lost_.close();
    await diag_.close();
  }

  @override
  Future<void> send(String text) async {
    if (sendError != null) throw sendError!;
    sent.add(text);
  }
}

void main() {
  late FakeLink link;
  late NativeLinkTransport transport;

  setUp(() {
    link = FakeLink();
    transport = NativeLinkTransport(link);
  });

  tearDown(() async {
    await transport.dispose();
    await link.dispose();
  });

  test('it connects, and reports connecting then connected', () async {
    final states = <TransportState>[];
    transport.state.listen(states.add);
    await transport.connect();
    expect(states, [TransportState.connecting, TransportState.connected]);
    expect(link.opens, 1);
  });

  test(
    'what is written reaches the link, and what arrives is passed on',
    () async {
      final text = StringBuffer();
      transport.incoming.listen(text.write);
      await transport.connect();
      await transport.write('ATZ\r');
      expect(link.sent, ['ATZ\r']);
      link.in_.add('ELM327 v1.5\r\r>');
      expect(text.toString(), 'ELM327 v1.5\r\r>');
    },
  );

  test('a link that cannot open is unreachable, and says why', () async {
    link.openError = const NativeLinkException(
      NativeLinkProblem.permissionDenied,
      'no permission',
    );
    await expectLater(
      transport.connect(),
      throwsA(
        isA<TransportException>()
            .having((e) => e.failure, 'failure', TransportFailure.unreachable)
            .having((e) => e.message, 'message', 'no permission'),
      ),
    );
    expect(transport.lastProblem, NativeLinkProblem.permissionDenied);
    expect(
      transport.currentState,
      const TransportState.disconnected(failure: TransportFailure.unreachable),
    );

    // And it can try again.
    link.openError = null;
    await transport.connect();
    expect(transport.currentState, TransportState.connected);
    expect(transport.lastProblem, isNull);
  });

  test('an unexpected error opening is unreachable too', () async {
    link.gate = Completer<void>()..completeError(StateError('boom'));
    await expectLater(transport.connect(), throwsA(isA<TransportException>()));
    expect(transport.lastProblem, NativeLinkProblem.other);
  });

  test(
    'the link dropping underneath is a lost link, and writes then fail',
    () async {
      await transport.connect();
      final lost = transport.state.firstWhere((s) => !s.isConnected);
      link.lost_.add(null);
      expect(
        await lost,
        const TransportState.disconnected(failure: TransportFailure.lost),
      );
      await expectLater(
        transport.write('ATZ\r'),
        throwsA(
          isA<TransportException>().having(
            (e) => e.failure,
            'failure',
            TransportFailure.notConnected,
          ),
        ),
      );
    },
  );

  test('a write that fails means the link is lost', () async {
    await transport.connect();
    link.sendError = const NativeLinkException(NativeLinkProblem.notConnected);
    await expectLater(
      transport.write('ATZ\r'),
      throwsA(
        isA<TransportException>().having(
          (e) => e.failure,
          'failure',
          TransportFailure.lost,
        ),
      ),
    );
    expect(transport.currentState.failure, TransportFailure.lost);
  });

  test(
    'a disconnect by the app is not a failure and closes the link',
    () async {
      await transport.connect();
      await transport.disconnect();
      expect(transport.currentState, const TransportState.disconnected());
      expect(link.closes, 1);
      // A link that then reports lost is not news.
      link.lost_.add(null);
      expect(transport.currentState, const TransportState.disconnected());
    },
  );

  test(
    'a disconnect while connecting cancels it and closes what was made',
    () async {
      link.gate = Completer<void>();
      final connecting = transport.connect();
      expect(transport.currentState, TransportState.connecting);
      await transport.disconnect();
      link.gate!.complete();
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
      expect(transport.currentState, const TransportState.disconnected());
      expect(link.closes, greaterThanOrEqualTo(2), reason: 'and the one made');
    },
  );

  test('connect while already connected does nothing', () async {
    await transport.connect();
    await transport.connect();
    expect(link.opens, 1);
  });

  test(
    'a radio that never answers is a failed connection, not a wait for ever',
    () async {
      await transport.dispose();
      link.gate = Completer<void>();
      transport = NativeLinkTransport(
        link,
        openTimeout: const Duration(milliseconds: 50),
      );
      final closesBefore = link.closes;
      final lines = <String>[];
      transport.diagnostics.listen(lines.add);
      await expectLater(
        transport.connect(),
        throwsA(
          isA<TransportException>().having(
            (e) => e.failure,
            'failure',
            TransportFailure.unreachable,
          ),
        ),
      );
      expect(transport.currentState.failure, TransportFailure.unreachable);
      expect(
        link.closes,
        closesBefore + 1,
        reason: 'what was half-opened is let go of',
      );
      expect(lines.single, contains('did not answer'));
    },
  );

  group('diagnostics', () {
    test('the link\'s lines pass through', () async {
      final lines = <String>[];
      transport.diagnostics.listen(lines.add);
      link.diag_.add('classic: connected by channel 1 (round 2)');
      expect(lines, ['classic: connected by channel 1 (round 2)']);
    });

    test('a connection that fails says what the radio said', () async {
      link.openError = const NativeLinkException(
        NativeLinkProblem.connectFailed,
        'read failed, socket might closed or timeout',
      );
      final lines = <String>[];
      transport.diagnostics.listen(lines.add);
      await expectLater(
        transport.connect(),
        throwsA(isA<TransportException>()),
      );
      expect(lines, hasLength(1));
      expect(lines.single, contains('connectFailed'));
      expect(lines.single, contains('read failed'));
    });

    test('a link that drops is said to have been lost', () async {
      await transport.connect();
      final lines = <String>[];
      transport.diagnostics.listen(lines.add);
      link.lost_.add(null);
      expect(lines, ['the link was lost']);
    });
  });
}
