/// The strength and size of halos (DESIGN.md 4.9). A halo is a pre-rendered
/// blurred sprite, composited with `BlendMode.plus`. Nothing is blurred at runtime.
abstract final class TapeGlow {
  /// A hero readout's halo: 25 to 35%.
  static const double heroHalo = 0.30;

  /// A needle's halo: 60%.
  static const double needleHalo = 0.60;

  /// The blur of a numeral's halo, as a share of its font size.
  static const double numeralSigmaEm = 0.09;

  /// At most this many halos above [strongThreshold] may be on screen at once
  /// (DESIGN.md 4.9).
  static const int maxStrongHalos = 3;
  static const double strongThreshold = 0.5;

  /// Halo sprites in Tier 1 are drawn at half resolution (DESIGN.md 9.1).
  static const double liteResolution = 0.5;
}
