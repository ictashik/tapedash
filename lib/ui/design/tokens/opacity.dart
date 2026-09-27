/// Alphas that recur in the components (DESIGN.md 6.14 and 6.16).
abstract final class TapeOpacity {
  /// A pressed chamfer button fills with 12% of its accent.
  static const double pressedFill = 0.12;

  /// A selected cell of a segmented selector fills with 16% of the accent.
  static const double selectedFill = 0.16;

  /// A disabled control is drawn at this share of its colour.
  static const double disabled = 0.45;

  /// The touch bloom starts at 35% and fades to nothing (DESIGN.md 6.16).
  static const double bloomStart = 0.35;

  /// The scrim behind a sheet: `void` at 60% (DESIGN.md 6.15).
  static const double scrim = 0.60;

  /// The surface of an overlay: `carbon.900` at 94% (DESIGN.md 6.15).
  static const double overlay = 0.94;

  /// The halo behind a lit toggle cell.
  static const double toggleHalo = 0.55;
}
