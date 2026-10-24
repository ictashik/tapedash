import 'nav_state.dart';
import 'nav_text.dart';

/// A figure for the HUD: the number as it is to be written, and its unit as a
/// label. A unit is null where the figure is Google's text, which is shown as it
/// came because it could not be read.
class NavFigure {
  const NavFigure(this.value, [this.unit]);

  final String value;
  final String? unit;

  @override
  bool operator ==(Object other) =>
      other is NavFigure && other.value == value && other.unit == unit;

  @override
  int get hashCode => Object.hash(value, unit);

  @override
  String toString() => unit == null ? value : '$value $unit';
}

/// What the navigation HUD writes (DESIGN.md 8), from a [NavState]: figures to
/// the precision the car's other figures have, never more than Maps gave
/// (CLAUDE.md 1.6). Pure, so the words are tested without a screen.
class NavFormat {
  const NavFormat._();

  static final _figure = RegExp(
    r'^([0-9]+(?:[.,][0-9]+)?)\s*([^\s0-9.,]+)\.?$',
  );

  /// The distance to the turn as Maps wrote it: `650 m` is 650 and M. A distance
  /// in a unit that was not read is shown in Google's own text.
  static NavFigure? distanceToTurn(NavState s) {
    final text = s.distanceText;
    if (text == null || text.trim().isEmpty) return null;
    final match = _figure.firstMatch(NavText.plain(text).trim());
    if (match == null) return NavFigure(text.trim());
    return NavFigure(match.group(1)!, match.group(2)!.toUpperCase());
  }

  /// The distance left to the destination, in the units Maps wrote in: whole
  /// kilometres from a hundred, tenths from one, and metres in steps of 50 under
  /// that (a distance in feet likewise, in miles).
  static NavFigure? distanceLeft(NavState s) {
    final metres = s.distanceLeftM;
    if (metres == null) return null;
    if (s.imperial) {
      final miles = metres / 1609.344;
      if (miles < 0.1) {
        return NavFigure(_step(metres / 0.3048, 50), 'FT');
      }
      return NavFigure(_big(miles), 'MI');
    }
    if (metres < 950) {
      return NavFigure(_step(metres, metres < 100 ? 10 : 50), 'M');
    }
    return NavFigure(_big(metres / 1000), 'KM');
  }

  /// The time left: minutes, and from an hour hours and minutes (`1:05` and H).
  static NavFigure? timeLeft(NavState s) {
    final d = s.timeLeft;
    if (d == null) return null;
    final minutes = (d.inSeconds / 60).round().clamp(1, 1 << 30);
    if (minutes < 60) return NavFigure('$minutes', 'MIN');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return NavFigure('${minutes ~/ 60}:$m', 'H');
  }

  static final _marker = RegExp(r'\s*([AaPp])\.?\s*[Mm]\.?$');

  /// The ETA as Maps wrote it, its AM or PM taken off to be a label of its own.
  static NavFigure? eta(NavState s) {
    final text = s.etaText;
    if (text == null || text.trim().isEmpty) return null;
    final plain = NavText.plain(text).trim();
    final match = _marker.firstMatch(plain);
    if (match == null) return NavFigure(plain);
    return NavFigure(
      plain.substring(0, match.start),
      '${match.group(1)!.toUpperCase()}M',
    );
  }

  static String _step(double value, int step) =>
      '${((value / step).round() * step)}';

  /// One decimal under a hundred, whole above.
  static String _big(double value) =>
      value < 100 ? value.toStringAsFixed(1) : value.round().toString();
}
