import 'dart:math' as math;
import 'dart:ui' show Color;

/// WCAG 2.x contrast, for the rules of DESIGN.md 11 and for the Daylight mode's
/// choice of numeral colour (DESIGN.md 4.4).
abstract final class Contrast {
  /// Relative luminance, 0 (black) to 1 (white). Alpha is ignored: composite a
  /// translucent colour with [over] first.
  static double luminance(Color color) {
    double channel(double c) => c <= 0.03928
        ? c / 12.92
        : math.pow((c + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(color.r) +
        0.7152 * channel(color.g) +
        0.0722 * channel(color.b);
  }

  /// The contrast ratio of two opaque colours, 1 to 21.
  static double ratio(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    final light = math.max(la, lb);
    final dark = math.min(la, lb);
    return (light + 0.05) / (dark + 0.05);
  }

  /// [foreground] drawn over an opaque [background], as an opaque colour.
  static Color over(Color foreground, Color background) {
    final a = foreground.a;
    return Color.from(
      alpha: 1,
      red: foreground.r * a + background.r * (1 - a),
      green: foreground.g * a + background.g * (1 - a),
      blue: foreground.b * a + background.b * (1 - a),
    );
  }
}
