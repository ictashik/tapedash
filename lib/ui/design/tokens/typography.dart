import 'dart:math' as math;
import 'dart:ui' show Color, FontFeature, FontVariation, FontWeight;

import 'package:flutter/painting.dart' show TextStyle;

/// The three families the app draws in, by the names `TapeFonts` registers them
/// under. Nothing else, never a system font or Roboto (DESIGN.md 4.5).
abstract final class TapeFontFamily {
  /// Variable, with weight and width axes: numerals, the wordmark, fault codes.
  static const String saira = 'Saira';

  /// Instrument labels and button labels.
  static const String barlowSemiCondensed = 'BarlowSemiCondensed';

  /// All parked UI text.
  static const String barlow = 'Barlow';
}

/// Sizes on the driving screens, which scale with the screen. [height] is the
/// height in logical pixels of the screen in landscape (DESIGN.md 4.5).
class TypeScale {
  const TypeScale._({
    required this.hero,
    required this.display,
    required this.primary,
    required this.secondary,
    required this.label,
  });

  /// The scale for a screen [height] logical pixels tall.
  factory TypeScale.forHeight(double height) => TypeScale._(
    hero: _scaled(height, 0.36, 96, 220),
    display: _scaled(height, 0.20, 56, 128),
    primary: _scaled(height, 0.12, 34, 72),
    secondary: _scaled(height, 0.075, 22, 44),
    label: _scaled(height, 0.036, 11, 16),
  );

  /// Speed.
  final double hero;

  /// Money on the Money page, and big secondary values.
  final double display;

  /// Flank values.
  final double primary;

  /// Tertiary values, and tape labels.
  final double secondary;

  /// Instrument labels.
  final double label;

  static double _scaled(double height, double share, double min, double max) =>
      math.min(max, math.max(min, height * share));
}

/// Text styles. Every style in the app is made here (DESIGN.md 13.1).
abstract final class TapeType {
  /// The `wdth` axis of Saira for numerals: wide, within DESIGN.md's 112 to 125.
  static const double numeralWidth = 118;

  /// A digit's ink height as a share of the font size, from Saira's design:
  /// cap height 0.688, with 0.008 of overshoot at each end.
  static const double digitHeightEm = 0.704;

  /// Where a digit's ink starts above the baseline, in em, overshoot included.
  static const double digitAboveBaselineEm = 0.696;

  /// How far apart the digits of a rolling column are, in em: a little more than
  /// a digit is tall, so that two digits passing each other do not touch.
  static const double digitPitchEm = 0.95;

  /// Instrument labels are tracked out by 12% of their size (DESIGN.md 4.5).
  static const double labelTracking = 0.12;

  /// Button labels are tracked out by 8% (DESIGN.md 6.14).
  static const double buttonTracking = 0.08;

  /// The wordmark's tracking, 6% (DESIGN.md 12).
  static const double wordmarkTracking = 0.06;

  /// The highest a parked screen scales text with the system font size
  /// (DESIGN.md 4.5). Driving screens ignore it.
  static const double maxParkedTextScale = 1.3;

  /// Barlow has no rupee sign, so a run of Barlow text falls back to Saira for
  /// it, and to nothing else.
  static const List<String> _fallback = [TapeFontFamily.saira];

  /// Saira as a numeral: wide, tabular, at the given [weight] (`wght`).
  ///
  /// [height] is the line height as a multiple of [size]; leave it null for the
  /// font's own, which is tall.
  static TextStyle numeral({
    required double size,
    required double weight,
    Color? color,
    double width = numeralWidth,
    double? height,
    double letterSpacing = 0,
  }) => TextStyle(
    fontFamily: TapeFontFamily.saira,
    fontSize: size,
    fontWeight: _nearestWeight(weight),
    fontVariations: [
      FontVariation('wght', weight),
      FontVariation('wdth', width),
    ],
    fontFeatures: const [FontFeature.tabularFigures()],
    color: color,
    height: height,
    letterSpacing: letterSpacing,
  );

  /// An instrument label: Barlow Semi Condensed Medium, tracked out. Write it in
  /// UPPERCASE.
  static TextStyle label({required double size, Color? color}) => TextStyle(
    fontFamily: TapeFontFamily.barlowSemiCondensed,
    fontFamilyFallback: _fallback,
    fontSize: size,
    fontWeight: FontWeight.w500,
    fontFeatures: const [FontFeature.tabularFigures()],
    letterSpacing: size * labelTracking,
    color: color,
    height: 1.0,
  );

  /// The label of a button: Barlow Semi Condensed SemiBold, in UPPERCASE.
  static TextStyle button({double size = 16, Color? color}) => TextStyle(
    fontFamily: TapeFontFamily.barlowSemiCondensed,
    fontFamilyFallback: _fallback,
    fontSize: size,
    fontWeight: FontWeight.w600,
    letterSpacing: size * buttonTracking,
    color: color,
    height: 1.0,
  );

  /// The wordmark: wide Saira SemiBold, tracked out.
  static TextStyle wordmark({required double size, Color? color}) => numeral(
    size: size,
    weight: 600,
    color: color,
    letterSpacing: size * wordmarkTracking,
    height: 1.0,
  );

  // Parked UI: fixed sizes in Barlow (DESIGN.md 4.5).

  static TextStyle headline({Color? color}) =>
      _parked(30, FontWeight.w600, color, 1.15);
  static TextStyle title({Color? color}) =>
      _parked(22, FontWeight.w600, color, 1.2);
  static TextStyle body({Color? color}) =>
      _parked(16, FontWeight.w400, color, 1.3);
  static TextStyle small({Color? color}) =>
      _parked(13, FontWeight.w400, color, 1.3);
  static TextStyle caption({Color? color}) =>
      _parked(12, FontWeight.w400, color, 1.3);

  static TextStyle _parked(
    double size,
    FontWeight weight,
    Color? color,
    double height,
  ) => TextStyle(
    fontFamily: TapeFontFamily.barlow,
    fontFamilyFallback: _fallback,
    fontSize: size,
    fontWeight: weight,
    fontFeatures: const [FontFeature.tabularFigures()],
    color: color,
    height: height,
  );

  static FontWeight _nearestWeight(double weight) {
    final index = (weight / 100).round().clamp(1, 9) - 1;
    return FontWeight.values[index];
  }
}
