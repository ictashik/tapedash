import 'dart:async';
import 'dart:convert';
import 'dart:io' show gzip;

import '../insights/rest_voltage_log.dart' show RestReading;
import '../money/fill_up.dart';
import '../trips/trip.dart';
import 'crc32.dart';
import 'tdx_codec.dart';
import 'tdx_format.dart';
import 'tdx_profile.dart';

/// A line of an exchange file, read (docs/EXCHANGE.md 2).
sealed class TdxRecord {
  const TdxRecord(this.line);

  /// Its line in the file, counting from 1.
  final int line;
}

/// The header.
final class TdxHeaderRecord extends TdxRecord {
  const TdxHeaderRecord(
    super.line, {
    required this.version,
    required this.appVersion,
    required this.created,
    required this.device,
    required this.scopes,
  });

  final int version;
  final String appVersion;
  final DateTime? created;
  final TdxDeviceInfo device;
  final Set<TdxScope> scopes;
}

/// The portable setup, cleaned: only what was valid, and why the rest was not.
final class TdxProfileRecord extends TdxRecord {
  const TdxProfileRecord(super.line, this.clean);
  final CleanProfile clean;
}

/// The settings of one screen, cleaned.
final class TdxDeviceRecord extends TdxRecord {
  const TdxDeviceRecord(super.line, this.clean);
  final CleanProfile clean;
}

/// A finished trip. Its samples follow in `samples` lines.
final class TdxTripRecord extends TdxRecord {
  const TdxTripRecord(super.line, this.key, this.trip);

  /// What the trip is called in the file: its start time, in milliseconds.
  final int key;
  final Trip trip;
}

/// Some of a trip's samples.
final class TdxSamplesRecord extends TdxRecord {
  const TdxSamplesRecord(super.line, this.tripKey, this.samples, this.dropped);

  final int tripKey;
  final List<TripSample> samples;

  /// Rows that were not usable.
  final int dropped;
}

final class TdxFillUpRecord extends TdxRecord {
  const TdxFillUpRecord(super.line, this.key, this.fillUp);
  final int key;
  final FillUp fillUp;
}

final class TdxRestRecord extends TdxRecord {
  const TdxRestRecord(super.line, this.readings);
  final List<RestReading> readings;
}

/// The footer, checked.
final class TdxEndRecord extends TdxRecord {
  const TdxEndRecord(super.line, this.counts, this.crc);
  final Map<String, int> counts;

  /// The checksum the footer says everything before it has.
  final String? crc;
}

/// A line of a type this reader does not know: left alone, and counted.
final class TdxUnknownRecord extends TdxRecord {
  const TdxUnknownRecord(super.line, this.type);
  final String type;
}

/// A line of a known type that cannot be used, with the plain reason.
final class TdxRejectedRecord extends TdxRecord {
  const TdxRejectedRecord(super.line, this.type, this.reason);
  final String type;
  final String reason;
}

/// Why a file cannot be used at all, in a sentence a person can read.
class TdxException implements Exception {
  const TdxException(this.message);
  final String message;

  @override
  String toString() => message;
}

/// What a first pass over a file found, without applying any of it.
class TdxScan {
  TdxScan();

  TdxHeaderRecord? header;
  final Map<String, int> counts = {};
  int rejected = 0;
  final List<String> rejections = [];
  int ignored = 0;
  int droppedRows = 0;
  int lines = 0;

  /// The profile's own problems, in order.
  final List<String> profileProblems = [];

  /// The earliest and latest trip, for a report.
  DateTime? firstTrip;
  DateTime? lastTrip;
}

/// Reads an exchange file (docs/EXCHANGE.md 2), a line at a time and twice: [scan]
/// checks all of it, and [records] hands over what is in it to be applied. The
/// whole file is checked before any of it is used, so one that was cut short or
/// damaged on its way is refused whole.
abstract final class TdxReader {
  /// How many reasons for rejected lines a [TdxScan] keeps.
  static const int keepReasons = 5;

