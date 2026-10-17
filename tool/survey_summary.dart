// Reads a survey log (a survey drive's file from the phone, or one made by the
// simulator) and says what is in it: the ECUs and their PIDs, how often each PID
// was read and the range of what it said, the answers to the other modes, the
// marks, and what the survey decided on the way.
//
//   dart run tool/survey_summary.dart <log> [--csv <file>]
//
// With --csv, every PID read is written as a line of `t_s,ecu,pid,hex,value`
// (value only for the PIDs TapeDash knows the formula of), for a spreadsheet or
// a script. No formula is guessed for the others: the raw bytes are there.
import 'dart:io';

import 'package:tapedash/obd/pids/pid.dart';
import 'package:tapedash/obd/survey/survey_log_reader.dart';
import 'package:tapedash/obd/transport/session_log.dart';

/// The names of the standard Mode 01 PIDs (SAE J1979), for reading the tables.
/// Names only: what the bytes mean is for whoever reads the data, with the
/// standard to hand.
const Map<int, String> pidNames = {
  0x01: 'Monitor status since DTCs cleared',
  0x03: 'Fuel system status',
  0x04: 'Calculated engine load',
  0x05: 'Coolant temperature',
  0x06: 'Short-term fuel trim, bank 1',
  0x07: 'Long-term fuel trim, bank 1',
  0x0B: 'Intake manifold pressure',
  0x0C: 'Engine speed',
  0x0D: 'Vehicle speed',
  0x0E: 'Timing advance',
  0x0F: 'Intake air temperature',
  0x10: 'Mass air flow',
  0x11: 'Throttle position',
  0x13: 'Oxygen sensors present',
  0x15: 'Oxygen sensor 2 (voltage, trim)',
  0x1C: 'OBD standard',
  0x1F: 'Run time since engine start',
  0x21: 'Distance with MIL on',
  0x2C: 'Commanded EGR',
  0x2E: 'Commanded evaporative purge',
  0x2F: 'Fuel level',
  0x30: 'Warm-ups since codes cleared',
  0x31: 'Distance since codes cleared',
  0x33: 'Barometric pressure',
  0x34: 'Oxygen sensor 1 (wide range)',
  0x41: 'Monitor status this drive cycle',
  0x42: 'Control module voltage',
  0x43: 'Absolute load',
  0x44: 'Commanded equivalence ratio',
  0x45: 'Relative throttle position',
  0x46: 'Ambient air temperature',
  0x47: 'Absolute throttle position B',
  0x49: 'Accelerator pedal position D',
  0x4A: 'Accelerator pedal position E',
  0x4C: 'Commanded throttle actuator',
  0x4D: 'Time run with MIL on',
  0x4E: 'Time since codes cleared',
  0x51: 'Fuel type',
  0x52: 'Ethanol fuel percentage',
  0x5C: 'Engine oil temperature',
  0x5E: 'Engine fuel rate',
};

String _hex(int v, [int width = 2]) =>
    v.toRadixString(16).toUpperCase().padLeft(width, '0');

String _hexBytes(List<int> bytes) => bytes.map(_hex).join();

String _clock(Duration d) {
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.inMinutes)}:${two(d.inSeconds % 60)}';
}

