import 'elm327_failure.dart';

/// The text an adapter sent for one command, taken apart: what is left when the
/// echo, the `SEARCHING...` notice and the prompt are removed, and whether it
/// was an error.
class ParsedReply {
  const ParsedReply({
    required this.lines,
    this.searched = false,
    this.failure,
    this.failureLine,
  });

  /// The lines of content, trimmed, with no empty ones.
  final List<String> lines;

  /// Whether the adapter said `SEARCHING...`, which is to say that it looked
  /// for a protocol and this reply is the first since it did.
  final bool searched;

  /// Set if the adapter reported an error instead of, or as well as, data.
  final Elm327Failure? failure;

  /// The line that was the error.
  final String? failureLine;

  bool get isEmpty => lines.isEmpty && failure == null;

  @override
  String toString() =>
      'ParsedReply($lines${searched ? ', searched' : ''}'
      '${failure == null ? '' : ', $failure'})';
}

/// Reads the text of an ELM327 adapter (CLAUDE.md 8.1).
///
/// It is tolerant of what adapters do differently: echo on or off, `\r` or
/// `\r\n`, spaces between bytes or none, a space after the last byte or not.
/// It is not tolerant of noise: a line that should be hex and is not is
/// reported as unreadable, and never guessed at.
abstract final class Elm327Parser {
  /// Takes [raw], everything received from the command's echo to its prompt,
  /// apart. [sentCommand] is what was sent, so that its echo can be dropped.
  static ParsedReply parse(String raw, {String? sentCommand}) {
    // The datasheet says to ignore NULs, which some chips insert.
    final text = raw.replaceAll('\x00', '');
    final lines = <String>[];
    for (final line in text.split(RegExp(r'[\r\n]'))) {
      final trimmed = _clean(line);
      if (trimmed.isNotEmpty) lines.add(trimmed);
    }
    // The prompt ends the reply, on a line of its own or at the end of one.
    if (lines.isNotEmpty && lines.last.endsWith('>')) {
      final last = _clean(lines.last.substring(0, lines.last.length - 1));
      lines.removeLast();
      if (last.isNotEmpty) lines.add(last);
    }

    // With echo on, the first line is the command as it was typed.
    if (sentCommand != null && lines.isNotEmpty) {
      if (_compact(lines.first) == _compact(sentCommand)) lines.removeAt(0);
    }

    var searched = false;
    Elm327Failure? failure;
    String? failureLine;
    final content = <String>[];
    for (final line in lines) {
      final upper = line.toUpperCase();
      if (upper.startsWith('SEARCHING')) {
        searched = true;
        continue;
      }
      // A K-line protocol saying that it started: not an error, not data.
      if (upper.startsWith('BUS INIT') && upper.endsWith('OK')) continue;
      final error = classify(line);
      if (error != null) {
        failure ??= error;
        failureLine ??= line;
        continue;
      }
      content.add(line);
    }
    return ParsedReply(
      lines: content,
      searched: searched,
      failure: failure,
      failureLine: failureLine,
    );
  }

  /// The failure that an adapter's [line] reports, or null if it is not an
  /// error message.
  static Elm327Failure? classify(String line) {
    final text = line.trim().toUpperCase().replaceAll(RegExp(r'\s+'), ' ');
    switch (text) {
      case '?':
        return Elm327Failure.unknownCommand;
      case 'NO DATA':
        return Elm327Failure.noData;
      case 'STOPPED':
        return Elm327Failure.stopped;
      case 'CAN ERROR':
        return Elm327Failure.canError;
      case 'UNABLE TO CONNECT':
        return Elm327Failure.unableToConnect;
      case 'BUFFER FULL':
        return Elm327Failure.bufferFull;
      case 'BUS BUSY':
        return Elm327Failure.busBusy;
      case 'BUS ERROR':
        return Elm327Failure.busError;
      case 'DATA ERROR':
      case '<DATA ERROR':
        return Elm327Failure.dataError;
      case '<RX ERROR':
        return Elm327Failure.rxError;
      case 'FB ERROR':
        return Elm327Failure.feedbackError;
      case 'LV RESET':
        return Elm327Failure.lowVoltageReset;
    }
    if (text.startsWith('BUS INIT') && text.contains('ERROR')) {
      return Elm327Failure.busInitError;
    }
    if (RegExp(r'^ERR\d\d$').hasMatch(text)) return Elm327Failure.internalError;
    return null;
  }

