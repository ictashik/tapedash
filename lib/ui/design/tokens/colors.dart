import 'dart:ui' show Color;

/// Colour tokens from DESIGN.md 4.3: the neutrals, money and state colours that
/// every livery shares. A livery adds the accent (`livery.dart`).
///
/// This is one of the few places a colour literal may be written (DESIGN.md
/// 13.1); everything else takes its colours from here or from the theme.
abstract final class TapeColors {
  // Neutrals

  /// `void`, #050607: the canvas behind everything, and the Android launch
  /// window colour. Not pure black, which looks grey-blue on cheap LCDs.
  ///
  /// Must match `tapedash_void` in `android/app/src/main/res/values/colors.xml`.
  static const Color voidColor = Color(0xFF050607);

  /// Vignette centre, and the surface of an overlay.
  static const Color carbon900 = Color(0xFF0B0D10);

  /// Raised surfaces, when parked.
  static const Color carbon800 = Color(0xFF11141A);

  /// Tracks and unlit segments.
  static const Color carbon700 = Color(0xFF1A1F27);

  /// Disabled and inactive tracks.
  static const Color carbon600 = Color(0xFF252B35);

  /// Grids and separators: white at 5%.
  static const Color etchFaint = Color.fromRGBO(255, 255, 255, 0.05);

  /// Ticks and frames: white at 9%.
  static const Color etch = Color.fromRGBO(255, 255, 255, 0.09);

  /// Major ticks and edges: white at 16%.
  static const Color etchStrong = Color.fromRGBO(255, 255, 255, 0.16);

  /// Labels and units. About 5:1 on `void`, the dimmest colour allowed for text.
  static const Color inkDim = Color(0xFF7A838F);

  /// Secondary values.
  static const Color inkMid = Color(0xFF9AA3AF);

  /// Primary values that are not in the accent.
  static const Color inkBright = Color(0xFFE7ECF1);

  /// Needle cores and peak highlights only.
  static const Color inkHot = Color(0xFFFFFFFF);

  /// The white that atlases and sprites are drawn in, before a colour role tints
  /// them. It is not a colour anything is shown in.
  static const Color spriteWhite = Color(0xFFFFFFFF);

  // Money. Champagne is the colour of money and is used for nothing else.

  static const Color moneyCore = Color(0xFFF3CF86);
  static const Color moneyDeep = Color(0xFFD6A042);
  static const Color moneyGlow = Color(0xFFFFC45C);

  // State

  /// Needs attention.
  static const Color caution = Color(0xFFFFB020);

  /// Act now, or redline.
  static const Color critical = Color(0xFFFF3355);

  /// Data older than 1.5 s.
  static const Color stale = inkDim;
}

/// The four colours the HUD can be set in (DESIGN.md 8). A windshield shows one
/// bold colour on black; critical alerts still use [TapeColors.critical].
enum HudColor {
  /// The default, and the most visible.
  green(Color(0xFF5CFF7A), 'Green'),
  ion(Color(0xFF5CE1FF), 'Ion'),
  amber(Color(0xFFFFB020), 'Amber'),
  white(Color(0xFFFFFFFF), 'White');

  const HudColor(this.color, this.label);

  final Color color;
  final String label;
}
