/// Which way a line of a session log went, or that it is not traffic at all.
enum SessionDirection {
  /// Sent by the app to the adapter.
  sent,

  /// Received from the adapter.
  received,

  /// The link changed state: `connecting`, `connected`, `disconnected`...
  event,

  /// A line the app wrote about itself, not traffic: its connection status, a
  /// trip starting or ending, the fuel figures once in a while. Replay ignores
  /// these; they are there for whoever reads the log.
  note,
}

/// One line of a session log.
class SessionEntry {
  const SessionEntry(this.at, this.direction, this.text);

  /// When it happened, from the start of the session, to the millisecond.
  final Duration at;
  final SessionDirection direction;

  /// The bytes as text, exactly as they went over the link, or for an event
  /// its description.
  final String text;

  @override
  bool operator ==(Object other) =>
      other is SessionEntry &&
      other.at == at &&
      other.direction == direction &&
      other.text == text;

  @override
  int get hashCode => Object.hash(at, direction, text);

  @override
  String toString() => 'SessionEntry($at ${direction.name} ${text.codeUnits})';
}

/// A recording of what passed between the app and an adapter, with the time of
/// each piece (CLAUDE.md 10, Recordings).
///
/// It is a text file, one line to an entry, so that it can be read, diffed and
/// kept in git:
///
/// ```
/// # tapedash-session v1
/// # scenario: city_stop_go
/// 1.000 > ATZ\r
/// 1.000 < ATZ\r
/// 1.800 < \r\rELM327 v1.5\r\n\r\n>
/// 2.010 ! disconnected lost
/// ```
///
/// The `#` lines at the top say what was recorded. Each entry is the time in
/// seconds, a marker (`>` sent, `<` received, `!` a link event, `@` a note the
/// app wrote about itself) and the text. The
/// text is escaped so that it stays on one line and can be read back exactly:
/// `\r`, `\n` and `\\` as written, any other character outside the printable
/// ASCII range as `\xHH` or `\uHHHH`. A trailing space is part of the text.
class SessionLog {
  const SessionLog({this.header = const {}, this.entries = const []});

  /// What was recorded, from the `#` lines: `scenario`, `profile`, `seed`...
  final Map<String, String> header;
  final List<SessionEntry> entries;

  static const String _magic = '# tapedash-session v1';

  /// The whole log as text.
  String format() {
    final out = StringBuffer('$_magic\n');
    for (final entry in header.entries) {
      out.write('# ${entry.key}: ${entry.value}\n');
    }
    for (final e in entries) {
      out
        ..write(_formatTime(e.at))
        ..write(switch (e.direction) {
          SessionDirection.sent => ' > ',
          SessionDirection.received => ' < ',
          SessionDirection.event => ' ! ',
          SessionDirection.note => ' @ ',
        })
        ..write(escape(e.text))
        ..write('\n');
    }
    return out.toString();
  }

  static String _formatTime(Duration at) {
    final ms = at.inMilliseconds;
    return '${ms ~/ 1000}.${(ms % 1000).toString().padLeft(3, '0')}';
  }

  /// Reads a log. Throws a [FormatException] that names the line if it is not
  /// one.
  static SessionLog parse(String content) {
    final lines = content.split('\n');
    // A file that has been through Windows line endings.
    String clean(String line) =>
        line.endsWith('\r') ? line.substring(0, line.length - 1) : line;

    if (clean(lines.first) != _magic) {
      throw const FormatException(
        'not a TapeDash session log: the first line should be "$_magic"',
      );
    }
    final header = <String, String>{};
    final entries = <SessionEntry>[];
    for (var i = 1; i < lines.length; i++) {
      final line = clean(lines[i]);
      if (line.isEmpty) continue;
      if (line.startsWith('#')) {
        // Only before the first entry do these say what was recorded.
        if (entries.isEmpty) {
          final colon = line.indexOf(':');
          if (colon > 1) {
            header[line.substring(1, colon).trim()] = line
                .substring(colon + 1)
                .trim();
          }
        }
        continue;
      }
      entries.add(_parseEntry(line, i + 1));
    }
    return SessionLog(header: header, entries: entries);
  }

  static SessionEntry _parseEntry(String line, int number) {
    FormatException bad(String why) =>
        FormatException('line $number: $why: $line');

    final match = RegExp(r'^(\d+)\.(\d{3}) ([><!@]) ?(.*)$').firstMatch(line);
    if (match == null) throw bad('expected "<seconds> <marker> <text>"');
    final at = Duration(
      milliseconds:
          int.parse(match.group(1)!) * 1000 + int.parse(match.group(2)!),
    );
    final direction = switch (match.group(3)!) {
      '>' => SessionDirection.sent,
      '<' => SessionDirection.received,
      '@' => SessionDirection.note,
      _ => SessionDirection.event,
    };
    try {
      return SessionEntry(at, direction, unescape(match.group(4)!));
    } on FormatException catch (e) {
      throw bad(e.message);
    }
  }

  /// [text] on one line, with what would break it written as an escape.
  static String escape(String text) {
    final out = StringBuffer();
    for (final unit in text.codeUnits) {
      switch (unit) {
        case 0x0D:
          out.write(r'\r');
        case 0x0A:
          out.write(r'\n');
        case 0x5C:
          out.write(r'\\');
        case >= 0x20 && <= 0x7E:
          out.writeCharCode(unit);
        case <= 0xFF:
          out.write(
            '\\x${unit.toRadixString(16).padLeft(2, '0').toUpperCase()}',
          );
        default:
          out.write(
            '\\u${unit.toRadixString(16).padLeft(4, '0').toUpperCase()}',
          );
      }
    }
    return out.toString();
  }

  /// The inverse of [escape].
  static String unescape(String text) {
    final out = StringBuffer();
    var i = 0;
    while (i < text.length) {
      final c = text[i];
      if (c != r'\') {
        out.write(c);
        i++;
        continue;
      }
      if (i + 1 >= text.length) {
        throw const FormatException('ends in a backslash');
      }
      final next = text[i + 1];
      switch (next) {
        case 'r':
          out.write('\r');
          i += 2;
        case 'n':
          out.write('\n');
          i += 2;
        case r'\':
          out.write(r'\');
          i += 2;
        case 'x':
          out.writeCharCode(_hex(text, i + 2, 2));
          i += 4;
        case 'u':
          out.writeCharCode(_hex(text, i + 2, 4));
          i += 6;
        default:
          throw FormatException(
            r'unknown escape \'
            '$next',
          );
      }
    }
    return out.toString();
  }

  static int _hex(String text, int start, int digits) {
    if (start + digits > text.length) {
      throw const FormatException('a hex escape is cut short');
    }
    final value = int.tryParse(
      text.substring(start, start + digits),
      radix: 16,
    );
    if (value == null) {
      throw const FormatException('bad hex digits in an escape');
    }
    return value;
  }
}