/// The text report for [log]: the ECUs, the PIDs read, the other modes, the marks
/// and what the survey did. [name] is shown at the top.
String summarize(SessionLog log, {String name = ''}) {
  final s = SurveyLogReader.read(log);
  final out = StringBuffer();

  out.writeln('Survey log${name.isEmpty ? '' : ': $name'}');
  for (final e in s.header.entries) {
    out.writeln('  ${e.key}: ${e.value}');
  }
  out.writeln(
    'Length ${_clock(s.length)}, ${s.commands.length} commands, '
    '${s.reads.length} PID readings',
  );
  if (s.header['survey'] != '1') {
    out.writeln(
      '  (this is not marked as a survey: it may be a dashboard '
      'recording; the tables below still apply)',
    );
  }
  out.writeln();

  if (s.adapterLines.isNotEmpty) {
    out.writeln('Adapter');
    for (final e in s.adapterLines.entries) {
      out.writeln('  ${e.key}: ${e.value}');
    }
    out.writeln();
  }

  out.writeln('ECUs');
  if (s.supported.isEmpty) out.writeln('  none found');
  for (final e in s.supported.entries) {
    final pids = e.value.where((p) => p % 0x20 != 0).toList()..sort();
    out.writeln('  ${e.key}: ${pids.length} PIDs: ${pids.map(_hex).join(' ')}');
  }
  out.writeln();

  // (The adapter's own start-up reads, before the survey tells the ECUs apart,
  // are under ALL and are only the masks of which PIDs exist.)
  final ecus = {
    for (final r in s.reads)
      if (r.pid % 0x20 != 0) r.ecu,
  }.toList()..sort();
  for (final ecu in ecus) {
    out.writeln('PIDs read from $ecu');
    out.writeln(
      '  PID  name                                   reads   per s  '
      'range (decoded, or raw bytes)',
    );
    final byPid = <int, List<SurveyRead>>{};
    for (final r in s.reads) {
      if (r.ecu == ecu && r.pid % 0x20 != 0) (byPid[r.pid] ??= []).add(r);
    }
    final seconds = s.length.inMilliseconds / 1000;
    for (final pid in byPid.keys.toList()..sort()) {
      final reads = byPid[pid]!;
      final known = Pids.byId(pid);
      final decoded = known == null
          ? null
          : [
              for (final r in reads)
                if (r.data.length == known.length) known.decode(r.data),
            ];
      final span = decoded != null && decoded.isNotEmpty
          ? '${decoded.reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}'
                ' .. ${decoded.reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}'
                ' (${known!.name})'
          : '${_hexBytes(reads.first.data)} .. ${_hexBytes(reads.last.data)}';
      out.writeln(
        '  ${_hex(pid)}   ${(pidNames[pid] ?? '?').padRight(36)} '
        '${reads.length.toString().padLeft(6)} '
        '${(reads.length / (seconds == 0 ? 1 : seconds)).toStringAsFixed(2).padLeft(6)}  '
        '$span',
      );
    }
    out.writeln();
  }

  if (s.others.isNotEmpty) {
    out.writeln('Other modes');
    final seen = <String>{};
    for (final o in s.others) {
      final key = '${o.ecu} ${o.command} ${_hexBytes(o.payload)}';
      if (!seen.add(key)) continue;
      // Only the calibration ID (04) and the ECU name (0A) are text.
      final isText =
          o.command.startsWith('0904') || o.command.startsWith('090A');
      final ascii =
          isText &&
              o.payload.length > 3 &&
              o.payload.skip(3).every((b) => b == 0 || (b >= 32 && b < 127))
          ? '  "${String.fromCharCodes(o.payload.skip(3).where((b) => b != 0))}"'
          : '';
      out.writeln(
        '  ${o.ecu}  ${o.command.padRight(6)} '
        '${_hexBytes(o.payload)}${o.complete ? '' : '  (cut short)'}$ascii',
      );
    }
    out.writeln();
  }

  if (s.marks.isNotEmpty) {
    out.writeln('Marks');
    for (final m in s.marks) {
      out.writeln(
        '  ${_clock(m.at)}  ${m.id} ${m.on ? 'on' : 'off'}'
        '${m.pass == null ? '' : '  (checks run ${m.pass})'}',
      );
    }
    out.writeln();
  }

  final decisions = [
    for (final n in s.notes)
      if (!n.$2.startsWith('vitals') &&
          !n.$2.startsWith('ecu ') &&
          !n.$2.startsWith('mark '))
        n,
  ];
  if (decisions.isNotEmpty) {
    out.writeln('What the survey did');
    for (final (at, text) in decisions) {
      out.writeln('  ${_clock(at)}  $text');
    }
  }
  return out.toString();
}

/// Every PID read as a line of `t_s,ecu,pid,hex,value`; the value only for the
/// PIDs TapeDash knows the formula of.
String csvOf(SessionLog log) {
  final s = SurveyLogReader.read(log);
  final out = StringBuffer('t_s,ecu,pid,hex,value\n');
  for (final r in s.reads) {
    final known = Pids.byId(r.pid);
    final value = known != null && known.length == r.data.length
        ? known.decode(r.data).toString()
        : '';
    out.writeln(
      '${(r.at.inMilliseconds / 1000).toStringAsFixed(3)},${r.ecu},'
      '${_hex(r.pid)},${_hexBytes(r.data)},$value',
    );
  }
  return out.toString();
}

void main(List<String> args) {
  String? path;
  String? csv;
  for (var i = 0; i < args.length; i++) {
    if (args[i] == '--csv' && i + 1 < args.length) {
      csv = args[++i];
    } else if (args[i] == '--help' || args[i] == '-h') {
      stdout.writeln(
        'usage: dart run tool/survey_summary.dart <log> [--csv <file>]',
      );
      return;
    } else {
      path = args[i];
    }
  }
  if (path == null) {
    stderr.writeln(
      'usage: dart run tool/survey_summary.dart <log> [--csv <file>]',
    );
    exitCode = 64;
    return;
  }
  final file = File(path);
  if (!file.existsSync()) {
    stderr.writeln('no such file: $path');
    exitCode = 66;
    return;
  }
  final SessionLog log;
  try {
    log = SessionLog.parse(file.readAsStringSync());
  } on FormatException catch (e) {
    stderr.writeln('not a session log: ${e.message}');
    exitCode = 65;
    return;
  }
  stdout.write(summarize(log, name: file.uri.pathSegments.last));
  if (csv != null) {
    File(csv).writeAsStringSync(csvOf(log));
    stdout.writeln('\nWrote the PID readings to $csv');
  }
}
