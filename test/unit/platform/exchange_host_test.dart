// The exchange host against a mocked platform channel. The Android side
// (ExchangeChannel.kt) is not exercised here; see docs/STATUS.md for what has and
// has not been verified on a device.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/exchange/tdx_format.dart';
import 'package:tapedash/platform/exchange_host.dart';

const _channel = MethodChannel('tapedash/exchange');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Object? Function(MethodCall) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      return reply(call);
    });
    addTearDown(() => messenger.setMockMethodCallHandler(_channel, null));
  });

  group('the launch\'s request', () {
    test('an export, with the scopes adb named', () async {
      reply = (_) => {
        'operation': 'export',
        'scopes': 'trips, fillups,nonsense',
        'applyProfile': false,
      };
      final r = await NativeExchangeHost().takeRequest();
      expect(r!.isExport, isTrue);
      expect(r.scopes, {TdxScope.trips, TdxScope.fillups});
      expect(r.applyProfile, isFalse);
      expect(calls.single.method, 'takeRequest');
    });

    test('an import that may apply the setup', () async {
      reply = (_) => {'operation': 'import', 'applyProfile': true};
      final r = await NativeExchangeHost().takeRequest();
      expect(r!.isImport, isTrue);
      expect(r.scopes, isNull);
      expect(r.applyProfile, isTrue);
    });

    test('scopes that are all unknown mean the default', () async {
      reply = (_) => {'operation': 'export', 'scopes': 'x,y'};
      expect((await NativeExchangeHost().takeRequest())!.scopes, isNull);
    });

    test(
      'nothing, a request we do not know, and a platform with no channel',
      () async {
        reply = (_) => null;
        expect(await NativeExchangeHost().takeRequest(), isNull);
        reply = (_) => {'operation': 'delete everything'};
        expect(await NativeExchangeHost().takeRequest(), isNull);
        messenger.setMockMethodCallHandler(_channel, null);
        expect(await NativeExchangeHost().takeRequest(), isNull);
      },
    );
  });

  test(
    'says what the phone can do: a phone has both, a watch neither',
    () async {
      reply = (_) => {'canPick': true, 'canShare': true};
      var c = await NativeExchangeHost().capabilities();
      expect((c.canPick, c.canShare), (true, true));
      reply = (_) => {'canPick': false, 'canShare': false};
      c = await NativeExchangeHost().capabilities();
      expect((c.canPick, c.canShare), (false, false));
      messenger.setMockMethodCallHandler(_channel, null);
      c = await NativeExchangeHost().capabilities();
      expect((c.canPick, c.canShare), (false, false));
    },
  );

  test('picks a file and shares one, and a failure is a no', () async {
    reply = (c) => c.method == 'pickFile' ? '/cache/exchange_in/x.tdx' : true;
    final host = NativeExchangeHost();
    expect(await host.pickFile(), '/cache/exchange_in/x.tdx');
    expect(await host.shareFile('/files/out.tdx.gz'), isTrue);
    expect(calls.last.arguments, {'path': '/files/out.tdx.gz'});

    reply = (_) => throw PlatformException(code: 'no');
    expect(await host.pickFile(), isNull);
    expect(await host.shareFile('/x'), isFalse);
  });

  test('is told when a request arrives while the app is running', () async {
    final host = NativeExchangeHost();
    final seen = <void>[];
    final sub = host.arrivals.listen(seen.add);
    await messenger.handlePlatformMessage(
      'tapedash/exchange',
      const StandardMethodCodec().encodeMethodCall(
        const MethodCall('requestArrived'),
      ),
      (_) {},
    );
    await Future<void>.delayed(Duration.zero);
    expect(seen, hasLength(1));
    await sub.cancel();
  });

  test(
    'the fake host gives a request once, and records what was shared',
    () async {
      final host = FakeExchangeHost(
        request: const ExchangeRequest(operation: 'export'),
        canShare: true,
      );
      expect((await host.takeRequest())!.isExport, isTrue);
      expect(await host.takeRequest(), isNull);
      expect(await host.shareFile('/a'), isTrue);
      expect(host.shared, ['/a']);
      expect(await host.pickFile(), isNull, reason: 'no picker here');
      host.arrive(const ExchangeRequest(operation: 'import'));
      expect((await host.takeRequest())!.isImport, isTrue);
    },
  );
}
