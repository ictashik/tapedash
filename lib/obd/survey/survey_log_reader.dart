import '../elm327/elm327_parser.dart';
import '../transport/session_log.dart';
import 'headed_reply.dart';
import 'mode01_lengths.dart';

/// One PID read from one ECU.
class SurveyRead {
  const SurveyRead({
    required this.at,
    required this.ecu,
    required this.pid,
    required this.data,
  });

  /// When the car was asked, taken as the middle of the round trip.
  final Duration at;

  /// The ECU's ID, or `ALL` where the log cannot say which of several
  /// answered.
  final String ecu;
  final int pid;
  final List<int> data;

  @override
  String toString() =>
      'SurveyRead($ecu ${pid.toRadixString(16)} $data at ${at.inMilliseconds} ms)';
}

/// What an adapter answered to a request that is not a Mode 01 PID, such as the
/// fault codes (03), test results (06) or calibration IDs (09).
class SurveyOtherReply {
  const SurveyOtherReply({
    required this.at,
    required this.command,
    required this.ecu,
    required this.payload,
    required this.complete,
  });

  final Duration at;

  /// What was sent, such as `0904`.
  final String command;
  final String ecu;
  final List<int> payload;
  final bool complete;
}

/// Something the user switched on or off during the survey (headlights, A/C...),
/// as they marked it on the screen.
class SurveyMark {
  const SurveyMark({required this.at, required this.id, required this.on});

  final Duration at;

  /// What it was: `headlights`, `blower`, `ac`, `defogger`, `wipers`,
  /// `steering`.
  final String id;
  final bool on;
}

/// A survey log, read back.
class SurveySummary {
  SurveySummary({
    required this.header,
    required this.length,
    required this.reads,
    required this.others,
    required this.commands,
    required this.notes,
    required this.supported,
    required this.adapterLines,
    required this.marks,
  });

  /// The `#` lines of the log.
  final Map<String, String> header;

  /// From the first entry to the last.
  final Duration length;

  /// Every PID read, in order.
  final List<SurveyRead> reads;

  /// The answers to the other modes.
  final List<SurveyOtherReply> others;

  /// Every command sent, in order.
  final List<String> commands;

  /// The app's own `survey` notes (the text after the marker), with their
  /// times.
  final List<(Duration, String)> notes;

  /// The PIDs each ECU said it has, from the survey's own notes.
  final Map<String, Set<int>> supported;

  /// What the adapter said to `ATI`, `AT@1` and `ATRV`, by command.
  final Map<String, String> adapterLines;

  /// What the user marked, in order.
  final List<SurveyMark> marks;

  /// The reads of [pid] from [ecu] (or from any ECU if it is null).
  List<SurveyRead> readsOf(int pid, {String? ecu}) => [
    for (final r in reads)
      if (r.pid == pid && (ecu == null || r.ecu == ecu)) r,
  ];

  /// The PIDs read, with how many times, for one ECU or all of them.
  Map<int, int> countByPid({String? ecu}) {
    final counts = <int, int>{};
    for (final r in reads) {
      if (ecu != null && r.ecu != ecu) continue;
      counts[r.pid] = (counts[r.pid] ?? 0) + 1;
    }
    return counts;
  }
}

