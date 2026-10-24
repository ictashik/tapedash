// Reads, checks, merges and flattens exchange files on a computer (docs/EXCHANGE.md
// 5). It is the same code the app reads them with, run under plain `dart`:
//
//   dart run tool/tdx.dart info  from-device/*.tdx.gz        header, counts, dates
//   dart run tool/tdx.dart check from-device/*.tdx.gz        the checksum and every line
//   dart run tool/tdx.dart merge a.tdx b.tdx.gz -o all.tdx   trips and fill-ups by key
//   dart run tool/tdx.dart csv   all.tdx > trips.csv         one row a trip
//
// `check` exits 1 if a file is refused or has a line that cannot be used, and `info`
// exits 1 if a file is refused, so a script can tell.
import 'dart:async';
import 'dart:io';

import 'package:tapedash/exchange/tdx_format.dart';
import 'package:tapedash/exchange/tdx_reader.dart';
import 'package:tapedash/exchange/tdx_writer.dart';
import 'package:tapedash/insights/rest_voltage_log.dart';
import 'package:tapedash/money/fill_up.dart';
import 'package:tapedash/trips/trip.dart';

const String _usage = '''
Usage: dart run tool/tdx.dart <command> [options] <file>...

  info  <file>...             what is in each file
  check <file>...             verify each file; exit 1 if any cannot be used
  merge <file>... -o <out>    one file with every trip and fill-up; .gz compresses
  csv   <file>...             a spreadsheet of the trips, to standard output
''';

Future<int> main(List<String> args) async {
  if (args.isEmpty || args.first == '-h' || args.first == '--help') {
    stdout.write(_usage);
    return args.isEmpty ? 64 : 0;
  }
  final command = args.first;
  final rest = args.sublist(1);
  switch (command) {
    case 'info':
      return _each(rest, _info);
    case 'check':
      return _each(rest, _check);
    case 'merge':
      return _merge(rest);
    case 'csv':
      return _csv(rest);
    default:
      stderr.writeln('Unknown command "$command".\n$_usage');
      return 64;
  }
}

Stream<List<int>> _open(String path) => File(path).openRead();

Future<int> _each(
  List<String> paths,
  Future<int> Function(String path) one,
) async {
  if (paths.isEmpty) {
    stderr.write(_usage);
    return 64;
  }
  var worst = 0;
  for (final p in paths) {
    final code = await one(p);
    if (code > worst) worst = code;
  }
  return worst;
}

Future<int> _info(String path) async {
  stdout.writeln(path);
  try {
    final scan = await TdxReader.scan(_open(path));
    final h = scan.header!;
    stdout.writeln(
      '  made by TapeDash ${h.appVersion} on a ${h.device.kind}'
      '${h.device.name.isEmpty ? '' : ' (${h.device.name})'}'
      '${h.created == null ? '' : ', ${h.created!.toUtc().toIso8601String()}'}',
    );
    stdout.writeln(
      '  format version ${h.version}, scopes: '
      '${h.scopes.map((s) => s.name).join(', ')}',
    );
    stdout.writeln('  lines: ${scan.lines}');
    for (final e in scan.counts.entries) {
      stdout.writeln('  ${e.key}: ${e.value}');
    }
    if (scan.firstTrip != null) {
      stdout.writeln(
        '  trips from ${scan.firstTrip!.toUtc().toIso8601String()} '
        'to ${scan.lastTrip!.toUtc().toIso8601String()}',
      );
    }
    if (scan.rejected > 0 || scan.ignored > 0) {
      stdout.writeln(
        '  ${scan.rejected} line(s) cannot be used, ${scan.ignored} of a '
        'type this version does not know',
      );
    }
    return 0;
  } on TdxException catch (e) {
    stdout.writeln('  REFUSED: ${e.message}');
    return 1;
  } on FileSystemException catch (e) {
    stdout.writeln('  cannot read: ${e.message}');
    return 1;
  }
}

Future<int> _check(String path) async {
  try {
    final scan = await TdxReader.scan(_open(path));
    if (scan.rejected > 0) {
      stdout.writeln(
        '$path: complete, but ${scan.rejected} line(s) cannot be used',
      );
      for (final r in scan.rejections) {
        stdout.writeln('  $r');
      }
      return 1;
    }
    stdout.writeln('$path: ok (${scan.lines} lines)');
    return 0;
  } on TdxException catch (e) {
    stdout.writeln('$path: REFUSED: ${e.message}');
    return 1;
  } on FileSystemException catch (e) {
    stdout.writeln('$path: cannot read: ${e.message}');
    return 1;
  }
}

/// Everything usable in [paths], by key.
class _Collected {
  final Map<int, (Trip, List<TripSample>)> trips = {};
  final Map<String, FillUp> fills = {};
  final Map<int, RestReading> rest = {};
  Map<String, Object?>? profile;
  DateTime? profileFrom;
}

