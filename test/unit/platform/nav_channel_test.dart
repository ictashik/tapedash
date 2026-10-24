// The Dart side of the navigation listener, against mocked platform channels.
// The Android side (NavChannel.kt, NavBridge.kt, NavReader.kt) is not exercised
// here: see docs/NAV.md and docs/STATUS.md.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/nav/nav_notification.dart';
import 'package:tapedash/platform/nav_channel.dart';

const _methods = MethodChannel('tapedash/nav');
const _events = EventChannel('tapedash/nav/events');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  late List<MethodCall> calls;
  late Object? Function(MethodCall call) reply;

  setUp(() {
    calls = [];
    reply = (_) => null;
    messenger.setMockMethodCallHandler(_methods, (call) async {
      calls.add(call);
      return reply(call);
    });
    addTearDown(() {
      messenger.setMockMethodCallHandler(_methods, null);
      messenger.setMockStreamHandler(_events, null);
    });
  });

  group('the methods', () {
    test('access asks the platform, and says no when it is silent', () async {
      reply = (_) => true;
      expect(await NativeNavSource().hasAccess(), isTrue);
      expect(calls.single.method, 'access');

      reply = (_) => null;
      expect(await NativeNavSource().hasAccess(), isFalse);
    });

    test(
      'opening the access screen reports whether the phone had one',
      () async {
        reply = (_) => true;
        expect(await NativeNavSource().openAccessSettings(), isTrue);
        expect(calls.single.method, 'openAccessSettings');

        reply = (_) => false;
        expect(await NativeNavSource().openAccessSettings(), isFalse);
      },
    );

    test('the version of Maps, or null when it is not there', () async {
      reply = (_) => '25.33.03';
      expect(await NativeNavSource().mapsVersion(), '25.33.03');

      reply = (_) => null;
      expect(await NativeNavSource().mapsVersion(), isNull);
    });

    test('an error from the platform is a no, not a crash', () async {
      reply = (_) => throw PlatformException(code: 'bad');

      expect(await NativeNavSource().hasAccess(), isFalse);
      expect(await NativeNavSource().openAccessSettings(), isFalse);
      expect(await NativeNavSource().mapsVersion(), isNull);
    });

    test('a phone with no such channel is a no, not a crash', () async {
      messenger.setMockMethodCallHandler(_methods, null);

      expect(await NativeNavSource().hasAccess(), isFalse);
      expect(await NativeNavSource().openAccessSettings(), isFalse);
      expect(await NativeNavSource().mapsVersion(), isNull);
    });
  });

  group('the events', () {
    test('a posted notification is read in full, arrow included', () async {
      final alpha = Uint8List.fromList(List.filled(4, 255));
      messenger.setMockStreamHandler(
        _events,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({
              'event': 'posted',
              'title': '650 m · Turn right onto Mission Rd',
              'text': null,
              'subText': 'Arrive 9:25 PM',
              'shortCriticalText': '650 m',
              'progress': 171,
              'progressMax': 6605,
              'template': 'android.app.Notification\$ProgressStyle',
              'arrow': {
                'id': 'e687a80d',
                'width': 2,
                'height': 2,
                'alpha': alpha,
              },
            });
            events.success({'event': 'removed'});
            events.success({'event': 'connected'});
            events.success({'event': 'disconnected'});
            events.endOfStream();
          },
        ),
      );

      final all = await NativeNavSource().events().toList();

      expect(all, hasLength(4));
      final posted = (all[0] as NavPosted).notification;
      expect(posted.title, '650 m · Turn right onto Mission Rd');
      expect(posted.shortCriticalText, '650 m');
      expect(posted.progress, 171);
      expect(posted.progressMax, 6605);
      expect(posted.arrow!.id, 'e687a80d');
      expect(posted.arrow!.alpha, alpha);
      expect(all[1], isA<NavRemoved>());
      expect((all[2] as NavLink).connected, isTrue);
      expect((all[3] as NavLink).connected, isFalse);
    });

    test('an event it does not know is left out', () async {
      messenger.setMockStreamHandler(
        _events,
        MockStreamHandler.inline(
          onListen: (arguments, events) {
            events.success({'event': 'something new'});
            events.success('not even a map');
            events.success({'event': 'removed'});
            events.endOfStream();
          },
        ),
      );

      final all = await NativeNavSource().events().toList();

      expect(all, hasLength(1));
      expect(all.single, isA<NavRemoved>());
    });

    test(
      'listening is what starts the native reading, and stopping ends it',
      () async {
        var listens = 0;
        var cancels = 0;
        messenger.setMockStreamHandler(
          _events,
          MockStreamHandler.inline(
            onListen: (arguments, events) => listens++,
            onCancel: (arguments) => cancels++,
          ),
        );
        final source = NativeNavSource();

        expect(listens, 0, reason: 'nothing listens until asked');
        final sub = source.events().listen((_) {});
        await Future<void>.delayed(Duration.zero);
        expect(listens, 1);

        await sub.cancel();
        await Future<void>.delayed(Duration.zero);
        expect(cancels, 1);
      },
    );

    test('decode reads what a NavNotification writes', () {
      final n = NavNotification(title: 't', progress: 1, progressMax: 2);
      final event = NativeNavSource.decode({...n.toMap(), 'event': 'posted'});

      expect((event! as NavPosted).notification.title, 't');
      expect((event as NavPosted).notification.progressMax, 2);
    });
  });

  group('the fake', () {
    test(
      'counts its listeners, so a test can see a switch that is off',
      () async {
        final source = FakeNavSource();
        expect(source.listeners, 0);

        final sub = source.events().listen((_) {});
        expect(source.listeners, 1);
        await sub.cancel();
        expect(source.listeners, 0);
      },
    );
  });
}