/// Reads a survey log (the transport recording of a survey, with its notes) and
/// works out what each command asked for and what each ECU answered.
///
/// It follows the settings as the log shows them: whether headers were on
/// (`ATH1`/`ATH0`) and which ECU the adapter was listening to (`ATCRA`), so
/// each read is attributed to the ECU that gave it. Where it cannot tell (several
/// ECUs, headers off, no filter), the ECU is `ALL`.
abstract final class SurveyLogReader {
  static SurveySummary read(SessionLog log) {
    final reads = <SurveyRead>[];
    final others = <SurveyOtherReply>[];
    final commands = <String>[];
    final notes = <(Duration, String)>[];
    final supported = <String, Set<int>>{};
    final adapterLines = <String, String>{};
    final marks = <SurveyMark>[];

    var headersOn = false;
    String? filter;

    String? command;
    Duration sentAt = Duration.zero;
    Duration? dataAt;
    final buffer = StringBuffer();

    void flush(Duration doneAt) {
      final sent = command;
      command = null;
      if (sent == null) return;
      final raw = buffer.toString();
      buffer.clear();
      final parsed = Elm327Parser.parse(raw, sentCommand: sent);
      final at = dataAt == null
          ? sentAt
          : sentAt +
                Duration(microseconds: (dataAt - sentAt).inMicroseconds ~/ 2);

      final upper = sent.toUpperCase();
      if (upper.startsWith('AT')) {
        if (upper == 'ATH1') headersOn = parsed.failure == null;
        if (upper == 'ATH0') headersOn = false;
        if (upper.startsWith('ATCRA') && parsed.failure == null) {
          final id = upper.substring(5);
          filter = id.isEmpty ? null : id;
        }
        if (const {'ATI', 'AT@1', 'ATRV'}.contains(upper) &&
            parsed.lines.isNotEmpty) {
          adapterLines[upper] = parsed.lines.last;
        }
        return;
      }
      if (parsed.failure != null && parsed.lines.isEmpty) return;
      final request = _request(upper);
      if (request == null) return;

      final messages = headersOn
          ? HeadedReply.parse(parsed.lines).messages
          : [
              for (final bytes
                  in Elm327Parser.messages(parsed.lines) ?? const <List<int>>[])
                HeadedMessage(
                  id: filter ?? 'ALL',
                  payload: bytes,
                  complete: true,
                ),
            ];
      for (final m in messages) {
        if (request.mode == 0x01 &&
            m.payload.isNotEmpty &&
            m.payload.first == 0x41) {
          for (final (pid, data) in Mode01Lengths.walk(m.payload).values) {
            reads.add(SurveyRead(at: at, ecu: m.id, pid: pid, data: data));
          }
        } else {
          others.add(
            SurveyOtherReply(
              at: at,
              command: request.text,
              ecu: m.id,
              payload: m.payload,
              complete: m.complete,
            ),
          );
        }
      }
    }

    for (final e in log.entries) {
      switch (e.direction) {
        case SessionDirection.sent:
          // A new command ends whatever was waiting for its prompt.
          if (command != null) flush(e.at);
          final text = e.text.replaceAll('\r', '').trim();
          if (text.isEmpty) break;
          command = text;
          commands.add(text);
          sentAt = e.at;
          dataAt = null;
        case SessionDirection.received:
          if (command == null) break;
          buffer.write(e.text);
          dataAt ??= e.at;
          if (e.text.contains('>')) flush(e.at);
        case SessionDirection.event:
          if (command != null) {
            buffer.clear();
            command = null;
          }
          // The adapter forgets its settings when the link goes.
          headersOn = false;
          filter = null;
        case SessionDirection.note:
          final text = e.text;
          if (text.startsWith('survey ')) {
            notes.add((e.at, text.substring(7)));
            final mark = RegExp(
              r'^mark id=(\S+) state=(on|off)$',
            ).firstMatch(text.substring(7));
            if (mark != null) {
              marks.add(
                SurveyMark(
                  at: e.at,
                  id: mark.group(1)!,
                  on: mark.group(2) == 'on',
                ),
              );
            }
            final ecu = RegExp(
              r'^ecu id=(\S+) pids=(\S*)$',
            ).firstMatch(text.substring(7));
            if (ecu != null) {
              supported[ecu.group(1)!] = {
                for (final p in ecu.group(2)!.split(','))
                  if (p.isNotEmpty) int.parse(p, radix: 16),
              };
            }
          }
      }
    }
    if (command != null) {
      flush(log.entries.isEmpty ? Duration.zero : log.entries.last.at);
    }

    return SurveySummary(
      header: log.header,
      length: log.entries.isEmpty ? Duration.zero : log.entries.last.at,
      reads: reads,
      others: others,
      commands: commands,
      notes: notes,
      supported: supported,
      adapterLines: adapterLines,
      marks: marks,
    );
  }

  /// A request for data: its mode and the text. Null for anything else.
  static ({int mode, String text})? _request(String command) {
    if (!RegExp(r'^[0-9A-F]+$').hasMatch(command) || command.length < 2) {
      return null;
    }
    final mode = int.parse(command.substring(0, 2), radix: 16);
    if (mode < 1 || mode > 0x0A) return null;
    return (mode: mode, text: command);
  }
}
