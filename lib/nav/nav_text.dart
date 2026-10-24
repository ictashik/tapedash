/// Reading figures out of the text Google Maps writes (docs/NAV.md).
///
/// Google writes in the phone's language and units, with a no-break space
/// between a number and its unit (`650 m`, `6.7 km`) and a middle dot between
/// the parts. Only what has been seen is read here. Anything else comes back
/// null, and the caller shows Google's own words instead of a guessed figure
/// (CLAUDE.md 1.6).
class NavText {
  const NavText._();

  /// The separators between the parts of one line: a middle dot, a bullet and a
  /// bar, with the spaces round them.
  static final _partSeparator = RegExp(r'\s*[·•|]\s*');

  /// Splits a line at its separators: `28 min · 6.7 km · 9:25 PM ETA` is three
  /// parts.
  static List<String> parts(String text) => text
      .split(_partSeparator)
      .map((p) => p.trim())
      .where((p) => p.isNotEmpty)
      .toList();

  /// [text] with its digits in any script turned into 0 to 9, and its
  /// no-break spaces into spaces, so that the rest of the reading sees one
  /// alphabet.
  static String plain(String text) {
    final out = StringBuffer();
    for (final unit in text.runes) {
      out.writeCharCode(_digit(unit) ?? (_isSpace(unit) ? 0x20 : unit));
    }
    return out.toString();
  }

  static bool _isSpace(int c) =>
      c == 0xA0 || c == 0x202F || c == 0x2009 || c == 0x200A || c == 0x2007;

  // The first digit (zero) of each block of ten that Unicode defines for a
  // script a phone in India or the Gulf may write in.
  static const _zeros = [
    0x0660, // Arabic-Indic
    0x06F0, // Extended Arabic-Indic
    0x0966, // Devanagari
    0x09E6, // Bengali
    0x0A66, // Gurmukhi
    0x0AE6, // Gujarati
    0x0B66, // Odia
    0x0BE6, // Tamil
    0x0C66, // Telugu
    0x0CE6, // Kannada
    0x0D66, // Malayalam
    0xFF10, // Fullwidth
  ];

  static int? _digit(int c) {
    for (final zero in _zeros) {
      if (c >= zero && c < zero + 10) return 0x30 + (c - zero);
    }
    return null;
  }

  /// The units of distance this reads, in metres. These are the ones seen in a
  /// capture of an English phone, and the ones a phone in the miles-and-feet
  /// regions writes; other languages' units are not guessed (docs/NAV.md). Add a
  /// unit here when a capture shows it.
  static const distanceUnits = <String, double>{
    'm': 1,
    'meter': 1,
    'meters': 1,
    'metre': 1,
    'metres': 1,
    'km': 1000,
    'kilometer': 1000,
    'kilometers': 1000,
    'kilometre': 1000,
    'kilometres': 1000,
    'mi': 1609.344,
    'mile': 1609.344,
    'miles': 1609.344,
    'ft': 0.3048,
    'foot': 0.3048,
    'feet': 0.3048,
    'yd': 0.9144,
    'yard': 0.9144,
    'yards': 0.9144,
  };

  static final _distance = RegExp(
    r'^([0-9]+(?:[.,][0-9]+)*)\s*([^\s0-9.,]+)\.?$',
  );

  /// `650 m`, `6.7 km`, `0.3 mi`, `1,2 km`, `500 ft`, in metres; null when
  /// [text] is not exactly a number and a known unit.
  static double? distanceMetres(String text, {Map<String, double>? units}) {
    final match = _distance.firstMatch(plain(text).trim());
    if (match == null) return null;
    final factor = (units ?? distanceUnits)[match.group(2)!.toLowerCase()];
    final number = _number(match.group(1)!);
    if (factor == null || number == null) return null;
    return number * factor;
  }

  /// A number written with a decimal point or comma, and perhaps grouping.
  static double? _number(String s) {
    final lastDot = s.lastIndexOf('.');
    final lastComma = s.lastIndexOf(',');
    final decimalAt = lastDot > lastComma ? lastDot : lastComma;
    final String whole;
    final String fraction;
    if (decimalAt < 0) {
      whole = s;
      fraction = '';
    } else {
      final after = s.substring(decimalAt + 1);
      final onlyOneKind = lastDot < 0 || lastComma < 0;
      final count = s.split(s[decimalAt]).length - 1;
      // `1,234` with one comma and three digits after it is a thousand, and so
      // is `1.234.567`; `1,2` and `6.7` are decimals.
      final grouping =
          onlyOneKind &&
          (count > 1 || after.length == 3 && s[decimalAt] == ',');
      if (grouping) {
        whole = s;
        fraction = '';
      } else {
        whole = s.substring(0, decimalAt);
        fraction = after;
      }
    }
    final digits = whole.replaceAll(RegExp(r'[.,]'), '');
    return double.tryParse(fraction.isEmpty ? digits : '$digits.$fraction');
  }

  static final _hours = RegExp(
    r'([0-9]+)\s*(?:h|hr|hrs|hour|hours)\b',
    caseSensitive: false,
  );
  static final _minutes = RegExp(
    r'([0-9]+)\s*(?:min|mins|minute|minutes)\b',
    caseSensitive: false,
  );
  static final _days = RegExp(
    r'([0-9]+)\s*(?:d|day|days)\b',
    caseSensitive: false,
  );

  /// `28 min`, `1 h 5 min`, `1 hr 5 min`, `2 days 3 hr`; null when [text] has
  /// no hours or minutes in it.
  static Duration? duration(String text) {
    final s = plain(text);
    final h = _hours.firstMatch(s);
    final m = _minutes.firstMatch(s);
    final d = _days.firstMatch(s);
    if (h == null && m == null) return null;
    return Duration(
      days: d == null ? 0 : int.parse(d.group(1)!),
      hours: h == null ? 0 : int.parse(h.group(1)!),
      minutes: m == null ? 0 : int.parse(m.group(1)!),
    );
  }

  static final _clock = RegExp(
    r'(?<![0-9])([0-9]{1,2})\s*[:.]\s*([0-9]{2})(?![0-9])(?:\s*([ap])\.?\s*m\.?)?',
    caseSensitive: false,
  );

  /// A time of day: `9:25 PM`, `21:25`, `9.25 pm`. The text it was found in, and
  /// the hour (0 to 23) and minute; null when there is none.
  static ({String text, int hour, int minute})? clock(String text) {
    final match = _clock.firstMatch(plain(text));
    if (match == null) return null;
    var hour = int.parse(match.group(1)!);
    final minute = int.parse(match.group(2)!);
    final marker = match.group(3)?.toLowerCase();
    if (minute > 59) return null;
    if (marker != null) {
      if (hour < 1 || hour > 12) return null;
      hour = hour % 12 + (marker == 'p' ? 12 : 0);
    } else if (hour > 23) {
      return null;
    }
    return (text: match.group(0)!.trim(), hour: hour, minute: minute);
  }

  /// Whether [text] has any digit in it, in any script.
  static bool hasDigit(String text) => RegExp(r'[0-9]').hasMatch(plain(text));
}
