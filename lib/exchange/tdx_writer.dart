import 'dart:convert';

import '../insights/rest_voltage_log.dart' show RestReading;
import '../money/fill_up.dart';
import '../trips/trip.dart';
import 'crc32.dart';
import 'tdx_codec.dart';
import 'tdx_format.dart';

/// Writes an exchange file a line at a time (docs/EXCHANGE.md 1), to wherever
/// [emit] sends bytes: a file, a gzip encoder, a list in a test.
///
/// Nothing is held: each line is encoded, counted in the footer, added to the
/// checksum and passed on, so a year of trips is written without being in memory.
/// The order is the header, then the records in any order, then [finish].
class TdxWriter {
  TdxWriter(this._emit);

  final void Function(List<int> bytes) _emit;
  final Crc32 _crc = Crc32();
  final Map<String, int> _counts = {};
  bool _started = false;
  bool _finished = false;

  /// How many lines of each type have been written.
  Map<String, int> get counts => Map.unmodifiable(_counts);

  /// The header: where and when this was made, and what it was asked to hold.
  void header({
    required String appVersion,
    required DateTime created,
    required TdxDeviceInfo device,
    required Set<TdxScope> scopes,
  }) {
    if (_started) throw StateError('The header is written once, first.');
    _started = true;
    _line({
      't': 'tdx',
      'v': Tdx.version,
      'app': Tdx.app,
      'appVersion': appVersion,
      'createdMs': created.millisecondsSinceEpoch,
      'created': created.toUtc().toIso8601String(),
      'device': device.toJson(),
      'scopes': [
        for (final s in TdxScope.values)
          if (scopes.contains(s)) s.name,
      ],
    }, count: null);
  }

  /// The portable setup (already cleaned, see `TdxProfile`).
  void profile(Map<String, Object?> values) =>
      _record('profile', {'t': 'profile', ...values});

  /// The settings of this one screen.
  void device(Map<String, Object?> values) =>
      _record('device', {'t': 'device', ...values});

  /// One finished trip and its samples, cut into lines of
  /// [Tdx.samplesPerLine] rows.
  void trip(Trip trip, List<TripSample> samples) {
    final json = TdxCodec.tripToJson(trip);
    _record('trip', json);
    final key = trip.startedAt.millisecondsSinceEpoch;
    for (var i = 0; i < samples.length; i += Tdx.samplesPerLine) {
      final end = i + Tdx.samplesPerLine < samples.length
          ? i + Tdx.samplesPerLine
          : samples.length;
      _record('samples', TdxCodec.samplesToJson(key, samples.sublist(i, end)));
    }
  }

  void fillUp(FillUp fillUp) =>
      _record('fillup', TdxCodec.fillUpToJson(fillUp));

  void rest(List<RestReading> readings) =>
      _record('rest', TdxCodec.restToJson(readings));

  /// The footer: the counts, and the checksum of everything before it.
  void finish() {
    _need();
    _finished = true;
    final crc = _crc.hex;
    _line(
      {'t': 'end', 'counts': _counts, 'crc32': crc},
      count: null,
      checksum: false,
    );
  }

  void _record(String type, Map<String, Object?> json) {
    _need();
    _line(json, count: type);
  }

  void _need() {
    if (!_started) throw StateError('Write the header first.');
    if (_finished) throw StateError('The file is finished.');
  }

  void _line(
    Map<String, Object?> json, {
    required String? count,
    bool checksum = true,
  }) {
    if (count != null) _counts.update(count, (n) => n + 1, ifAbsent: () => 1);
    final bytes = utf8.encode('${jsonEncode(json)}\n');
    if (checksum) _crc.add(bytes);
    _emit(bytes);
  }
}
