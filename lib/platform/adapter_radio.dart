import 'dart:async';

import 'package:flutter/services.dart';

import '../obd/transport/native_link.dart';

/// Which radio an adapter is reached over.
enum RadioKind {
  /// Bluetooth Classic (SPP, RFCOMM): the cheap ELM327s that are paired in
  /// Android's settings, most of the ones sold in India.
  bluetoothClassic('bt_classic', 'Bluetooth'),

  /// Bluetooth Low Energy (GATT): the newer "BLE" adapters.
  ble('ble', 'Bluetooth LE');

  const RadioKind(this.channel, this.label);

  /// The stem of the platform channel names (`tapedash/<channel>`).
  final String channel;
  final String label;
}

/// What the phone's radio is like right now.
class RadioStatus {
  const RadioStatus({
    required this.supported,
    required this.enabled,
    required this.permitted,
  });

  /// The phone has this radio.
  final bool supported;

  /// It is switched on.
  final bool enabled;

  /// The user has allowed the app to use it (and to look for nearby devices).
  final bool permitted;

  bool get ready => supported && enabled && permitted;

  @override
  String toString() =>
      'RadioStatus(supported: $supported, enabled: $enabled, permitted: $permitted)';
}

/// An adapter the radio found, or has already paired.
class FoundAdapter {
  const FoundAdapter({
    required this.name,
    required this.address,
    required this.kind,
    this.paired = false,
  });

  /// The name it advertises. Empty for a device that says none.
  final String name;

  /// The Bluetooth address, `AA:BB:CC:DD:EE:FF`.
  final String address;
  final RadioKind kind;
  final bool paired;

  /// What to call it on screen.
  String get displayName => name.isEmpty ? address : name;

  /// Whether the name looks like an OBD adapter: an ELM327 or one of the usual
  /// brands. Only used to put likely adapters first; nothing is hidden.
  bool get looksLikeAdapter {
    final n = name.toLowerCase();
    return const [
      'obd',
      'elm',
      'vlink',
      'vgate',
      'icar',
      'veepeak',
      'konnwei',
      'carista',
      'viecar',
      'v-link',
    ].any(n.contains);
  }

  @override
  bool operator ==(Object other) =>
      other is FoundAdapter && other.address == address && other.kind == kind;

  @override
  int get hashCode => Object.hash(address, kind);
}

/// A phone's Bluetooth radio, for finding an adapter and opening a link to it
/// (CLAUDE.md 5): the Dart side of `BtClassicChannel.kt` and `BleChannel.kt`.
///
/// Both radios speak the same channel vocabulary, so this one class serves both.
/// **Unverified on hardware until the handoff (CLAUDE.md 11).** The tests run
/// against mocked channels.
class AdapterRadio {
  AdapterRadio(this.kind, {MethodChannel? methods, EventChannel? events})
    : _methods = methods ?? MethodChannel('tapedash/${kind.channel}'),
      _events = events ?? EventChannel('tapedash/${kind.channel}/events');

  final RadioKind kind;
  final MethodChannel _methods;
  final EventChannel _events;

  final StreamController<FoundAdapter> _found = StreamController.broadcast();
  final StreamController<String> _data = StreamController.broadcast(sync: true);
  final StreamController<void> _lost = StreamController.broadcast(sync: true);
  StreamSubscription<Object?>? _subscription;
  int _listeners = 0;

  // The event stream is shared by scanning and by the link, so it is opened by
  // whichever needs it first and closed with the last.
  void _retain() {
    if (_listeners++ > 0) return;
    _subscription = _events.receiveBroadcastStream().listen(_onEvent);
  }

  void _release() {
    if (--_listeners > 0) return;
    _listeners = 0;
    _subscription?.cancel();
    _subscription = null;
  }

  void _onEvent(Object? event) {
    if (event is! Map) return;
    switch (event['type']) {
      case 'found':
        final address = event['address'];
        if (address is! String) return;
        _found.add(
          FoundAdapter(
            name: (event['name'] as String?) ?? '',
            address: address,
            kind: kind,
            paired: event['paired'] == true,
          ),
        );
      case 'data':
        final text = event['text'];
        if (text is String) _data.add(text);
      case 'lost':
        _lost.add(null);
    }
  }

