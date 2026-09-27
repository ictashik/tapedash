/// Which system a fault code is about, from its letter.
enum DtcSystem {
  powertrain('P'),
  chassis('C'),
  body('B'),
  network('U');

  const DtcSystem(this.letter);
  final String letter;
}

/// A diagnostic trouble code such as `P0420` (SAE J2012).
class Dtc {
  const Dtc(this.code);

  /// Five characters: the letter, and four digits, the last three in hex.
  final String code;

  DtcSystem get system =>
      DtcSystem.values.firstWhere((s) => s.letter == code[0]);

  @override
  bool operator ==(Object other) => other is Dtc && other.code == code;

  @override
  int get hashCode => code.hashCode;

  @override
  String toString() => code;
}

/// Reads fault codes out of an ECU's answer to Mode 03 (stored) or Mode 07
/// (pending).
abstract final class DtcDecoder {
  static const String _letters = 'PCBU';

  /// The code in two bytes, or null for `00 00`, which is not a code but the
  /// padding of a message: a message is padded out to fill its frame.
  ///
  /// The first two bits are the letter, the next two the first digit, and the
  /// remaining twelve bits are three hex digits.
  static Dtc? decodePair(int high, int low) {
    if (high < 0 || high > 255 || low < 0 || low > 255) {
      throw ArgumentError('not bytes: $high, $low');
    }
    if (high == 0 && low == 0) return null;
    final letter = _letters[high >> 6];
    final digit = (high >> 4) & 0x3;
    final rest = (((high & 0xF) << 8) | low)
        .toRadixString(16)
        .toUpperCase()
        .padLeft(3, '0');
    return Dtc('$letter$digit$rest');
  }

  /// The codes in one ECU's [message], which starts with [reply]: 0x43 for
  /// Mode 03, 0x47 for Mode 07. On CAN a byte follows it that says how many
  /// codes there are; on other protocols the codes follow directly, three to a
  /// message.
  ///
  /// It is tolerant: padding is dropped, a count that is wrong is not believed
  /// (the bytes there are read), and a last byte with no partner is ignored.
  /// Null if [message] is not a reply of that mode.
  static List<Dtc>? decode(
    List<int> message, {
    required int reply,
    required bool isCan,
  }) {
    if (message.isEmpty || message.first != reply) return null;
    var bytes = message.sublist(1);
    if (isCan) {
      if (bytes.isEmpty) return const [];
      final count = bytes.first;
      bytes = bytes.sublist(1);
      // Believe the count only as far as the bytes go, and no further than
      // it says: some ECUs pad.
      if (count * 2 < bytes.length) bytes = bytes.sublist(0, count * 2);
    }
    final codes = <Dtc>[];
    for (var i = 0; i + 1 < bytes.length; i += 2) {
      final code = decodePair(bytes[i], bytes[i + 1]);
      if (code != null) codes.add(code);
    }
    return codes;
  }

  /// The codes in every ECU's message, each once, in the order found.
  static List<Dtc>? decodeAll(
    List<List<int>> messages, {
    required int reply,
    required bool isCan,
  }) {
    final out = <Dtc>[];
    var any = false;
    for (final message in messages) {
      final codes = decode(message, reply: reply, isCan: isCan);
      if (codes == null) continue;
      any = true;
      for (final code in codes) {
        if (!out.contains(code)) out.add(code);
      }
    }
    return any ? out : null;
  }
}
