// The Dart side of the share sheet, against a mocked platform channel. The
// Android side (ShareChannel.kt) is not exercised here; see docs/STATUS.md.

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:tapedash/platform/image_sharer.dart';

const _channel = MethodChannel('tapedash/share');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  void mock(Future<Object?>? Function(MethodCall call) handler) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_channel, handler);
    addTearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(_channel, null),
    );
  }

  final png = Uint8List.fromList([0x89, 0x50, 0x4e, 0x47, 1, 2, 3]);

  test('it hands the bytes and the name to the platform', () async {
    MethodCall? seen;
    mock((call) async {
      seen = call;
      return true;
    });
    final ok = await NativeImageSharer().sharePng(png, name: 'tapedash-2026');
    expect(ok, isTrue);
    expect(seen!.method, 'shareImage');
    final args = seen!.arguments as Map<Object?, Object?>;
    expect(args['name'], 'tapedash-2026');
    expect(args['bytes'], png);
  });

  test('a platform that says no, or nothing, is a no', () async {
    mock((call) async => false);
    expect(await NativeImageSharer().sharePng(png, name: 'x'), isFalse);
    mock((call) async => null);
    expect(await NativeImageSharer().sharePng(png, name: 'x'), isFalse);
  });

  test('an error from the platform is a no, not a crash', () async {
    mock((call) async => throw PlatformException(code: 'bad_args'));
    expect(await NativeImageSharer().sharePng(png, name: 'x'), isFalse);
  });

  test('a phone with no such channel is a no, not a crash', () async {
    expect(await NativeImageSharer().sharePng(png, name: 'x'), isFalse);
  });

  test('the in-memory sharer keeps what it was given', () async {
    final sharer = MemoryImageSharer();
    expect(await sharer.sharePng(png, name: 'a'), isTrue);
    expect(sharer.shared.single.name, 'a');
    expect(
      await MemoryImageSharer(succeed: false).sharePng(png, name: 'b'),
      isFalse,
    );
  });
}
