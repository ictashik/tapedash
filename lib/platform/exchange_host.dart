import 'dart:async';

import 'package:flutter/services.dart';

import '../exchange/tdx_format.dart';

/// A request that arrived with the launch, from adb (docs/EXCHANGE.md 5):
/// `am start -n <package>/.MainActivity --es tapedash.exchange export`.
class ExchangeRequest {
  const ExchangeRequest({
    required this.operation,
    this.scopes,
    this.applyProfile = false,
  });

  /// `export` or `import`.
  final String operation;

  /// What to export, or the default when null.
  final Set<TdxScope>? scopes;

  /// Whether an import may apply the file's setup.
  final bool applyProfile;

  bool get isExport => operation == 'export';
  bool get isImport => operation == 'import';

  @override
  String toString() => 'ExchangeRequest($operation, $scopes, $applyProfile)';
}

/// What the phone can do for the exchange that Dart cannot: take the launch's
/// request, open Android's own file picker and share sheet. A watch has neither
/// of the last two.
abstract interface class ExchangeHost {
  /// Fires when a request arrives while the app is already running (adb starts
  /// the activity again): ask for it with [takeRequest].
  Stream<void> get arrivals;

  /// The request that came with the launch, once: it is cleared as it is taken.
  Future<ExchangeRequest?> takeRequest();

  /// Whether the phone has a picker and a share sheet to use.
  Future<({bool canPick, bool canShare})> capabilities();

  /// Asks Android's file picker for a file; it is copied into the app's cache and
  /// its path returned. Null if cancelled or there is no picker. The app is given
  /// that one file and no storage permission.
  Future<String?> pickFile();

  /// Opens the share sheet for the file at [path]. False if there is none to open.
  Future<bool> shareFile(String path);
}

/// [ExchangeHost] on the platform channel implemented by `ExchangeChannel.kt`.
///
/// Unverified on hardware until the handoff (CLAUDE.md 11): the tests run against a
/// mocked channel.
class NativeExchangeHost implements ExchangeHost {
  NativeExchangeHost({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('tapedash/exchange') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'requestArrived') _arrivals.add(null);
      return null;
    });
  }

  final MethodChannel _channel;
  final StreamController<void> _arrivals = StreamController<void>.broadcast();

  @override
  Stream<void> get arrivals => _arrivals.stream;

  @override
  Future<ExchangeRequest?> takeRequest() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>(
        'takeRequest',
      );
      if (map == null) return null;
      final operation = map['operation'];
      if (operation != 'export' && operation != 'import') return null;
      Set<TdxScope>? scopes;
      final raw = map['scopes'];
      if (raw is String && raw.trim().isNotEmpty) {
        scopes = {
          for (final name in raw.split(','))
            if (TdxScope.named(name.trim()) != null)
              TdxScope.named(name.trim())!,
        };
        if (scopes.isEmpty) scopes = null;
      }
      return ExchangeRequest(
        operation: operation as String,
        scopes: scopes,
        applyProfile: map['applyProfile'] == true,
      );
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<({bool canPick, bool canShare})> capabilities() async {
    try {
      final map = await _channel.invokeMapMethod<String, Object?>(
        'capabilities',
      );
      return (
        canPick: map?['canPick'] == true,
        canShare: map?['canShare'] == true,
      );
    } on PlatformException {
      return (canPick: false, canShare: false);
    } on MissingPluginException {
      return (canPick: false, canShare: false);
    }
  }

  @override
  Future<String?> pickFile() async {
    try {
      return await _channel.invokeMethod<String>('pickFile');
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }

  @override
  Future<bool> shareFile(String path) async {
    try {
      return await _channel.invokeMethod<bool>('shareFile', {'path': path}) ??
          false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }
}

/// An [ExchangeHost] for tests, and for a device with none of it: what it is told
/// to give, and a record of what it was asked to share.
class FakeExchangeHost implements ExchangeHost {
  FakeExchangeHost({
    this.request,
    this.canPick = false,
    this.canShare = false,
    this.picked,
  });

  ExchangeRequest? request;
  final StreamController<void> _arrivals = StreamController<void>.broadcast();

  /// Says a request has arrived, as adb starting the app again does.
  void arrive(ExchangeRequest r) {
    request = r;
    _arrivals.add(null);
  }

  @override
  Stream<void> get arrivals => _arrivals.stream;

  bool canPick;
  bool canShare;

  /// The path [pickFile] returns.
  String? picked;

  final List<String> shared = [];

  @override
  Future<ExchangeRequest?> takeRequest() async {
    final r = request;
    request = null;
    return r;
  }

  @override
  Future<({bool canPick, bool canShare})> capabilities() async =>
      (canPick: canPick, canShare: canShare);

  @override
  Future<String?> pickFile() async => canPick ? picked : null;

  @override
  Future<bool> shareFile(String path) async {
    if (!canShare) return false;
    shared.add(path);
    return true;
  }
}