Future<_Collected?> _collect(List<String> paths) async {
  final all = _Collected();
  for (final path in paths) {
    try {
      await TdxReader.scan(_open(path));
      DateTime? made;
      TdxTripRecord? pending;
      final samples = <TripSample>[];
      void flush() {
        final p = pending;
        if (p == null) return;
        all.trips.putIfAbsent(p.key, () => (p.trip, [...samples]));
        pending = null;
        samples.clear();
      }

      await for (final r in TdxReader.records(_open(path))) {
        if (r is! TdxSamplesRecord) flush();
        switch (r) {
          case TdxHeaderRecord():
            made = r.created;
          case TdxTripRecord():
            if (!all.trips.containsKey(r.key)) pending = r;
          case TdxSamplesRecord():
            if (pending?.key == r.tripKey) samples.addAll(r.samples);
          case TdxFillUpRecord():
            all.fills.putIfAbsent(
              '${r.key}:${r.fillUp.litres.toStringAsFixed(3)}',
              () => r.fillUp,
            );
          case TdxRestRecord():
            for (final e in r.readings) {
              all.rest.putIfAbsent(e.at.millisecondsSinceEpoch, () => e);
            }
          case TdxProfileRecord():
            // The newest file's setup wins.
            if (all.profileFrom == null ||
                (made != null && made.isAfter(all.profileFrom!))) {
              all.profile = r.clean.values;
              all.profileFrom = made;
            }
          case TdxDeviceRecord() ||
              TdxEndRecord() ||
              TdxUnknownRecord() ||
              TdxRejectedRecord():
            break;
        }
      }
      flush();
    } on TdxException catch (e) {
      stderr.writeln('$path: REFUSED: ${e.message}');
      return null;
    } on FileSystemException catch (e) {
      stderr.writeln('$path: cannot read: ${e.message}');
      return null;
    }
  }
  return all;
}

Future<int> _merge(List<String> args) async {
  final out = args.indexOf('-o');
  if (out < 0 || out + 1 >= args.length) {
    stderr.writeln('merge needs -o <out>.\n$_usage');
    return 64;
  }
  final target = args[out + 1];
  final inputs = [
    for (var i = 0; i < args.length; i++)
      if (i != out && i != out + 1) args[i],
  ];
  if (inputs.isEmpty) {
    stderr.writeln('merge needs files to merge.\n$_usage');
    return 64;
  }
  final all = await _collect(inputs);
  if (all == null) return 1;

  final file = File(target);
  final sink = file.openWrite();
  final zip = target.endsWith('.gz')
      ? gzip.encoder.startChunkedConversion(_Sink(sink))
      : null;
  final writer = TdxWriter(zip?.add ?? sink.add)
    ..header(
      appVersion: 'tdx tool',
      created: DateTime.now().toUtc(),
      device: const TdxDeviceInfo(
        id: 'merge',
        kind: 'phone',
        name: 'tdx merge',
      ),
      scopes: {
        if (all.profile != null) TdxScope.profile,
        TdxScope.trips,
        TdxScope.fillups,
        TdxScope.rest,
      },
    );
  if (all.profile != null) writer.profile(all.profile!);
  final keys = all.trips.keys.toList()..sort();
  for (final k in keys) {
    final (trip, samples) = all.trips[k]!;
    writer.trip(trip, samples);
  }
  final fills = all.fills.values.toList()..sort((a, b) => a.at.compareTo(b.at));
  fills.forEach(writer.fillUp);
  if (all.rest.isNotEmpty) {
    writer.rest(all.rest.values.toList()..sort((a, b) => a.at.compareTo(b.at)));
  }
  writer.finish();
  zip?.close();
  await sink.close();
  stdout.writeln(
    '$target: ${all.trips.length} trips, ${all.fills.length} fill-ups, '
    '${all.rest.length} battery readings.',
  );
  return 0;
}

Future<int> _csv(List<String> paths) async {
  if (paths.isEmpty) {
    stderr.write(_usage);
    return 64;
  }
  final all = await _collect(paths);
  if (all == null) return 1;
  stdout.writeln(
    'started_utc,ended_utc,duration_s,distance_km,litres,cost,price_per_litre,'
    'km_per_litre,cost_per_km,idle_s,hard_accelerations,hard_brakings,'
    'long_idles,fuel_source,low_confidence',
  );
  final keys = all.trips.keys.toList()..sort();
  for (final k in keys) {
    final t = all.trips[k]!.$1;
    String n(num? v) => v == null ? '' : '$v';
    stdout.writeln(
      [
        t.startedAt.toUtc().toIso8601String(),
        t.endedAt?.toUtc().toIso8601String() ?? '',
        n(t.endedAt?.difference(t.startedAt).inSeconds),
        n(t.distanceKm),
        n(t.litres),
        n(t.cost),
        n(t.pricePerLitre),
        n(t.kmPerLitre),
        n(t.costPerKm),
        n(t.idleSeconds),
        n(t.hardAccelerations),
        n(t.hardBrakings),
        n(t.longIdles),
        t.fuelSource.label,
        t.lowConfidence,
      ].join(','),
    );
  }
  return 0;
}

class _Sink implements Sink<List<int>> {
  _Sink(this._sink);
  final IOSink _sink;

  @override
  void add(List<int> data) => _sink.add(data);

  @override
  void close() {}
}
