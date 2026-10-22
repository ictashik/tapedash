// AdapterRadio against mocked platform channels, for both radios. The Android
// sides (BtClassicChannel.kt, BleChannel.kt) are not exercised here; see
// docs/STATUS.md for what has and has not been verified on a phone.
import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/obd/transport/native_link.dart';
import 'package:tapedash/obd/transport/native_link_transport.dart';
import 'package:tapedash/obd/transport/transport.dart';
import 'package:tapedash/platform/adapter_radio.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  for (final kind in RadioKind.values) {
    group(kind.label, () {
      final methods = MethodChannel('tapedash/${kind.channel}');
      final events = EventChannel('tapedash/${kind.channel}/events');

      late List<MethodCall> calls;
      late Object? Function(MethodCall call) reply;
      MockStreamHandlerEventSink? sink;
      var listens = 0;
      late AdapterRadio radio;

      setUp(() {
        calls = [];
        sink = null;
        listens = 0;
        reply = (call) => null;
        radio = AdapterRadio(kind);
        messenger.setMockMethodCallHandler(methods, (call) async {
          calls.add(call);
          return reply(call);
        });
        messenger.setMockStreamHandler(
          events,
          MockStreamHandler.inline(
            onListen: (arguments, e) {
              listens++;
              sink = e;
            },
            onCancel: (arguments) => sink = null,
          ),
        );
        addTearDown(() {
          messenger.setMockMethodCallHandler(methods, null);
          messenger.setMockStreamHandler(events, null);
        });
      });

      Future<void> settle() => Future<void>.delayed(Duration.zero);

      test(
        'the status says whether the radio is there, on and allowed',
        () async {
          reply = (call) => {
            'supported': true,
            'enabled': false,
            'permitted': true,
          };
          final status = await radio.status();
          expect(status.supported, isTrue);
          expect(status.enabled, isFalse);
          expect(status.permitted, isTrue);
          expect(status.ready, isFalse);

          reply = (call) => {
            'supported': true,
            'enabled': true,
            'permitted': true,
          };
          expect((await radio.status()).ready, isTrue);
        },
      );

      test('a missing status is a radio that is not there', () async {
        reply = (call) => null;
        expect((await radio.status()).supported, isFalse);
      });

      test('permission is asked for, and the answer passed on', () async {
        reply = (call) => call.method == 'requestPermission' ? true : null;
        expect(await radio.requestPermission(), isTrue);
        reply = (call) => false;
        expect(await radio.requestPermission(), isFalse);
      });

      test('paired adapters are listed, the malformed ones skipped', () async {
        reply = (call) => [
          {'name': 'OBDII', 'address': '00:1D:A5:00:00:01'},
          {'address': '11:22:33:44:55:66'},
          {'name': 'no address'},
          'nonsense',
        ];
        final found = await radio.paired();
        expect(
          [for (final a in found) a.address],
          ['00:1D:A5:00:00:01', '11:22:33:44:55:66'],
        );
        expect(found.first.displayName, 'OBDII');
        expect(found.first.paired, isTrue);
        expect(found.first.kind, kind);
        expect(found.last.displayName, '11:22:33:44:55:66');
      });

      test(
        'a scan reports each adapter once, and stops when cancelled',
        () async {
          final found = <FoundAdapter>[];
          final sub = radio.scan().listen(found.add);
          await settle();
          expect(calls.map((c) => c.method), ['startScan']);
          expect(listens, 1);

          sink!.success({'type': 'found', 'name': 'OBDII', 'address': 'AA:01'});
          sink!.success({'type': 'found', 'name': 'OBDII', 'address': 'AA:01'});
          sink!.success({'type': 'found', 'address': 'AA:02', 'paired': true});
          sink!.success({'type': 'found', 'name': 'x'}); // no address
          sink!.success('garbage');
          await settle();
          expect([for (final a in found) a.address], ['AA:01', 'AA:02']);
          expect(found.last.paired, isTrue);

          await sub.cancel();
          await settle();
          expect(calls.map((c) => c.method), ['startScan', 'stopScan']);
          expect(sink, isNull, reason: 'the event stream is let go');
        },
      );

      test('a scan that cannot start says why, and ends', () async {
        reply = (call) {
          if (call.method == 'startScan') {
            throw PlatformException(code: 'radio_off', message: 'off');
          }
          return null;
        };
        final done = Completer<void>();
        Object? error;
        radio.scan().listen(
          (_) {},
          onError: (Object e) => error = e,
          onDone: done.complete,
        );
        await done.future;
        expect(error, isA<NativeLinkException>());
        expect(
          (error! as NativeLinkException).problem,
          NativeLinkProblem.radioOff,
        );
      });

      test('pairing passes the address, and a refusal is a problem', () async {
        await radio.pair('AA:01');
        expect(calls.single.method, 'pair');
        expect(calls.single.arguments, {'address': 'AA:01'});

        reply = (call) => throw PlatformException(code: 'connect_failed');
        await expectLater(
          radio.pair('AA:01'),
          throwsA(
            isA<NativeLinkException>().having(
              (e) => e.problem,
              'problem',
              NativeLinkProblem.connectFailed,
            ),
          ),
        );
      });

      test(
        'forgetting a pairing passes the address, and a refusal is a problem',
        () async {
          await radio.unpair('AA:01');
          expect(calls.single.method, 'unpair');
          expect(calls.single.arguments, {'address': 'AA:01'});

          reply = (call) => throw PlatformException(code: 'connect_failed');
          await expectLater(
            radio.unpair('AA:01'),
            throwsA(isA<NativeLinkException>()),
          );
        },
      );

      test('a link opens, sends, receives, and closes', () async {
        final link = radio.link('AA:01');
        final text = StringBuffer();
        link.incoming.listen(text.write);

        await link.open();
        expect(calls.single.method, 'open');
        expect(calls.single.arguments, {'address': 'AA:01'});
        expect(listens, 1);

        await link.send('ATZ\r');
        expect(calls.last.method, 'send');
        expect(calls.last.arguments, {'text': 'ATZ\r'});

        sink!.success({'type': 'data', 'text': '\r\rELM327 v1.5\r\r>'});
        await settle();
        expect(text.toString(), '\r\rELM327 v1.5\r\r>');

        await link.close();
        expect(calls.last.method, 'close');
        await settle();
        expect(sink, isNull, reason: 'the event stream is let go');
      });

      test('the link dropping underneath is reported as lost', () async {
        final link = radio.link('AA:01');
        var lost = 0;
        link.lost.listen((_) => lost++);
        await link.open();
        sink!.success({'type': 'lost'});
        await settle();
        expect(lost, 1);
      });

      test('the platform\'s error codes become problems', () async {
        final expected = {
          'permission_denied': NativeLinkProblem.permissionDenied,
          'radio_off': NativeLinkProblem.radioOff,
          'unsupported': NativeLinkProblem.unsupported,
          'connect_failed': NativeLinkProblem.connectFailed,
          'not_connected': NativeLinkProblem.notConnected,
          'something_else': NativeLinkProblem.other,
        };
        for (final entry in expected.entries) {
          reply = (call) =>
              throw PlatformException(code: entry.key, message: 'm');
          final link = radio.link('AA:01');
          await expectLater(
            link.open(),
            throwsA(
              isA<NativeLinkException>()
                  .having((e) => e.problem, 'problem', entry.value)
                  .having((e) => e.message, 'message', 'm'),
            ),
            reason: entry.key,
          );
          await expectLater(
            link.send('x'),
            throwsA(
              isA<NativeLinkException>().having(
                (e) => e.problem,
                'problem',
                entry.value,
              ),
            ),
          );
        }
      });

      test('a whole transport over it: connect, talk, lose the link', () async {
        final transport = NativeLinkTransport(radio.link('AA:01'));
        addTearDown(transport.dispose);
        final text = StringBuffer();
        transport.incoming.listen(text.write);

        await transport.connect();
        expect(transport.currentState, TransportState.connected);
        await transport.write('ATZ\r');
        sink!.success({'type': 'data', 'text': 'ELM327 v1.5\r>'});
        await settle();
        expect(text.toString(), 'ELM327 v1.5\r>');

        sink!.success({'type': 'lost'});
        await settle();
        expect(
          transport.currentState,
          const TransportState.disconnected(failure: TransportFailure.lost),
        );
      });

      test(
        'scanning and a link share the event stream, and it stays open for the last',
        () async {
          final sub = radio.scan().listen((_) {});
          await settle();
          final link = radio.link('AA:01');
          await link.open();
          expect(listens, 1, reason: 'one event stream for both');

          await sub.cancel();
          await settle();
          expect(sink, isNotNull, reason: 'the link still needs it');
          await link.close();
          await settle();
          expect(sink, isNull);
        },
      );
    });
  }

  group('what an adapter looks like', () {
    test('names of the usual adapters are put first, nothing is hidden', () {
      FoundAdapter a(String name) =>
          FoundAdapter(name: name, address: 'AA', kind: RadioKind.ble);
      expect(a('OBDII').looksLikeAdapter, isTrue);
      expect(a('Vgate iCar Pro').looksLikeAdapter, isTrue);
      expect(a('VEEPEAK').looksLikeAdapter, isTrue);
      expect(a('ELM327 v1.5').looksLikeAdapter, isTrue);
      expect(a('JBL Flip 5').looksLikeAdapter, isFalse);
      expect(a('').looksLikeAdapter, isFalse);
    });

    test('two sightings of one address are the same adapter', () {
      const x = FoundAdapter(name: 'a', address: 'AA', kind: RadioKind.ble);
      const y = FoundAdapter(name: 'b', address: 'AA', kind: RadioKind.ble);
      const z = FoundAdapter(
        name: 'a',
        address: 'AA',
        kind: RadioKind.bluetoothClassic,
      );
      expect(x, y);
      expect(x, isNot(z));
    });
  });
}