  /// The ECUs' messages in a reply's content [lines], as bytes.
  ///
  /// A message is one line of hex, or, when it was too long for one CAN frame,
  /// a line with its length in three hex digits followed by numbered lines
  /// (`00A`, `0: 41 04 3F 05 44 0B`, `1: 21 0C 17 B8 00 00 00`). The bytes are
  /// cut to the length, which drops the padding of the last line. Several
  /// ECUs answering give several messages, in order.
  ///
  /// Null if anything is not hex, or a message is incomplete: noise is never
  /// guessed at.
  static List<List<int>>? messages(List<String> lines) {
    final out = <List<int>>[];
    var i = 0;
    while (i < lines.length) {
      final compact = _compact(lines[i]);
      final isCount =
          compact.length == 3 &&
          _isHex(compact) &&
          i + 1 < lines.length &&
          _numbered.hasMatch(_compact(lines[i + 1]));
      if (isCount) {
        final total = int.parse(compact, radix: 16);
        final numbered = <String>[];
        var j = i + 1;
        while (j < lines.length && _numbered.hasMatch(_compact(lines[j]))) {
          numbered.add(_compact(lines[j]));
          j++;
        }
        final bytes = _assemble(numbered);
        if (bytes == null || bytes.length < total) return null;
        out.add(bytes.sublist(0, total));
        i = j;
      } else if (_isHex(compact) && compact.length.isEven) {
        out.add(_bytes(compact));
        i++;
      } else {
        return null;
      }
    }
    return out;
  }

  static final RegExp _numbered = RegExp(r'^[0-9A-F]:[0-9A-F]*$');

  /// The bytes of a multi-frame message's numbered lines, or null if the
  /// numbers do not run in order from 0. The first frame carries six bytes and
  /// each one after it seven, but the lines are taken as they come; the
  /// length cuts off the padding.
  static List<int>? _assemble(List<String> numbered) {
    final byNumber = <int, String>{};
    final order = <int>[];
    for (final line in numbered) {
      final n = int.parse(line[0], radix: 16);
      final data = line.substring(2);
      if (data.length.isOdd || (data.isNotEmpty && !_isHex(data))) return null;
      order.add(n);
      byNumber[n] = data;
    }
    // In order, counting 0 to F and round again.
    var inOrder = true;
    for (var k = 0; k < order.length; k++) {
      if (order[k] != k % 16) inOrder = false;
    }
    final List<String> sequence;
    if (inOrder) {
      sequence = [for (final line in numbered) line.substring(2)];
    } else if (order.length <= 16 &&
        byNumber.length == order.length &&
        List.generate(order.length, (k) => k).every(byNumber.containsKey)) {
      // Out of order but complete, as the datasheet says can happen.
      sequence = [for (var k = 0; k < order.length; k++) byNumber[k]!];
    } else {
      return null;
    }
    return _bytes(sequence.join());
  }

  static List<int> _bytes(String hex) => [
    for (var i = 0; i < hex.length; i += 2)
      int.parse(hex.substring(i, i + 2), radix: 16),
  ];

  static bool _isHex(String s) =>
      s.isNotEmpty && RegExp(r'^[0-9A-F]+$').hasMatch(s);

  /// Spaces, tabs and the like removed, and upper case: how a command or a
  /// line of hex is compared.
  static String _compact(String s) =>
      s.replaceAll(RegExp(r'\s+'), '').toUpperCase();

  /// Leading and trailing white space removed.
  static String _clean(String s) => s.replaceAll(RegExp(r'^\s+|\s+$'), '');
}
