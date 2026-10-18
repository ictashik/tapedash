import 'package:flutter/services.dart';

/// Hands a picture the app made to the phone's own share sheet, so that the person
/// can post it or save it wherever they choose. The app itself sends nothing
/// anywhere: it writes the file, and Android's chooser does the rest (CLAUDE.md 1).
abstract interface class ImageSharer {
  /// Opens the share sheet for [png], named [name] (without an extension).
  /// Returns false if the phone had nothing to open it with, or it failed.
  Future<bool> sharePng(Uint8List png, {required String name});
}

/// [ImageSharer] on the platform channel implemented by `ShareChannel.kt`.
///
/// Unverified on hardware until the handoff (CLAUDE.md 11): the tests run against a
/// mocked channel.
class NativeImageSharer implements ImageSharer {
  NativeImageSharer({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('tapedash/share');

  final MethodChannel _channel;

  @override
  Future<bool> sharePng(Uint8List png, {required String name}) async {
    try {
      final ok = await _channel.invokeMethod<bool>('shareImage', {
        'bytes': png,
        'name': name,
      });
      return ok ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// An [ImageSharer] that keeps what it was given, for tests and for a phone with
/// no share sheet.
class MemoryImageSharer implements ImageSharer {
  MemoryImageSharer({this.succeed = true});

  final bool succeed;
  final List<({Uint8List png, String name})> shared = [];

  @override
  Future<bool> sharePng(Uint8List png, {required String name}) async {
    shared.add((png: png, name: name));
    return succeed;
  }
}