  /// Whether the radio is there, on, and allowed.
  Future<RadioStatus> status() async {
    final reply = await _methods.invokeMapMethod<String, Object?>('status');
    return RadioStatus(
      supported: reply?['supported'] == true,
      enabled: reply?['enabled'] == true,
      permitted: reply?['permitted'] == true,
    );
  }

  /// Asks the user for the permissions the radio needs, and says whether they
  /// are now given.
  Future<bool> requestPermission() async =>
      await _methods.invokeMethod<bool>('requestPermission') ?? false;

  /// The adapters the phone has already paired (Bluetooth Classic; BLE has no
  /// pairing step, so it has none).
  Future<List<FoundAdapter>> paired() async {
    final reply =
        await _methods.invokeListMethod<Object?>('paired') ?? const [];
    return [
      for (final e in reply)
        if (e is Map && e['address'] is String)
          FoundAdapter(
            name: (e['name'] as String?) ?? '',
            address: e['address'] as String,
            kind: kind,
            paired: true,
          ),
    ];
  }

  /// Looks for nearby adapters until the stream is cancelled. Each is reported
  /// once, however often the radio hears it.
  Stream<FoundAdapter> scan() {
    late final StreamController<FoundAdapter> out;
    StreamSubscription<FoundAdapter>? sub;
    final seen = <String>{};
    out = StreamController<FoundAdapter>(
      onListen: () async {
        _retain();
        sub = _found.stream.listen((a) {
          if (seen.add(a.address)) out.add(a);
        });
        try {
          await _methods.invokeMethod<void>('startScan');
        } on PlatformException catch (e) {
          out.addError(_problemOf(e));
          await out.close();
        }
      },
      onCancel: () async {
        await sub?.cancel();
        _release();
        try {
          await _methods.invokeMethod<void>('stopScan');
        } on PlatformException {
          // Nothing left to stop.
        }
      },
    );
    return out.stream;
  }

  /// Pairs with [address] (Bluetooth Classic), which makes the phone ask the user
  /// for the adapter's PIN if it wants one. Completes when the pairing is done.
  Future<void> pair(String address) async {
    try {
      await _methods.invokeMethod<void>('pair', {'address': address});
    } on PlatformException catch (e) {
      throw _problemOf(e);
    }
  }

  /// A pipe to the adapter at [address].
  NativeLink link(String address) => _ChannelLink(this, address);

  static NativeLinkException _problemOf(PlatformException e) {
    final problem = switch (e.code) {
      'permission_denied' => NativeLinkProblem.permissionDenied,
      'radio_off' => NativeLinkProblem.radioOff,
      'unsupported' => NativeLinkProblem.unsupported,
      'connect_failed' => NativeLinkProblem.connectFailed,
      'not_connected' => NativeLinkProblem.notConnected,
      _ => NativeLinkProblem.other,
    };
    return NativeLinkException(problem, e.message);
  }
}

class _ChannelLink implements NativeLink {
  _ChannelLink(this._radio, this.address);

  final AdapterRadio _radio;
  final String address;
  bool _retained = false;

  @override
  Stream<String> get incoming => _radio._data.stream;

  @override
  Stream<void> get lost => _radio._lost.stream;

  @override
  Future<void> open() async {
    if (!_retained) {
      _radio._retain();
      _retained = true;
    }
    try {
      await _radio._methods.invokeMethod<void>('open', {'address': address});
    } on PlatformException catch (e) {
      _releaseEvents();
      throw AdapterRadio._problemOf(e);
    }
  }

  @override
  Future<void> close() async {
    try {
      await _radio._methods.invokeMethod<void>('close');
    } on PlatformException {
      // Nothing left to close.
    } finally {
      _releaseEvents();
    }
  }

  void _releaseEvents() {
    if (!_retained) return;
    _retained = false;
    _radio._release();
  }

  @override
  Future<void> send(String text) async {
    try {
      await _radio._methods.invokeMethod<void>('send', {'text': text});
    } on PlatformException catch (e) {
      throw AdapterRadio._problemOf(e);
    }
  }
}
