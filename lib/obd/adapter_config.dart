import 'dart:convert';

import '../core/key_value_store.dart';
import '../core/observable.dart';
import 'obd_session.dart' show AdapterMemory;

/// How an adapter is reached.
enum AdapterKind {
  bluetoothClassic('Bluetooth'),
  ble('Bluetooth LE'),
  wifi('WiFi');

  const AdapterKind(this.label);

  final String label;
}

/// Where the drive's speed comes from. Nothing else is ever substituted for it:
/// an adapter that will not connect stays "looking for your adapter" and does not
/// quietly become another source.
enum DriveSource {
  /// The car, through the OBD adapter the user chose.
  obd,

  /// The phone's GPS alone: speed, distance and time, with no adapter.
  gps,
}

/// The adapter the user chose (DESIGN.md 7.11): what to open a link to, and what
/// to call it.
class AdapterConfig {
  const AdapterConfig({
    required this.kind,
    required this.address,
    this.name = '',
    this.port,
  });

  final AdapterKind kind;

  /// The Bluetooth address (`AA:BB:CC:DD:EE:FF`), or the WiFi adapter's IP
  /// address.
  final String address;

  /// What the adapter calls itself, if it says.
  final String name;

  /// The TCP port, for WiFi.
  final int? port;

  /// What to call it on screen.
  String get displayName => name.isEmpty ? address : name;

  /// A key that is the same for the same adapter, for what is remembered about
  /// it (the protocol it found).
  String get id => switch (kind) {
    AdapterKind.wifi => 'wifi:$address:${port ?? 35000}',
    _ => '${kind.name}:$address',
  };

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'address': address,
    'name': name,
    if (port != null) 'port': port,
  };

  /// The config in [json], or null if it is not one.
  static AdapterConfig? fromJson(Object? json) {
    if (json is! Map) return null;
    final kind = AdapterKind.values
        .where((k) => k.name == json['kind'])
        .firstOrNull;
    final address = json['address'];
    if (kind == null || address is! String || address.isEmpty) return null;
    final port = json['port'];
    return AdapterConfig(
      kind: kind,
      address: address,
      name: json['name'] is String ? json['name'] as String : '',
      port: port is int ? port : null,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is AdapterConfig &&
      other.kind == kind &&
      other.address == address &&
      other.port == port &&
      other.name == name;

  @override
  int get hashCode => Object.hash(kind, address, port, name);

  @override
  String toString() => 'AdapterConfig(${kind.name} $address)';
}

/// The adapter the app uses, and how it is used, kept on the phone (CLAUDE.md 5).
class AdapterStore {
  AdapterStore(this._store, {this.recordByDefault = false});

  /// Whether sessions are recorded until the user says otherwise: on for a debug
  /// build, which is a build for finding things out, and off for a release one.
  /// What the user has chosen in Garage is kept either way.
  final bool recordByDefault;

  static const _adapterKey = 'adapter_config';
  static const _sourceKey = 'drive_source';
  static const _compatKey = 'adapter_compatibility';
  static const _recordKey = 'adapter_record_sessions';
  static const _protocolPrefix = 'adapter_protocol_';

  final KeyValueStore _store;

  final ObservableValue<AdapterConfig?> _adapter = ObservableValue(null);
  final ObservableValue<DriveSource?> _source = ObservableValue(null);
  final ObservableValue<bool> _compat = ObservableValue(false);
  final ObservableValue<bool> _record = ObservableValue(false);

  /// The adapter last chosen, or null if none has been.
  Observable<AdapterConfig?> get adapter => _adapter;

  /// Where the drive comes from, or null until the person has chosen: the app then
  /// asks, and shows nothing in the meantime.
  Observable<DriveSource?> get source => _source;

  /// Compatibility mode forced on (CLAUDE.md 8.1): no batching and a slower pace,
  /// for an adapter that cannot keep up.
  Observable<bool> get compatibilityMode => _compat;

  /// Whether each drive's raw adapter traffic is written to a file, for the
  /// hardware handoff (CLAUDE.md 11).
  Observable<bool> get recordSessions => _record;

  Future<void> load() async {
    final raw = await _store.getString(_adapterKey);
    if (raw != null) {
      try {
        _adapter.value = AdapterConfig.fromJson(jsonDecode(raw));
      } on FormatException {
        _adapter.value = null;
      }
    }
    final stored = await _store.getString(_sourceKey);
    var source = DriveSource.values.where((s) => s.name == stored).firstOrNull;
    // An adapter cannot be the source without one chosen.
    if (source == DriveSource.obd && _adapter.value == null) source = null;
    // Builds from before the source was a setting had two states, the adapter
    // (when one was chosen and in use) or the demo. The demo is gone: an adapter
    // that was chosen is the source.
    if (source == null && _adapter.value != null) source = DriveSource.obd;
    _source.value = source;
    _compat.value = await _store.getBool(_compatKey) ?? false;
    _record.value = await _store.getBool(_recordKey) ?? recordByDefault;
  }

  /// Remembers [config] as the adapter, and switches to driving from it.
  Future<void> choose(AdapterConfig config) async {
    _adapter.value = config;
    _source.value = DriveSource.obd;
    await _store.setString(_adapterKey, jsonEncode(config.toJson()));
    await _store.setString(_sourceKey, DriveSource.obd.name);
  }

  /// Forgets the adapter. If it was the source, there is none until the person
  /// chooses again (an adapter, or the GPS).
  Future<void> forget() async {
    final was = _adapter.value;
    _adapter.value = null;
    await _store.remove(_adapterKey);
    if (_source.value == DriveSource.obd) {
      _source.value = null;
      await _store.remove(_sourceKey);
    }
    if (was != null) await _store.remove('$_protocolPrefix${was.id}');
  }

  /// Drives from the adapter or from the GPS alone, without forgetting the
  /// adapter. The adapter cannot be the source until one is chosen.
  Future<void> setSource(DriveSource source) async {
    if (source == DriveSource.obd && _adapter.value == null) return;
    _source.value = source;
    await _store.setString(_sourceKey, source.name);
  }

  Future<void> setCompatibilityMode(bool on) async {
    _compat.value = on;
    await _store.setBool(_compatKey, on);
  }

  Future<void> setRecordSessions(bool on) async {
    _record.value = on;
    await _store.setBool(_recordKey, on);
  }

  /// What is remembered about [config]: the protocol it found last time, so that
  /// it is set directly next time (CLAUDE.md 8.1).
  Future<AdapterMemory> memoryFor(AdapterConfig config) async {
    final key = '$_protocolPrefix${config.id}';
    return _StoredMemory(_store, key, await _store.getString(key));
  }
}

class _StoredMemory implements AdapterMemory {
  _StoredMemory(this._store, this._key, this._protocol);

  final KeyValueStore _store;
  final String _key;
  String? _protocol;

  @override
  String? get protocol => _protocol;

  @override
  set protocol(String? value) {
    _protocol = value;
    // The session cannot wait for the phone's storage; a failed write only means
    // the search is done again next time.
    if (value == null) {
      _store.remove(_key);
    } else {
      _store.setString(_key, value);
    }
  }
}