  /// Checks every byte and every line of the file in [raw].
  ///
  /// Throws [TdxException] with a plain sentence if the file cannot be used.
  static Future<TdxScan> scan(Stream<List<int>> raw) async {
    final scan = TdxScan();
    await for (final r in records(raw)) {
      scan.lines = r.line;
      switch (r) {
        case TdxHeaderRecord():
          scan.header = r;
        case TdxProfileRecord():
          scan.counts.update('profile', (n) => n + 1, ifAbsent: () => 1);
          scan.profileProblems.addAll(r.clean.problems);
        case TdxDeviceRecord():
          scan.counts.update('device', (n) => n + 1, ifAbsent: () => 1);
          scan.profileProblems.addAll(r.clean.problems);
        case TdxTripRecord():
          scan.counts.update('trip', (n) => n + 1, ifAbsent: () => 1);
          final at = r.trip.startedAt;
          if (scan.firstTrip == null || at.isBefore(scan.firstTrip!)) {
            scan.firstTrip = at;
          }
          if (scan.lastTrip == null || at.isAfter(scan.lastTrip!)) {
            scan.lastTrip = at;
          }
        case TdxSamplesRecord():
          scan.counts.update('samples', (n) => n + 1, ifAbsent: () => 1);
          scan.droppedRows += r.dropped;
        case TdxFillUpRecord():
          scan.counts.update('fillup', (n) => n + 1, ifAbsent: () => 1);
        case TdxRestRecord():
          scan.counts.update('rest', (n) => n + 1, ifAbsent: () => 1);
        case TdxEndRecord():
          break;
        case TdxUnknownRecord():
          scan.ignored++;
        case TdxRejectedRecord():
          scan.rejected++;
          if (scan.rejections.length < keepReasons) {
            scan.rejections.add('line ${r.line}: ${r.reason}');
          }
      }
    }
    return scan;
  }

  /// The records of the file in [raw], in order, ending with the footer. It checks
  /// the footer as it reaches it, and throws [TdxException] if the file is not
  /// whole, so use [scan] first and apply only what a clean scan found.
  static Stream<TdxRecord> records(Stream<List<int>> raw) async* {
    final crc = Crc32();
    final seen = <String, int>{};
    var line = 0;
    var ended = false;
    var expanded = 0;
    final buffer = <int>[];

    await for (final chunk in _decode(raw)) {
      expanded += chunk.length;
      if (expanded > Tdx.maxExpandedBytes) {
        throw const TdxException('This file is too large to read.');
      }
      for (final byte in chunk) {
        if (byte != 0x0A) {
          // The first line is JSON, so it starts with a brace: anything else is
          // known not to be ours at the first byte, not after a megabyte.
          if (line == 0 && buffer.isEmpty && byte != 0x7B) {
            throw const TdxException('This is not a TapeDash exchange file.');
          }
          buffer.add(byte);
          if (buffer.length > Tdx.maxLineBytes) {
            throw const TdxException(
              'This file has a line that is far too long to be one of ours.',
            );
          }
          continue;
        }
        line++;
        final bytes = List<int>.of(buffer);
        buffer.clear();
        if (ended) {
          if (bytes.every((b) => b == 0x20 || b == 0x0D)) continue;
          throw const TdxException('There is more after the end of this file.');
        }
        final record = _parse(bytes, line, first: line == 1, seen: seen);
        if (record is TdxEndRecord) {
          ended = true;
          if (record.crc == null || record.crc != crc.hex) {
            throw const TdxException(
              'This file was damaged on its way: its checksum does not match.',
            );
          }
          for (final type in const [
            'profile',
            'device',
            'trip',
            'samples',
            'fillup',
            'rest',
          ]) {
            final said = record.counts[type] ?? 0;
            final had = seen[type] ?? 0;
            if (said != had) {
              throw TdxException(
                'This file is not complete: it says it holds $said $type '
                'line${said == 1 ? '' : 's'} and holds $had.',
              );
            }
          }
          yield record;
          continue;
        }
        // Every line before the footer is part of the checksum, newline too.
        crc
          ..add(bytes)
          ..add(const [0x0A]);
        yield record;
      }
    }
    if (buffer.isNotEmpty && !ended) {
      // A last line with no newline cannot be the footer, which always has one.
      throw const TdxException(
        'This file is not complete: it ends before its last line.',
      );
    }
    if (!ended) {
      if (line == 0) throw const TdxException('This file is empty.');
      throw const TdxException(
        'This file is not complete: it ends before its last line.',
      );
    }
  }

