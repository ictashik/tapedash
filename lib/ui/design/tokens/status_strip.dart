/// The status strip's geometry and motion (DESIGN.md 6.9).
abstract final class TapeStatusStrip {
  /// The glyph's square size.
  static const double glyphSize = 20;

  /// The clock's digit size (secondary, not a hero numeral).
  static const double clockSize = 22;

  /// The Parked-only caption under a glyph.
  static const double captionSize = 10;

  /// Gap between a glyph and its neighbour, or a glyph and its caption.
  static const double gap = 6;

  /// A glyph column's width once its Parked-mode caption is showing: wide
  /// enough for the longest caption this strip uses ("SEARCHING", "PHONE
  /// HOT") so two neighbouring captions never run into each other. In
  /// Motion mode, with no caption to fit, a column is just [glyphSize] wide.
  static const double captionColumnWidth = 60;

  /// The adapter glyph pulses (breathes) at this rate while searching
  /// (DESIGN.md 6.9), well under the 3 Hz flash ceiling (DESIGN.md 11) --
  /// this is a slow breathing, not a flash.
  static const double searchPulseHz = 0.5;

  /// The pulse's alpha range, a share of the glyph's normal (lit) alpha.
  static const double searchPulseAlphaMin = 0.35;
  static const double searchPulseAlphaMax = 1.0;

  /// The DEMO badge's chamfer and inset (a small chamfered outline, DESIGN.md
  /// 6.9), matching the chamfer family used by other small controls.
  static const double badgeChamfer = 4;
  static const double badgePaddingH = 8;
  static const double badgePaddingV = 3;
}