  static TdxRecord _parse(
    List<int> bytes,
    int line, {
    required bool first,
    required Map<String, int> seen,
  }) {
    Object? json;
    try {
      json = jsonDecode(utf8.decode(bytes));
    } on FormatException {
      if (first) {
        throw const TdxException('This is not a TapeDash exchange file.');
      }
      return TdxRejectedRecord(line, '?', 'it is not JSON');
    }
    if (json is! Map) {
      if (first) {
        throw const TdxException('This is not a TapeDash exchange file.');
      }
      return TdxRejectedRecord(line, '?', 'it is not an object');
    }
    final j = Map<String, Object?>.from(json);
    final type = j['t'];
    if (first) {
      if (type != 'tdx') {
        throw const TdxException('This is not a TapeDash exchange file.');
      }
      final version = j['v'];
      if (version is! int || version < 1) {
        throw const TdxException('This is not a TapeDash exchange file.');
      }
      if (version > Tdx.version) {
        throw TdxException(
          'This file was made by a newer TapeDash (its format is version '
          '$version, this one reads up to ${Tdx.version}). Update the app to '
          'read it.',
        );
      }
      final ms = j['createdMs'];
      return TdxHeaderRecord(
        line,
        version: version,
        appVersion: j['appVersion'] is String ? j['appVersion'] as String : '',
        created: ms is int ? DateTime.fromMillisecondsSinceEpoch(ms) : null,
        device: TdxDeviceInfo.fromJson(j['device']),
        scopes: {
          if (j['scopes'] is List)
            for (final s in j['scopes'] as List)
              if (s is String && TdxScope.named(s) != null) TdxScope.named(s)!,
        },
      );
    }
    if (type is! String) return TdxRejectedRecord(line, '?', 'it has no type');
    if (type == 'tdx') {
      return TdxRejectedRecord(line, type, 'a second header');
    }
    void count() => seen.update(type, (n) => n + 1, ifAbsent: () => 1);
    switch (type) {
      case 'end':
        final counts = <String, int>{};
        final c = j['counts'];
        if (c is Map) {
          for (final e in c.entries) {
            if (e.key is String && e.value is int) {
              counts[e.key as String] = e.value as int;
            }
          }
        }
        return TdxEndRecord(
          line,
          counts,
          j['crc32'] is String ? j['crc32'] as String : null,
        );
      case 'profile':
        count();
        return TdxProfileRecord(line, TdxProfile.cleanProfile(j));
      case 'device':
        count();
        return TdxDeviceRecord(line, TdxProfile.cleanDevice(j));
      case 'trip':
        count();
        final parsed = TdxCodec.tripFromJson(j);
        if (!parsed.isOk) return TdxRejectedRecord(line, type, parsed.problem!);
        final trip = parsed.value!;
        return TdxTripRecord(line, trip.startedAt.millisecondsSinceEpoch, trip);
      case 'samples':
        count();
        final key = j['trip'];
        if (key is! int) {
          return TdxRejectedRecord(line, type, 'it names no trip');
        }
        final parsed = TdxCodec.samplesFromJson(j);
        if (!parsed.isOk) return TdxRejectedRecord(line, type, parsed.problem!);
        return TdxSamplesRecord(
          line,
          key,
          parsed.value!.samples,
          parsed.value!.dropped,
        );
      case 'fillup':
        count();
        final parsed = TdxCodec.fillUpFromJson(j);
        if (!parsed.isOk) return TdxRejectedRecord(line, type, parsed.problem!);
        return TdxFillUpRecord(
          line,
          parsed.value!.at.millisecondsSinceEpoch,
          parsed.value!,
        );
      case 'rest':
        count();
        final parsed = TdxCodec.restFromJson(j);
        if (!parsed.isOk) return TdxRejectedRecord(line, type, parsed.problem!);
        return TdxRestRecord(line, parsed.value!);
      default:
        return TdxUnknownRecord(line, type);
    }
  }

  /// The bytes of [raw], gunzipped if they start with the gzip magic.
  static Stream<List<int>> _decode(Stream<List<int>> raw) async* {
    final it = StreamIterator(raw);
    final head = <int>[];
    final held = <List<int>>[];
    var ended = false;
    while (head.length < 2) {
      if (!await it.moveNext()) {
        ended = true;
        break;
      }
      held.add(it.current);
      head.addAll(it.current);
    }
    final isGzip = head.length >= 2 && head[0] == 0x1F && head[1] == 0x8B;
    if (!isGzip) {
      for (final c in held) {
        yield c;
      }
      if (!ended) {
        while (await it.moveNext()) {
          yield it.current;
        }
      }
      return;
    }
    final out = _Collect();
    final conv = gzip.decoder.startChunkedConversion(out);
    try {
      for (final c in held) {
        conv.add(c);
        for (final o in out.take()) {
          yield o;
        }
      }
      if (!ended) {
        while (await it.moveNext()) {
          conv.add(it.current);
          for (final o in out.take()) {
            yield o;
          }
        }
      }
      conv.close();
    } on FormatException {
      throw const TdxException(
        'This file is not complete: its compression ends too soon.',
      );
    } on Exception catch (_) {
      throw const TdxException('This file cannot be decompressed.');
    }
    for (final o in out.take()) {
      yield o;
    }
  }
}

class _Collect implements Sink<List<int>> {
  final List<List<int>> _chunks = [];

  @override
  void add(List<int> data) => _chunks.add(data);

  @override
  void close() {}

  List<List<int>> take() {
    final out = List<List<int>>.of(_chunks);
    _chunks.clear();
    return out;
  }
}
